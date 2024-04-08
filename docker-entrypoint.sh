#!/bin/bash

#---------------------------------------------------------------------
# Configure PHP-FPM
#---------------------------------------------------------------------

php_fpm() {
  local cpu mem

  # Determine the PHP-FPM runtime environment
  cpu=$(grep -c ^processor /proc/cpuinfo)
  printf "%s\n" "${cpu}"

  mem=$(free -m | awk '/^Mem:/{print $2}')
  printf "%s\n" "${mem}"

  local total_cpu=$((cpu > 2 ? cpu : 2))

  # PHP-FPM settings
  PHP_START_SERVERS=${PHP_START_SERVERS:-$((total_cpu / 2))}
  PHP_MIN_SPARE_SERVERS=${PHP_MIN_SPARE_SERVERS:-$((total_cpu / 2))}
  PHP_MAX_SPARE_SERVERS=${PHP_MAX_SPARE_SERVERS:-${total_cpu}}
  PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-$((mem / 2))}
  PHP_MAX_CHILDREN=${PHP_MAX_CHILDREN:-$((total_cpu * 2))}
  PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE:-50}
  PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_FILESIZE:-50}
  PHP_MAX_INPUT_VARS=${PHP_MAX_INPUT_VARS:-1000}
  PHP_MAX_EXECUTION_TIME=${PHP_MAX_EXECUTION_TIME:-300}

  # Opcache settings
  PHP_OPCACHE_ENABLE=${PHP_OPCACHE_ENABLE:-1}
  PHP_OPCACHE_MEMORY_CONSUMPTION=${PHP_OPCACHE_MEMORY_CONSUMPTION:-$((mem / 6))}

  # Set the listening port and document root
  PHP_FPM_PORT=${PHP_FPM_PORT:-9000}
  APP_DOCROOT=${APP_DOCROOT:-/app}

  mkdir -p "${APP_DOCROOT}"

  # Configuration file creation
  create_config_files

  # Set the configurations with the environment variables
  set_configurations
}

