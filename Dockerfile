# Use the official PHP image with PHP 8.3 and FPM
FROM php:8.3-fpm-alpine

LABEL maintainer="Thomas Spicer (thomas@openbridge.com)"

# Set environment variables
ENV LOG_PREFIX=/var/log/php-fpm
ENV TEMP_PREFIX=/tmp
ENV CACHE_PREFIX=/var/cache

# Create necessary directories and logs, and adjust permissions
RUN set -ex \
    && mkdir -p /var/run/php-fpm \
    && mkdir -p "${LOG_PREFIX}" \
    && touch "${LOG_PREFIX}/access.log" \
    && touch "${LOG_PREFIX}/error.log" \
    && ln -sf /dev/stdout "${LOG_PREFIX}/access.log" \
    && ln -sf /dev/stderr "${LOG_PREFIX}/error.log"

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
        libjpeg-turbo \
        libpng \
        freetype \
        libgomp \
        libwebp \
    && apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        icu-dev \
        freetype-dev \
        imagemagick-dev \
        libzip-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        libwebp-dev \
    # Configure and install PHP extensions
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        pdo_mysql \
        mysqli \
        zip \
    && pecl install redis \
    && docker-php-ext-enable redis \
    # Install Imagick with patch
    && curl -fL -o imagick.tgz 'https://pecl.php.net/get/imagick-3.7.0.tgz' \
    && echo '5a364354109029d224bcbb2e82e15b248be9b641227f45e63425c06531792d3e *imagick.tgz' | sha256sum -c - \
    && tar --extract --directory /tmp --file imagick.tgz imagick-3.7.0 \
    && grep '^//#endif$' /tmp/imagick-3.7.0/Imagick.stub.php \
    && test "$(grep -c '^//#endif$' /tmp/imagick-3.7.0/Imagick.stub.php)" = '1' \
    && sed -i -e 's!^//#endif$!#endif!' /tmp/imagick-3.7.0/Imagick.stub.php \
    && grep '^//#endif$' /tmp/imagick-3.7.0/Imagick.stub.php && exit 1 || : \
    && docker-php-ext-install /tmp/imagick-3.7.0 \
    && rm -rf imagick.tgz /tmp/imagick-3.7.0 \
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

# Set the entrypoint script to be run on container start
ENTRYPOINT ["/usr/bin/env", "bash", "/docker-entrypoint.sh"]

CMD ["php-fpm"]
