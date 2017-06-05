# Overview

This is a Docker image creates a high performance, optimized container for PHP-FPM. The image also includes configuration enhancements for;
* Alpine Linux
* Opcache
* Dynamic Resource Allocation
* Monitoring
* Security
* and many others.


# Versioning
| Docker Tag | Git Hub Release | PHP Version | Alpine Version |
|-----|-------|-----|--------|
| latest | Master | 7.1.5 | 3.6 |

# Build
```
docker build -t openbridge/php-fpm .
```
# Run
```bash
docker run -it --rm \
    -p 9000:9000 \
    -e "APP_DOCROOT=/html " \
    --name php-fpm \
    openbridge/php-fpm
```
Via Docker compose
```
docker-compose up -d
```
# App Root

The default root app directory is `/app`. If you want to change this default you need to see `APP_DOCROOT` via ENV variable. For example, if you want to use `/html` as your root you would set `APP_DOCROOT=/html`

# Docker Volume
To mount your web app or html files you will need to mount the volume on the host that contains your files. Make sure you are setting the `APP_DOCROOT` in your run or `docker-compose.yml` file
```docker
-v /your/webapp/path:{{APP_DOCROOT}}:ro
```
You can also set the cache directory to leverage in-memory cache like `tmpfs`:
```docker
-v /tmpfs:{{CACHE_PREFIX}}:ro
```

You can do the same thing for config files if you wanted to use versions of what we have provided. Just make sure you are mapping locations correctly as NGINX and PHP expect files to be in certain locations.

# Configuration
The following represents the structure of the PHP configs used in this image:

```bash
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
              echo '; ping.path = /ping'
              echo '; Ensure worker stdout and stderr are sent to the main error log.'
              echo 'catch_workers_output = yes'
  } | tee /etc/php7/php-fpm.d/docker.conf

  {
              echo '[global]'
              echo 'daemonize = no'
              echo
              echo '[www]'
              echo 'listen = [::]:{{PHP_FPM_PORT}}'
              echo 'listen.mode = 0666'
              echo 'listen.owner = www-data'
              echo 'listen.group = www-data'
              echo 'user = www-data'
              echo 'group = www-data'
              echo 'pm = dynamic'
              echo 'pm.max_children = {{PHP_MAX_CHILDREN}}'
              echo 'pm.max_requests = 500'
              echo 'pm.start_servers = {{PHP_START_SERVERS}}'
              echo 'pm.min_spare_servers = {{PHP_MIN_SPARE_SERVERS}}'
              echo 'pm.max_spare_servers = {{PHP_MAX_SPARE_SERVERS}}'
  } | tee /etc/php7/php-fpm.d/zz-docker.conf

  {
              echo 'max_executionn_time=300'
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
              echo 'upload_max_filesize=50M'
              echo 'post_max_size=50M'
              echo 'file_uploads=On'
              echo
              echo 'opcache.enable=1'
              echo 'opcache.enable_cli=0'
              echo 'opcache.save_comments=1'
              echo 'opcache.interned_strings_buffer=8'
              echo 'opcache.fast_shutdown=1'
              echo 'opcache.validate_timestamps=2'
              echo 'opcache.revalidate_freq=60'
              echo 'opcache.use_cwd=1'
              echo 'opcache.max_accelerated_files=100000'
              echo 'opcache.max_wasted_percentage=5'
              echo 'opcache.memory_consumption={{PHP_OPCACHE_MEMORY_CONSUMPTION}}M'
              echo 'opcache.consistency_checks=0'
              echo 'opcache.huge_code_pages=1'
              echo
              echo ';opcache.file_cache_only=1'
              echo ';opcache.file_cache=/html/.opcache'
              echo ';opcache.file_cache_consistency_checks=1'

  } | tee /etc/php7/conf.d/50-setting.ini
```

## Dynamic Resource Allocation
The PHP and cache settings are a function of the available system resources. This allocation factors in available memory and CPU which is assigned proportionately. The proportion of resources was defined according to researched best practices and reading PHP docs.

