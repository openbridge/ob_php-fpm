# Use the official PHP image with PHP 8.2 and FPM
FROM php:8.2-fpm-alpine

LABEL maintainer="Thomas Spicer (thomas@openbridge.com)"

# Set environment variables
ENV LOG_PREFIX=/var/log/php-fpm
ENV TEMP_PREFIX=/tmp
ENV CACHE_PREFIX=/var/cache

# Create necessary directories and logs, and adjust permissions
RUN set -ex \
  && mkdir -p /var/run/php-fpm \
  && mkdir -p ${LOG_PREFIX} \
  && touch ${LOG_PREFIX}/access.log \
  && touch ${LOG_PREFIX}/error.log \
  && ln -sf /dev/stdout ${LOG_PREFIX}/access.log \
  && ln -sf /dev/stderr ${LOG_PREFIX}/error.log

# Install additional dependencies and PHP extensions
RUN set -ex \
  && apk add --no-cache \
      bash \
      icu-libs \
      libzip \
      imagemagick \
      monit \
      openssl \
      ca-certificates \
  && apk add --no-cache --virtual .build-deps \
      $PHPIZE_DEPS \
      icu-dev \
      freetype-dev \
      imagemagick-dev \
      libzip-dev \
      libpng-dev \
      libjpeg-turbo-dev \ 
  # Configure and install PHP extensions
  && docker-php-ext-configure gd \
      --with-freetype=/usr/include/ \
      --with-jpeg=/usr/include/ \
  && docker-php-ext-install -j"$(nproc)" \
      bcmath \
      exif \
      gd \
      intl \
      pdo_mysql \
      mysqli \
      zip \
  && pecl install imagick-3.6.0 \
  && pecl install redis \ 
  && docker-php-ext-enable imagick \
  && docker-php-ext-enable redis \ 
  && apk del .build-deps \
  && rm -rf /tmp/* /var/cache/apk/*

# Copy configuration files and scripts
COPY conf/monit/ /etc/monit.d/
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY check_wwwdata.sh /usr/bin/check_wwwdata
COPY check_folder.sh /usr/bin/check_folder

# Expose port 9000
EXPOSE 9000

# Make scripts executable
RUN chmod +x /docker-entrypoint.sh /usr/bin/check_wwwdata /usr/bin/check_folder

# Set the entrypoint and default command
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["php-fpm"]
