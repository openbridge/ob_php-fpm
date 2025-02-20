#!/bin/bash
#
# Docker Entrypoint for PHP-FPM, Redis, and Monitoring Configuration

set -euo pipefail

# Globals and Default Values
: "${PHP_MAX_EXECUTION_TIME:=300}"
: "${PHP_FPM_CONF_DIR:=/usr/local/etc}"
: "${PHP_MEMORY_LIMIT:=128}"  # Changed default to 128M
: "${PHP_POST_MAX_SIZE:=50}"
: "${PHP_UPLOAD_MAX_FILESIZE:=50}"
: "${PHP_OPCACHE_ENABLE:=1}"
: "${PHP_FPM_UPSTREAM_PORT:=9000}"
: "${REDIS_UPSTREAM_HOST:=redis}"
: "${REDIS_UPSTREAM_PORT:=6379}"
: "${LOG_PREFIX:=/var/log/php-fpm}"
: "${DEBUG:=0}"                        

# Debug Mode
if [[ "$DEBUG" == "1" ]]; then
  set -x
  echo "DEBUG: Loaded environment variables:"
  env | grep -E 'PHP_|APP_|CACHE_|REDIS_'
fi

# Function: Calculate optimal PHP-FPM settings based on available resources
calculate_fpm_settings() {
    # Get total RAM and CPU cores
    TOTAL_RAM_MB=$(grep MemTotal /proc/meminfo | awk '{print $2 / 1024}')
    CPU_CORES=$(nproc)
    
    echo "INFO: Total RAM: ${TOTAL_RAM_MB}MB"
    echo "INFO: CPU cores: ${CPU_CORES}"

    # Calculate available RAM for PHP processes (30% of total RAM as per your original script)
    PHP_AVAILABLE_RAM_MB=$(awk "BEGIN {print $TOTAL_RAM_MB * 0.30}")
    
    # Use memory limit from environment or calculate based on available RAM
    if [ -z "${PHP_MEMORY_LIMIT-}" ]; then
        # Calculate memory limit as 20% of PHP available RAM
        PHP_MEMORY_LIMIT=$(awk "BEGIN {printf \"%.0f\", $PHP_AVAILABLE_RAM_MB * 0.20}")
        # Ensure memory limit is between 128MB and 1024MB
        if [ "$(awk "BEGIN {print ($PHP_MEMORY_LIMIT < 128)}")" -eq 1 ]; then
            PHP_MEMORY_LIMIT=128
        elif [ "$(awk "BEGIN {print ($PHP_MEMORY_LIMIT > 1024)}")" -eq 1 ]; then
            PHP_MEMORY_LIMIT=1024
        fi
    fi

    # Calculate max children based on available RAM and memory limit
    PHP_MAX_CHILDREN=$(awk "BEGIN {print int($PHP_AVAILABLE_RAM_MB / $PHP_MEMORY_LIMIT)}")
    
    # Ensure minimum of 2 children even on very constrained systems
    if [ "$PHP_MAX_CHILDREN" -lt 2 ]; then
        PHP_MAX_CHILDREN=2
    fi

    # Calculate other FPM settings with safe minimums
    START_SERVERS=$(( (PHP_MAX_CHILDREN + 1) / 2 ))
    if [ "$START_SERVERS" -lt 2 ]; then
        START_SERVERS=2
    fi

    MIN_SPARE_SERVERS=$(( START_SERVERS - 1 ))
    if [ "$MIN_SPARE_SERVERS" -lt 1 ]; then
        MIN_SPARE_SERVERS=1
    fi

    MAX_SPARE_SERVERS=$((PHP_MAX_CHILDREN - 1))
    if [ "$MAX_SPARE_SERVERS" -le "$MIN_SPARE_SERVERS" ]; then
        MAX_SPARE_SERVERS=$((MIN_SPARE_SERVERS + 1))
    fi
    
    # Calculate max requests before worker restart
    MAX_REQUESTS=$((PHP_MAX_CHILDREN * 100))
    if [ "$MAX_REQUESTS" -gt 1000 ]; then
        MAX_REQUESTS=1000
    fi

    # Calculate OPcache memory (5% of PHP available RAM)
    OPCACHE_MEMORY_MB=$(awk "BEGIN {print int($PHP_AVAILABLE_RAM_MB * 0.05)}")
    if [ "$OPCACHE_MEMORY_MB" -lt 64 ]; then
        OPCACHE_MEMORY_MB=64
    elif [ "$OPCACHE_MEMORY_MB" -gt 512 ]; then
        OPCACHE_MEMORY_MB=512
    fi

    echo "INFO: Configured settings:"
    echo "- Memory limit: ${PHP_MEMORY_LIMIT}MB"
    echo "- PHP max children: $PHP_MAX_CHILDREN"
    echo "- Start servers: $START_SERVERS"
    echo "- Min spare servers: $MIN_SPARE_SERVERS"
    echo "- Max spare servers: $MAX_SPARE_SERVERS"
    echo "- Max requests: $MAX_REQUESTS"
    echo "- OPcache memory: ${OPCACHE_MEMORY_MB}MB"
}

