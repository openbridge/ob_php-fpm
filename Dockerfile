# syntax=docker/dockerfile:1.4

# Stage 1: Builder Stage
FROM php:8.4-fpm-alpine AS builder

LABEL maintainer="Thomas Spicer (thomas@openbridge.com)"

# Set build arguments with default values
ARG IMAGICK_VERSION=3.7.0

# Install build dependencies more efficiently
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        icu-dev \
        freetype-dev \
        imagemagick-dev \
        ghostscript-dev \
        libzip-dev \
        libavif-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        libwebp-dev \
        mariadb-dev \
        gcc \
        musl-dev \
        make \
        msgpack-c-dev \
    && apk add --no-cache \
        icu-libs \
        libzip \
        imagemagick \
        libjpeg-turbo \
        libpng \
        freetype \
        libwebp \
        bash \
        openssl \
        mariadb-client \
        ca-certificates \
        file

# Configure and install PHP extensions in a single layer
RUN --mount=type=cache,target=/tmp \
    docker-php-ext-configure gd \
        --with-freetype \
        --with-avif \
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
    # Install Imagick
    && curl -L -o /tmp/imagick.tar.gz https://github.com/Imagick/imagick/archive/tags/${IMAGICK_VERSION}.tar.gz \
    && tar --strip-components=1 -xf /tmp/imagick.tar.gz \
    && sed -i 's/php_strtolower/zend_str_tolower/g' imagick.c \
    && phpize \
    && ./configure \
    && make \
    && make install \
    && echo "extension=imagick.so" > /usr/local/etc/php/conf.d/ext-imagick.ini \
    # Install Redis
    && pecl install redis msgpack \
    && docker-php-ext-enable redis msgpack mysqli pdo_mysql

# Install WP-CLI
RUN curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# Clean up build dependencies
RUN apk del .build-deps \
    && rm -rf /tmp/* /var/cache/apk/*

# Stage 2: Final Image
FROM php:8.4-fpm-alpine

# Set environment variables
ENV LOG_PREFIX=/var/log/php-fpm \
    TEMP_PREFIX=/tmp \
    CACHE_PREFIX=/var/cache

# Install runtime dependencies efficiently
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
        bash \
        autoconf \
        ck \
        hiredis \
        hiredis-ssl \
        lz4-libs \
        zstd-libs \
        icu-libs \
        libzip \
        imagemagick \
        ghostscript \
        openssl \
        ca-certificates \
        libjpeg-turbo \
        libpng \
        libavif \
        libgomp \
        freetype \
        libwebp \
        mariadb-client \
        file \
        tini \
        msgpack-c

# Copy built extensions and tools from builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/bin/wp /usr/local/bin/wp

# Create necessary directories and configure logging
RUN mkdir -p /var/run/php-fpm "${LOG_PREFIX}" \
    && touch "${LOG_PREFIX}/access.log" "${LOG_PREFIX}/error.log" \
    && ln -sf /dev/stdout "${LOG_PREFIX}/access.log" \
    && ln -sf /dev/stderr "${LOG_PREFIX}/error.log"

# Copy configuration files and scripts
COPY --chmod=755 docker-entrypoint.sh /docker-entrypoint.sh
COPY --chmod=755 scripts/ /usr/src/plugins/

# Ensure www-data is the working user and owns the necessary directories
RUN set -ex \
    && id -u www-data || adduser -u 82 -D -S -G www-data www-data \
    && mkdir -p /var/www/html \
    && chown -R www-data:www-data /var/www/html

EXPOSE 9000

ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
CMD ["php-fpm"]