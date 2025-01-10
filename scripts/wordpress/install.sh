#!/usr/bin/env bash

# WordPress Installer and Configuration Script
#
# This script automates the process of installing and configuring WordPress.
# It includes functions for downloading WordPress, setting up the configuration,
# installing necessary plugins, and configuring SSL.

#######################################
# Downloads and sets up WordPress core files
# Globals:
#   APP_DOCROOT
#   WORDPRESS_VERSION
# Arguments:
#   None
#######################################
function wordpress_install() {
  echo "================================================================="
  echo "WordPress Installer"
  echo "================================================================="

  # Ensure that the document root directory exists
  mkdir -p "${APP_DOCROOT}"
  cd "${APP_DOCROOT}" || exit

  # Download the WordPress core files
  wp --allow-root core download --version="${WORDPRESS_VERSION}" --path="${APP_DOCROOT}"

  # Set the correct permissions on the files
  chown -R www-data:www-data "${APP_DOCROOT}"
}

#######################################
# Configures WordPress and installs necessary plugins
# Globals:
#   APP_DOCROOT
#   WORDPRESS_DB_NAME
#   WORDPRESS_DB_USER
#   WORDPRESS_DB_PASSWORD
#   WORDPRESS_DB_HOST
#   NGINX_SERVER_NAME
#   WORDPRESS_ADMIN
#   WORDPRESS_ADMIN_PASSWORD
#   WORDPRESS_ADMIN_EMAIL
# Arguments:
#   None
#######################################

# Function to generate fallback salts if the API fails

