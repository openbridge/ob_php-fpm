#!/usr/bin/env bash
# Enable strict mode for safer bash scripting
set -euo pipefail

# Trap errors and display line number
trap 'echo "Error on line $LINENO"; exit 1' ERR

#######################################
# Required environment variables
#######################################
: "${APP_DOCROOT:?APP_DOCROOT is not set}"
: "${WORDPRESS_DB_NAME:?WORDPRESS_DB_NAME is not set}"
: "${WORDPRESS_DB_USER:?WORDPRESS_DB_USER is not set}"
: "${WORDPRESS_DB_PASSWORD:?WORDPRESS_DB_PASSWORD is not set}"
: "${WORDPRESS_DB_HOST:?WORDPRESS_DB_HOST is not set}"
: "${NGINX_SERVER_NAME:?NGINX_SERVER_NAME is not set}"
: "${WORDPRESS_ADMIN:?WORDPRESS_ADMIN is not set}"
: "${WORDPRESS_ADMIN_PASSWORD:?WORDPRESS_ADMIN_PASSWORD is not set}"
: "${WORDPRESS_ADMIN_EMAIL:?WORDPRESS_ADMIN_EMAIL is not set}"

# Optional: Specify a version (or leave empty for latest)
WORDPRESS_VERSION="${WORDPRESS_VERSION:-}"

# INSTALL_METHOD can be "wp" or "curl". Defaults to "wp" (with fallback to curl)
INSTALL_METHOD="${INSTALL_METHOD:-wp}"

# OPcache settings with defaults
OPCACHE_PRELOAD_ENABLE="${OPCACHE_PRELOAD_ENABLE:-0}"
OPCACHE_PRELOAD_PATH="${OPCACHE_PRELOAD_PATH:-${APP_DOCROOT}/001-preload.php}"

# Redis settings with defaults
REDIS_UPSTREAM_HOST="${REDIS_UPSTREAM_HOST:-127.0.0.1}"
REDIS_UPSTREAM_PORT="${REDIS_UPSTREAM_PORT:-6379}"

#######################################
# Logging function
#######################################
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

#######################################
# Dependency check function
#######################################
check_dependency() {
  command -v "$1" >/dev/null 2>&1 || { log "$1 is required but not installed. Aborting."; exit 1; }
}

# Check required commands
check_dependency curl
check_dependency unzip
check_dependency openssl

# If INSTALL_METHOD is not set to 'curl', verify WP-CLI is available
if [[ "$INSTALL_METHOD" != "curl" ]]; then
  if ! command -v wp >/dev/null 2>&1; then
    log "WP-CLI not found. Falling back to curl installation."
    INSTALL_METHOD="curl"
  fi
fi


#######################################
# Generates fallback salts if the API fails
#######################################
generate_fallback_salts() {
  local keys=("AUTH" "SECURE_AUTH" "LOGGED_IN" "NONCE")
  local salts=""

  for key in "${keys[@]}"; do
    local auth_key
    auth_key=$(openssl rand -base64 48)
    local auth_salt
    auth_salt=$(openssl rand -base64 48)
    salts+="define('${key}_KEY', '${auth_key}');\n"
    salts+="define('${key}_SALT', '${auth_salt}');\n"
  done

  echo -e "$salts"
}


#######################################
# Downloads WordPress using wp-cli
#######################################
wordpress_install_wp_cli() {
  log "Installing WordPress via WP-CLI method..."
  mkdir -p "${APP_DOCROOT}"
  cd "${APP_DOCROOT}" || exit

  # Attempt to download the core files with wp-cli
  if ! wp --allow-root core download ${WORDPRESS_VERSION:+--version="$WORDPRESS_VERSION"} --path="${APP_DOCROOT}"; then
    log "WP-CLI download failed. Falling back to curl method..."
    wordpress_install_curl
    return
  fi

  chown -R www-data:www-data "${APP_DOCROOT}"
}

