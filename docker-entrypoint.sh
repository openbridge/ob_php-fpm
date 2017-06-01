#!/usr/bin/env bash

function php-fpm() {
# Setting the php-fpm configs
  {
              echo '[global]'
              echo 'include=/etc/php7/php-fpm.d/*.conf'
  } | tee /etc/php7/php-fpm.conf

  {
              echo '[global]'
              echo 'error_log = /proc/self/fd/2'
              echo
              echo '[www]'
              echo '; if we send this to /proc/self/fd/1, it never appears'
              echo 'access.log = /proc/self/fd/2'
              echo
              echo 'clear_env = no'
              echo
              echo '; Ensure worker stdout and stderr are sent to the main error log.'
              echo 'catch_workers_output = yes'
  } | tee /etc/php7/php-fpm.d/docker.conf

  {
              echo '[global]'
              echo 'daemonize = no'
              echo
              echo '[www]'
              echo 'listen = [::]:9000'
              echo 'listen.owner = www-data'
              echo 'listen.group = www-data'
              echo 'user = www-data'
              echo 'group = www-data'
              echo 'pm = dynamic'
              echo 'pm.max_children = 50'
              echo 'pm.max_requests = 200'
              echo 'pm.start_servers = 10'
              echo 'pm.min_spare_servers = 5'
              echo 'pm.max_spare_servers = 10'
  } | tee /etc/php7/php-fpm.d/zz-docker.conf

}

function monit() {

# Start Monit
cat << EOF > /etc/monitrc
set daemon 10
set pidfile /var/run/monit.pid
set statefile /var/run/monit.state
set httpd port 2849 and
    use address localhost
    allow localhost
set logfile syslog
set eventqueue
    basedir /var/run
    slots 100
include /etc/monit.d/*
EOF

  chmod 700 /etc/monitrc
  run="monit -c /etc/monitrc" && bash -c "${run}"

}

function run() {
  php-fpm
  monit

  echo "OK: All processes have completed. Service is ready..."
}

run

exec "$@"