# Function: Configure PHP-FPM
php_fpm() {
    echo "INFO: Configuring PHP-FPM..."
    calculate_fpm_settings
    
    mkdir -p "${APP_DOCROOT}" "${LOG_PREFIX}" "${CACHE_PREFIX}/fastcgi"

    # Create PHP-FPM Configuration Files
    cat <<EOF > "${PHP_FPM_CONF_DIR}/php-fpm.conf"
[global]
include=${PHP_FPM_CONF_DIR}/php-fpm.d/*.conf
EOF

    cat <<EOF > "${PHP_FPM_CONF_DIR}/php-fpm.d/docker.conf"
[global]
error_log = ${LOG_PREFIX}/error.log
log_level = error
emergency_restart_threshold = 10
emergency_restart_interval = 1m
process_control_timeout = 10s

[www]
access.log = ${LOG_PREFIX}/access.log
clear_env = no
catch_workers_output = yes
request_terminate_timeout = ${PHP_MAX_EXECUTION_TIME}s
EOF

    cat <<EOF > "${PHP_FPM_CONF_DIR}/php-fpm.d/zz-docker.conf"
[global]
daemonize = no

[www]
user = www-data
group = www-data
listen = [::]:${PHP_FPM_UPSTREAM_PORT}
listen.mode = 0660
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = ${PHP_MAX_CHILDREN}
pm.start_servers = ${START_SERVERS}
pm.min_spare_servers = ${MIN_SPARE_SERVERS}
pm.max_spare_servers = ${MAX_SPARE_SERVERS}
pm.max_requests = ${MAX_REQUESTS}
pm.status_path = /status
EOF

    cat <<EOF > "${PHP_FPM_CONF_DIR}/php/conf.d/50-setting.ini"
max_execution_time=${PHP_MAX_EXECUTION_TIME}
memory_limit=${PHP_MEMORY_LIMIT}M
upload_max_filesize=${PHP_UPLOAD_MAX_FILESIZE}M
post_max_size=${PHP_POST_MAX_SIZE}M
file_uploads=On
max_input_vars=${PHP_MAX_INPUT_VARS:-10000}
error_reporting=E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors=Off
display_startup_errors=Off
log_errors=On
error_log=${LOG_PREFIX}/php_errors.log
user_ini.filename=
realpath_cache_size=4M
realpath_cache_ttl=120
date.timezone=UTC
short_open_tag=Off
session.auto_start=Off

; OpCache settings
opcache.enable=${PHP_OPCACHE_ENABLE}
opcache.memory_consumption=${OPCACHE_MEMORY_MB}
opcache.max_accelerated_files=10000
opcache.validate_timestamps=1
opcache.revalidate_freq=2
opcache.enable_cli=0
opcache.save_comments=1
opcache.interned_strings_buffer=16
opcache.fast_shutdown=1
opcache.use_cwd=1
opcache.max_wasted_percentage=5
opcache.consistency_checks=0
opcache.huge_code_pages=1
opcache.file_cache="${CACHE_PREFIX}/fastcgi/.opcache"
opcache.file_cache_only=1
opcache.file_cache_consistency_checks=1
EOF

    echo "INFO: PHP-FPM configured successfully."
}


# Function: Configure Redis
redis() {
  if [[ -n "$REDIS_UPSTREAM_HOST" ]]; then
    echo "INFO: Configuring Redis..."
    cat <<EOF > "${PHP_FPM_CONF_DIR}/php/conf.d/zz-redis-setting.ini"
session.gc_maxlifetime=86400
session.save_handler=redis
session.save_path="tcp://$REDIS_UPSTREAM_HOST:$REDIS_UPSTREAM_PORT?weight=1&timeout=2.5&database=3"
EOF
    echo "INFO: Redis configured successfully."
  else
    echo "INFO: Redis not configured. Either Redis is not installed or REDIS_UPSTREAM is not set."
  fi
}


# Function: Install Plugins
install_plugin() {
  if [[ ! -d /usr/src/plugins/${NGINX_APP_PLUGIN} ]]; then
    echo "INFO: NGINX_APP_PLUGIN is not located in the plugin directory. Nothing to install..."
  else
    echo "OK: Installing NGINX_APP_PLUGIN=${NGINX_APP_PLUGIN}..."
    sleep 10
    chmod +x "/usr/src/plugins/${NGINX_APP_PLUGIN}/install.sh"
    bash -x /usr/src/plugins/${NGINX_APP_PLUGIN}/install.sh
  fi
}

# Function: Configure Permissions
set_permissions() {
  echo "INFO: Setting ownership and permissions..."

  # Set ownership for all files and directories
  find "${APP_DOCROOT}" ! -user www-data -exec chown www-data:www-data {} +
  find "${APP_DOCROOT}" -type d ! -perm 755 -exec chmod 755 {} +
  find "${APP_DOCROOT}" -type f ! -perm 644 -exec chmod 644 {} +

  echo "INFO: Ownership and permissions configured successfully."
}

# Function: Main Run
run() {
  php_fpm
  redis
  install_plugin
  set_permissions
  echo "INFO: Entry script completed. Starting PHP-FPM..."
}

# Execute the main run function
run

# Replace the current process with the CMD passed in the Dockerfile
exec "$@"