create_config_files() {
  {
    echo '[global]'
    echo 'include=/usr/local/etc/php-fpm.d/*.conf'
  } | tee /usr/local/etc/php-fpm.conf

  {
    echo '[global]'
    echo 'error_log = {{LOG_PREFIX}}/error.log'
    echo
    echo '[www]'
    echo '; if we send this to /proc/self/fd/1, it never appears'
    echo 'access.log = {{LOG_PREFIX}}/access.log'
    echo
    echo 'clear_env = no'
    echo '; ping.path = /ping'
    echo '; Ensure worker stdout and stderr are sent to the main error log.'
    echo 'catch_workers_output = yes'
  } | tee /usr/local/etc/php-fpm.d/docker.conf

  {
    echo '[global]'
    echo 'daemonize = no'
    echo 'log_level = error'
    echo
    echo '[www]'
    echo 'user = www-data'
    echo 'group = www-data'
    echo 'listen = [::]:{{PHP_FPM_PORT}}'
    echo 'listen.mode = 0666'
    echo 'listen.owner = www-data'
    echo 'listen.group = www-data'
    echo 'pm = static'
    echo 'pm.max_children = {{PHP_MAX_CHILDREN}}'
    echo 'pm.max_requests = 1000'
    echo 'pm.start_servers = {{PHP_START_SERVERS}}'
    echo 'pm.min_spare_servers = {{PHP_MIN_SPARE_SERVERS}}'
    echo 'pm.max_spare_servers = {{PHP_MAX_SPARE_SERVERS}}'
  } | tee /usr/local/etc/php-fpm.d/zz-docker.conf

  {
    echo 'max_execution_time={{PHP_MAX_EXECUTION_TIME}}'
    echo 'memory_limit={{PHP_MEMORY_LIMIT}}M'
    echo 'error_reporting=1'
    echo 'display_errors=0'
    echo 'log_errors=1'
    echo 'user_ini.filename='
    echo 'realpath_cache_size=2M'
    echo 'cgi.check_shebang_line=0'
    echo 'date.timezone=UTC'
    echo 'short_open_tag=Off'
    echo 'session.auto_start=Off'
    echo 'max_execution_time = 60'
    echo 'upload_max_filesize={{PHP_UPLOAD_MAX_FILESIZE}}M'
    echo 'post_max_size={{PHP_POST_MAX_SIZE}}M'
    echo 'file_uploads=On'
    echo 'max_input_vars={{PHP_MAX_INPUT_VARS}}'

    echo
    echo 'opcache.enable={{PHP_OPCACHE_ENABLE}}'
    echo 'opcache.enable_cli=0'
    echo 'opcache.save_comments=1'
    echo 'opcache.interned_strings_buffer=8'
    echo 'opcache.fast_shutdown=1'
    echo 'opcache.validate_timestamps=1'
    echo 'opcache.revalidate_freq=2'
    echo 'opcache.use_cwd=1'
    echo 'opcache.max_accelerated_files=100000'
    echo 'opcache.max_wasted_percentage=5'
    echo 'opcache.memory_consumption={{PHP_OPCACHE_MEMORY_CONSUMPTION}}M'
    echo 'opcache.consistency_checks=0'
    echo 'opcache.huge_code_pages=1'
    echo
    echo ';opcache.file_cache="{{CACHE_PREFIX}}/fastcgi/.opcache"'
    echo ';opcache.file_cache_only=1'
    echo ';opcache.file_cache_consistency_checks=1'
  } | tee /usr/local/etc/php/conf.d/50-setting.ini

  mkdir -p "${CACHE_PREFIX}"/fastcgi/

  # Set the configs with the ENV Var
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{CACHE_PREFIX}}|'"${CACHE_PREFIX}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_FPM_PORT}}|'"${PHP_FPM_PORT}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_START_SERVERS}}|'"${PHP_START_SERVERS}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_MIN_SPARE_SERVERS}}|'"${PHP_MIN_SPARE_SERVERS}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_MAX_SPARE_SERVERS}}|'"${PHP_MAX_SPARE_SERVERS}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_MEMORY_LIMIT}}|'"${PHP_MEMORY_LIMIT}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_OPCACHE_ENABLE}}|'"${PHP_OPCACHE_ENABLE}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_OPCACHE_MEMORY_CONSUMPTION}}|'"${PHP_OPCACHE_MEMORY_CONSUMPTION}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_MAX_CHILDREN}}|'"${PHP_MAX_CHILDREN}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{LOG_PREFIX}}|'"${LOG_PREFIX}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_POST_MAX_SIZE}}|'"${PHP_POST_MAX_SIZE}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_UPLOAD_MAX_FILESIZE}}|'"${PHP_UPLOAD_MAX_FILESIZE}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_MAX_INPUT_VARS}}|'"${PHP_MAX_INPUT_VARS}"'|g' {} \;
  find /usr/local/etc/ -maxdepth 3 -type f -exec sed -i -e 's|{{PHP_MAX_EXECUTION_TIME}}|'"${PHP_MAX_EXECUTION_TIME}"'|g' {} \;

}

set_configurations() {
  local config_path='/usr/local/etc/'
  local find_expr='s|{{\s*([^}\s]+)\s*}}|${\1}|g'

  # Replace placeholders with the actual environment variables
  find "${config_path}" -maxdepth 3 -type f -exec sed -i -e "${find_expr}" {} \;
}

#---------------------------------------------------------------------
# Configure PHP connection to Redis
#---------------------------------------------------------------------

redis() {
  {
    echo 'session.gc_maxlifetime=86400'
    echo 'session.save_handler=redis'
    echo 'session.save_path="tcp://{{REDIS_UPSTREAM}}?weight=1&timeout=2.5&database=3"'
  } | tee /usr/local/etc/php/conf.d/zz-redis-setting.ini

  find /usr/local/etc/php/conf.d/ -maxdepth 3 -type f -exec sed -i -e 's|{{REDIS_UPSTREAM}}|'"${REDIS_UPSTREAM}"'|g' {} \;

}