```bash
# Setting the php-fpm configs
 TOTALCPU=$(grep -c ^processor /proc/cpuinfo); echo "${TOTALCPU}"
 TOTALMEM=$(free -m | awk '/^Mem:/{print $2}'); echo "${TOTALMEM}"

 PHP_START_SERVERS=$(($TOTALCPU / 2)); echo "${PHP_START_SERVERS}"
 PHP_MIN_SPARE_SERVERS=$(($TOTALCPU / 2)); echo "${PHP_MIN_SPARE_SERVERS}"
 PHP_MAX_SPARE_SERVERS="${TOTALCPU}"; echo "${PHP_MAX_SPARE_SERVERS}"
 PHP_MEMORY_LIMIT=$(($TOTALMEM / 2)); echo "${PHP_MEMORY_LIMIT}"
 PHP_OPCACHE_MEMORY_CONSUMPTION=$(($TOTALMEM / 6)); echo "${PHP_OPCACHE_MEMORY_CONSUMPTION}"
 PHP_MAX_CHILDREN=$(($TOTALCPU * 2)); echo "${PHP_MAX_CHILDREN}"
 ```

# Cache
Opcache is enabled by default. The available cache memory is determined by the available system resources.

# Logging
Logs are sent to stdout and stderr PHP-FPM.
You will likely want to dispatch these logs to a service like Amazon Cloudwatch. This will allow you to setup alerts and triggers to perform tasks based on container activity.

# Monitoring
Services in the container are monitored via Monit. One thing to note is that if Monit detects a problem with Nginx it will issue a `STOP` command. THis will shutdown your container because the image uses `CMD ["php-fpm7", "-g", "/var/run/php-fpm.pid"]`. If you are using `--restart always` in your docker run command the server will automatically restart.

```bash
check process php-fpm with pidfile "/var/run/php-fpm.pid"
      if not exist for 10 cycles then restart
      start program = "/bin/bash -c /usr/sbin/php-fpm7 -g /var/run/php-fpm.pid" with timeout 90 seconds
      stop program = "/bin/bash -c /usr/bin/pkill -INT php-fpm"
      every 3 cycles
      if failed port 9000
        # Send FastCGI packet: version 1 (0x01), cmd FCGI_GET_VALUES (0x09)
        # padding 8 bytes (0x08), followed by 8xNULLs padding
        send "\0x01\0x09\0x00\0x00\0x00\0x00\0x08\0x00\0x00\0x00\0x00\0x00\0x00\0x00\0x00\0x00"
        # Expect FastCGI packet: version 1 (0x01), resp FCGI_GET_VALUES_RESULT (0x0A)
        expect "\0x01\0x0A"
        timeout 5 seconds
      then restart

check program wwwdata-owner with path /usr/bin/env bash -c "check_wwwdata owner"
      every 3 cycles
      if status != 0 then exec "/usr/bin/env bash -c 'find {{APP_DOCROOT}} -type d -exec chown www-data:www-data {} \; && find {{APP_DOCROOT}} -type f -exec chown www-data:www-data {} \;'"

check program wwwdata-permissions with path /usr/bin/env bash -c "check_wwwdata permission"
      every 3 cycles
      if status != 0 then exec "/usr/bin/env bash -c 'find {{APP_DOCROOT}} -type d -exec chmod 755 {} \; && find {{APP_DOCROOT}} -type f -exec chmod 644 {} \;'"

check directory cache-permissions with path {{CACHE_PREFIX}}
      every 3 cycles
      if failed permission 755 then exec "/usr/bin/env bash -c 'find {{CACHE_PREFIX}} -type d -exec chmod 755 {} \;'"

check directory cache-owner with path {{CACHE_PREFIX}}
      every 3 cycles
      if failed uid www-data then exec "/usr/bin/env bash -c 'find {{CACHE_PREFIX}} -type d -exec chown www-data:www-data {} \; && find {{CACHE_PREFIX}} -type f -exec chown www-data:www-data {} \;'"
```

# Plugins

# TODO

# Issues

If you have any problems with or questions about this image, please contact us through a GitHub issue.

# Contributing

You are invited to contribute new features, fixes, or updates, large or small; we are always thrilled to receive pull requests, and do our best to process them as fast as we can.

Before you start to code, we recommend discussing your plans through a GitHub issue, especially for more ambitious contributions. This gives other contributors a chance to point you in the right direction, give you feedback on your design, and help you find out if someone else is working on the same thing.

# References

PHP

* https://www.kinamo.be/en/support/faq/determining-the-correct-number-of-child-processes-for-php-fpm-on-nginx
* https://www.if-not-true-then-false.com/2011/nginx-and-php-fpm-configuration-and-optimizing-tips-and-tricks/
* https://www.tecklyfe.com/adjusting-child-processes-php-fpm-nginx-fix-server-reached-pm-max_children-setting/
* https://serversforhackers.com/video/php-fpm-process-management
* https://devcenter.heroku.com/articles/php-concurrency

The image is based on the office NGINX docker image:
* https://github.com/docker-library/php

# License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details