#######################################
# Downloads WordPress using curl (fallback method)
#######################################
wordpress_install_curl() {
  log "Installing WordPress via curl method..."
  mkdir -p "${APP_DOCROOT}"
  cd "${APP_DOCROOT}" || exit

  local wp_zip="wordpress.zip"
  local download_url="https://wordpress.org/latest.zip"
  if [ -n "$WORDPRESS_VERSION" ]; then
    download_url="https://wordpress.org/wordpress-${WORDPRESS_VERSION}.zip"
  fi

  log "Downloading WordPress from ${download_url}..."
  curl -fSL "${download_url}" -o "${wp_zip}"
  log "Download complete; unzipping..."

  # Create a temporary directory for extraction
  local tmp_dir
  tmp_dir=$(mktemp -d)

  unzip -q "${wp_zip}" -d "${tmp_dir}"

  # Move files from the extracted "wordpress" folder to the document root
  cp -r "${tmp_dir}/wordpress/"* ./

  # Cleanup temporary directory and zip file
  rm -rf "${tmp_dir}" "${wp_zip}"
  chown -R www-data:www-data "${APP_DOCROOT}"
}


#######################################
# Configures WordPress and installs plugins
#######################################
wordpress_config() {
  log "Configuring WordPress..."

  local MAX_RETRIES=3
  local RETRY_DELAY=5
  local SALT_URL="https://api.wordpress.org/secret-key/1.1/salt/"

  local retries=0
  local success=false
  local wp_salts=""

  log "Fetching WordPress salts..."
  while [ $retries -lt $MAX_RETRIES ] && [ "$success" = false ]; do
    wp_salts=$(curl -s -f "$SALT_URL") && success=true || {
      retries=$((retries + 1))
      if [ $retries -lt $MAX_RETRIES ]; then
        log "Attempt $retries failed. Retrying in $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
      else
        log "Failed to fetch salts after $MAX_RETRIES attempts; generating fallback salts..."
        wp_salts=$(generate_fallback_salts)
        success=true
      fi
    }
  done

  cd "${APP_DOCROOT}" || exit

  if [[ "${OPCACHE_PRELOAD_ENABLE}" == "1" ]]; then
    log "Generating OPcache preload script at ${OPCACHE_PRELOAD_PATH}..."
    
    # Create the preload script
    cat <<'EOF' > "${OPCACHE_PRELOAD_PATH}"
<?php
/**
 * OPcache Preload File for WordPress
 *
 * This script precompiles a curated list of WordPress core files into OPcache.
 * It's meant to be used with PHP 7.4+ with opcache.preload enabled.
 */
if (!function_exists('opcache_compile_file')) {
    return;
}

// Define an array of core files to preload.
$preload_files = [
    __DIR__ . '/wp-includes/load.php',
    __DIR__ . '/wp-includes/functions.php',
    __DIR__ . '/wp-includes/class-wp-hook.php',
    __DIR__ . '/wp-includes/post.php',
    __DIR__ . '/wp-includes/formatting.php',
    __DIR__ . '/wp-includes/query.php',
    __DIR__ . '/wp-includes/class-wpdb.php',
    __DIR__ . '/wp-includes/cache.php',
    __DIR__ . '/wp-includes/option.php',
    __DIR__ . '/wp-includes/template.php',
    __DIR__ . '/wp-includes/class-wp-query.php',
    __DIR__ . '/wp-includes/class-wp.php',
    __DIR__ . '/wp-includes/theme.php',
    __DIR__ . '/wp-settings.php',
];

foreach ($preload_files as $file) {
    if (file_exists($file)) {
        opcache_compile_file($file);
    }
}
EOF
  fi  # Close the if OPCACHE_PRELOAD_ENABLE condition

# Create the wp-config.php file
cat <<EOF > wp-config.php
<?php
define('DB_NAME', '${WORDPRESS_DB_NAME}');
define('DB_USER', '${WORDPRESS_DB_USER}');
define('DB_PASSWORD', '${WORDPRESS_DB_PASSWORD}');
define('DB_HOST', '${WORDPRESS_DB_HOST}');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

// Salts
$wp_salts

\$table_prefix = '${WORDPRESS_TABLE_PREFIX:-wp_}';
define('WP_DEBUG', ${WORDPRESS_DEBUG:-false});

// Improved HTTPS detection
\$is_https = false;
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    \$is_https = true;
} elseif (isset(\$_SERVER['HTTP_X_FORWARDED_SSL']) && \$_SERVER['HTTP_X_FORWARDED_SSL'] === 'on') {
    \$is_https = true;
} elseif (isset(\$_SERVER['HTTPS']) && \$_SERVER['HTTPS'] === 'on') {
    \$is_https = true;
}
\$_SERVER['HTTPS'] = \$is_https ? 'on' : 'off';

