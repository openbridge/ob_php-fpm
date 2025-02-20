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

#######################################
# Logging function
#######################################
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

#######################################
# Generates fallback salts if the API fails
#######################################
function generate_fallback_salts() {
  local keys=("AUTH" "SECURE_AUTH" "LOGGED_IN" "NONCE")
  local salt=""
  local chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-={}[]|:;<>,.?~`'
  
  for key in "${keys[@]}"; do
    local random_string=""
    for i in {1..64}; do
      random_string+="${chars:$((RANDOM % ${#chars})):1}"
    done
    salt+="define('${key}_KEY', '${random_string}');\n"
    
    random_string=""
    for i in {1..64}; do
      random_string+="${chars:$((RANDOM % ${#chars})):1}"
    done
    salt+="define('${key}_SALT', '${random_string}');\n"
  done
  
  echo -e "$salt"
}

#######################################
# Downloads WordPress using wp-cli
#######################################
function wordpress_install_wp_cli() {
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
function wordpress_install_curl() {
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
  unzip -q "${wp_zip}" -d /tmp

  # Move files from the extracted "wordpress" folder to the document root
  cp -r /tmp/wordpress/* ./
  rm -rf /tmp/wordpress "${wp_zip}"
  chown -R www-data:www-data "${APP_DOCROOT}"
}

#######################################
# Configures WordPress and installs plugins
#######################################
function wordpress_config() {
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

\$table_prefix = 'wp_';
define('WP_DEBUG', false);

// Modified HTTPS detection
\$is_https = false;
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO'])) {
    \$is_https = \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https';
} elseif (isset(\$_SERVER['HTTPS'])) {
    \$is_https = \$_SERVER['HTTPS'] === 'on';
}
\$_SERVER['HTTPS'] = \$is_https ? 'on' : 'off';

// Redis Configuration (if using Redis caching)
define('WP_REDIS_HOST', '${REDIS_UPSTREAM_HOST:-127.0.0.1}');
define('WP_REDIS_PORT', ${REDIS_UPSTREAM_PORT:-6379});
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
define('WP_REDIS_POOL_SIZE', 10);

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
}

#######################################
# Sets appropriate file and directory permissions
#######################################
function cleanup() {
  log "Setting file permissions..."
  find "${APP_DOCROOT}" ! -user www-data -exec chown www-data:www-data {} \;
  find "${APP_DOCROOT}" -type d ! -perm 755 -exec chmod 755 {} \;
  find "${APP_DOCROOT}" -type f ! -perm 644 -exec chmod 644 {} \;
}

#######################################
# Main installation function
#######################################
function run() {
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
    wordpress_config
    cleanup
  else
    log "WordPress appears to be already installed."
  fi
}

# Execute the main function
run

exit 0