function generate_fallback_salts() {
    local keys=("AUTH" "SECURE_AUTH" "LOGGED_IN" "NONCE")
    local salt=""
    local chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-={}[]|:;<>,.?~` '
    
    for key in "${keys[@]}"; do
        # Generate KEY with exact WordPress format
        local random_string=$(for i in {1..64}; do echo -n "${chars:RANDOM%${#chars}:1}"; done)
        salt+="define('${key}_KEY',         '${random_string}');\n"
        
        # Generate SALT with exact WordPress format
        random_string=$(for i in {1..64}; do echo -n "${chars:RANDOM%${#chars}:1}"; done)
        salt+="define('${key}_SALT',        '${random_string}');\n"
    done
    
    echo -e "$salt"
}

function wordpress_config() {
  echo "================================================================="
  echo "WordPress Configuration"
  echo "================================================================="

  MAX_RETRIES=3
  RETRY_DELAY=5
  SALT_URL="https://api.wordpress.org/secret-key/1.1/salt/"

  local retries=0
  local success=false
  local wp_salts=""

  echo "Fetching WordPress salts..."

  while [ $retries -lt $MAX_RETRIES ] && [ "$success" = false ]; do
        # Try to fetch salts using curl
        wp_salts=$(curl -s -f "$SALT_URL")
        
        # Check if curl was successful and we got content
        if [ $? -eq 0 ] && [ ! -z "$wp_salts" ]; then
            success=true
            echo "Successfully fetched WordPress salts"
        else
            retries=$((retries + 1))
            if [ $retries -lt $MAX_RETRIES ]; then
                echo "Attempt $retries failed. Retrying in $RETRY_DELAY seconds..."
                sleep $RETRY_DELAY
            else
                echo "Error: Failed to fetch WordPress salts after $MAX_RETRIES attempts"
                
                # Provide fallback random salts if the API fails
                wp_salts=$(generate_fallback_salts)
                echo "Generated fallback salts"
                success=true
            fi
        fi
  done

  cd "${APP_DOCROOT}" || exit

  # Create wp-config.php file
  cat <<EOF > ./wp-config.php
<?php

define('DB_NAME', '${WORDPRESS_DB_NAME}');
define('DB_USER', '${WORDPRESS_DB_USER}');
define('DB_PASSWORD', '${WORDPRESS_DB_PASSWORD}');
define('DB_HOST', '${WORDPRESS_DB_HOST}');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

// Insert the salts directly
$wp_salts

\$table_prefix = 'wp_';

define('WP_DEBUG', false);

// Modified HTTPS detection
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    \$_SERVER['HTTPS'] = 'on';
} elseif (isset(\$_SERVER['HTTPS']) && \$_SERVER['HTTPS'] === 'on') {
    // HTTPS is already set correctly
} else {
    // Default to HTTP
    \$_SERVER['HTTPS'] = 'off';
}

define('FORCE_SSL_ADMIN', true);
define('DISALLOW_FILE_EDIT', false);
define('RT_WP_NGINX_HELPER_CACHE_PATH', '/var/cache');
define('WP_REDIS_HOST', '$REDIS_UPSTREAM_HOST');
define('WP_REDIS_PORT', $REDIS_UPSTREAM_PORT);                       // Ensure port is defined
define('WP_REDIS_DATABASE', 1);                      // Optional: Specify Redis database
define('WP_REDIS_PREFIX', 'wp_cache:');              // Optional: Define a prefix to prevent key collisions
define('FS_METHOD', 'direct');

if (!defined('ABSPATH')) {
    define('ABSPATH', dirname(__FILE__) . '/');
}

require_once(ABSPATH . 'wp-settings.php');
EOF

  # Configure the site with wp-cli
  wp --allow-root --path="${APP_DOCROOT}" core install --url="https://${NGINX_SERVER_NAME}" \
    --title="${NGINX_SERVER_NAME}" --admin_user="${WORDPRESS_ADMIN}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL}"

  wp --allow-root --path="${APP_DOCROOT}" user update "${WORDPRESS_ADMIN}" \
    --user_pass="${WORDPRESS_ADMIN_PASSWORD}" --allow-root

  # Delete default plugins
  wp --allow-root --path="${APP_DOCROOT}" plugin delete akismet hello

  # Set permalink structure
  wp --allow-root --path="${APP_DOCROOT}" rewrite structure '/%postname%/' --hard

  # Install and activate plugins
  wp --allow-root --path="${APP_DOCROOT}" plugin install amp antispam-bee nginx-helper wp-mail-smtp redis-cache --activate

  # Copy object cache file if it exists
  if [[ -f ${APP_DOCROOT}/wp-content/plugins/redis-cache/includes/object-cache.php ]]; then
    cp "${APP_DOCROOT}/wp-content/plugins/redis-cache/includes/object-cache.php" \
      "${APP_DOCROOT}/wp-content/"
  fi

  echo "================================================================="
  echo "Installation is complete. Your username/password is listed below."
  echo ""
  echo "Username: ${WORDPRESS_ADMIN}"
  echo "Password: ${WORDPRESS_ADMIN_PASSWORD}"
  echo ""
  echo "================================================================="
  echo "Username: ${WORDPRESS_ADMIN} | Password: ${WORDPRESS_ADMIN_PASSWORD}" > /home/creds.txt
}

#######################################
# Cleans up after installation
# Globals:
#   APP_DOCROOT
# Arguments:
#   None
#######################################
function cleanup() {
  # Correct file and directory permissions
  find "${APP_DOCROOT}" ! -user www-data -exec chown www-data:www-data {} \;
  find "${APP_DOCROOT}" -type d ! -perm 755 -exec chmod 755 {} \;
  find "${APP_DOCROOT}" -type f ! -perm 644 -exec chmod 644 {} \;

}

#######################################
# Main function to run the WordPress installation
# Globals:
#   APP_DOCROOT
# Arguments:
#   None
#######################################
function run() {
  if [[ ! -f ${APP_DOCROOT}/wp-config.php ]]; then
    wordpress_install
    wordpress_config
    cleanup
  else
    echo "OK: Wordpress already seems to be installed."
  fi
}

# Execute the main function
run

exit 0