// Redis Configuration (if using Redis caching)
define('WP_REDIS_HOST', '${REDIS_UPSTREAM_HOST}');
define('WP_REDIS_PORT', ${REDIS_UPSTREAM_PORT});
define('WP_REDIS_DATABASE', 1);
define('WP_REDIS_PREFIX', 'wp_cache:');
define('WP_REDIS_MAXTTL', 86400);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_RETRY_INTERVAL', 100);
define('WP_REDIS_COMPRESSION', true);
define('WP_REDIS_COMPRESSION_LEVEL', 6);
define('WP_REDIS_SELECTIVE_FLUSH', true);
define('WP_REDIS_GRACEFUL', true);
define('WP_REDIS_PERSISTENT', true);
define('WP_REDIS_SERIALIZER', 'msgpack');

// Global groups for Redis (optional)
define('WP_REDIS_GLOBAL_GROUPS', [
    'blog-details',
    'blog-id-cache',
    'blog-lookup',
    'global-posts',
    'networks',
    'sites',
    'site-details',
    'site-lookup',
    'site-options',
    'site-transient',
    'users',
    'useremail',
    'userlogins',
    'usermeta',
    'user_meta',
    'userslugs',
]);

define('WP_REDIS_IGNORED_GROUPS', ['counts', 'plugins']);
define('FORCE_SSL_ADMIN', true);
define('DISALLOW_FILE_EDIT', false);
define('FS_METHOD', 'direct');
define('WP_CACHE', true);

if (!defined('ABSPATH')) {
    define('ABSPATH', dirname(__FILE__) . '/');
}
require_once(ABSPATH . 'wp-settings.php');
EOF

  log "Running WordPress core install..."
  wp --allow-root --path="${APP_DOCROOT}" core install \
    --url="https://${NGINX_SERVER_NAME}" \
    --title="${NGINX_SERVER_NAME}" \
    --admin_user="${WORDPRESS_ADMIN}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL}"

  log "Updating admin user password..."
  wp --allow-root --path="${APP_DOCROOT}" user update "${WORDPRESS_ADMIN}" \
    --user_pass="${WORDPRESS_ADMIN_PASSWORD}" --allow-root

  log "Deleting default plugins (akismet, hello)..."
  wp --allow-root --path="${APP_DOCROOT}" plugin delete akismet hello

  log "Setting permalink structure..."
  wp --allow-root --path="${APP_DOCROOT}" rewrite structure '/%postname%/' --hard

  log "Installing and activating additional plugins..."
  wp --allow-root --path="${APP_DOCROOT}" plugin install amp antispam-bee nginx-helper wp-mail-smtp --activate

  log "WordPress configuration complete."
  log "Username: ${WORDPRESS_ADMIN} | Password: ${WORDPRESS_ADMIN_PASSWORD}"
  echo "Username: ${WORDPRESS_ADMIN} | Password: ${WORDPRESS_ADMIN_PASSWORD}" > /home/creds.txt
  chmod 600 /home/creds.txt

}

#######################################
# Sets appropriate file and directory permissions
#######################################
cleanup() {
  log "Setting file permissions..."
  # Change ownership for files and directories not owned by www-data
  find "${APP_DOCROOT}" ! -user www-data -exec chown www-data:www-data {} +
  
  # Set directory permissions to 755
  find "${APP_DOCROOT}" -type d ! -perm 755 -exec chmod 755 {} +
  
  # Set file permissions to 644
  find "${APP_DOCROOT}" -type f ! -perm 644 -exec chmod 644 {} +
}

#######################################
# Main installation function
#######################################
run() {
  if [[ ! -f "${APP_DOCROOT}/wp-config.php" ]]; then
    # Choose installation method based on INSTALL_METHOD or wp-cli availability
    if [[ "$INSTALL_METHOD" == "curl" ]]; then
      wordpress_install_curl
    else
      if command -v wp >/dev/null 2>&1; then
        wordpress_install_wp_cli
      else
        log "WP-CLI not found; falling back to curl method..."
        wordpress_install_curl
      fi
    fi

     # Add this snippet to copy your object cache file into wp-content
    log "Copying object cache file..."
    cp "/usr/src/plugins/${NGINX_APP_PLUGIN}/object-cache.php" "${APP_DOCROOT}/wp-content/object-cache.php"

    wordpress_config
    cleanup
  else
    log "WordPress appears to be already installed."
  fi
}

# Execute the main function
run

exit 0