#---------------------------------------------------------------------
# Configure the use of a plugin (install script) for WordPress or similar
#---------------------------------------------------------------------

install_plugin() {
  if [[ ! -d /usr/src/plugins/$NGINX_APP_PLUGIN ]]; then
    echo "INFO: NGINX_APP_PLUGIN is not located in the plugin directory. Nothing to install..."
  else
    echo "OK: Installing NGINX_APP_PLUGIN=$NGINX_APP_PLUGIN..."
    sleep 10
    chmod +x "/usr/src/plugins/$NGINX_APP_PLUGIN/install"
    "/usr/src/plugins/$NGINX_APP_PLUGIN/install"
  fi
}

#---------------------------------------------------------------------
# Configure Monit
#---------------------------------------------------------------------

monit() {
  {
    echo 'set daemon 10'
    echo '    with START DELAY 10'
    echo 'set pidfile /var/run/monit.pid'
    echo 'set statefile /var/run/monit.state'
    echo 'set httpd port 2849 and'
    echo '    use address localhost'
    echo '    allow localhost'
    echo 'set logfile syslog'
    echo 'set eventqueue'
    echo '    basedir /var/run'
    echo '    slots 100'
    echo 'include /etc/monit.d/*'
  } | tee /etc/monitrc

  # Start monit
  find "/etc/monit.d" -maxdepth 4 -type f -exec sed -i -e 's|{{APP_DOCROOT}}|'"${APP_DOCROOT}"'|g' {} \;
  find "/etc/monit.d" -maxdepth 4 -type f -exec sed -i -e 's|{{CACHE_PREFIX}}|'"${CACHE_PREFIX}"'|g' {} \;
  find "/etc/monit.d" -maxdepth 4 -type f -exec sed -i -e 's|{{PHP_FPM_PORT}}|'"${PHP_FPM_PORT}"'|g' {} \;

  chmod 700 /etc/monitrc
  run="monit -c /etc/monitrc" && bash -c "${run}"
}

#---------------------------------------------------------------------
# Set correct permissions for php-fpm
#---------------------------------------------------------------------

permissions() {
  echo "Setting ownership and permissions on APP_ROOT and CACHE_PREFIX... "

  # This assumes you are using the common www-data for your user and group in NGINX and PHP-FPM. If you are using different users this is usually a recipe for error.

  find ${APP_DOCROOT} ! -user www-data -exec /usr/bin/env bash -c 'i="$1"; chown www-data:www-data "$i"' _ {} \;
  find ${APP_DOCROOT} ! -perm 755 -type d -exec /usr/bin/env bash -c 'i="$1"; chmod 755  "$i"' _ {} \;
  find ${APP_DOCROOT} ! -perm 644 -type f -exec /usr/bin/env bash -c 'i="$1"; chmod 644 "$i"' _ {} \;
  find ${CACHE_PREFIX} ! -perm 755 -type d -exec /usr/bin/env bash -c 'i="$1"; chmod 755  "$i"' _ {} \;
  find ${CACHE_PREFIX} ! -perm 644 -type f -exec /usr/bin/env bash -c 'i="$1"; chmod 644 "$i"' _ {} \;

}

#---------------------------------------------------------------------
# Run all the functions to start the services
#---------------------------------------------------------------------

run() {
  php_fpm
  [[ -z $REDIS_UPSTREAM ]] && echo "OK: Redis is not present so we will not activate it" || redis
  monit
  [[ -z $NGINX_APP_PLUGIN ]] && echo "OK: No plugins will be activated" || install_plugin
  # permissions
  echo "OK: All processes have completed. Service is ready..."
}

run

exec "$@"
