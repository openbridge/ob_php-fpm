FROM alpine:3.7
MAINTAINER Thomas Spicer (thomas@openbridge.com)

ENV VAR_PREFIX=/var/run
ENV LOG_PREFIX=/var/log/php-fpm
ENV TEMP_PREFIX=/tmp
ENV CACHE_PREFIX=/var/cache

RUN set -x \
  && addgroup -g 82 -S www-data \
  && adduser -u 82 -D -S -h /var/cache/php-fpm -s /sbin/nologin -G www-data www-data \
  && apk add --no-cache --virtual .build-deps \
      wget \
      linux-headers \
      curl \
      unzip \
  && echo '@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories \
  && echo '@community http://nl.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories \
  && apk add --no-cache --update \
      php7 \
      php7-bcmath \
      php7-dom \
      php7-common \
      php7-ctype \
      php7-cli \
      php7-curl \
      php7-fileinfo \
      php7-fpm \
      php7-gd \
      php7-iconv \
      php7-intl \
      php7-json \
      php7-mbstring \
      php7-mcrypt \
      php7-mysqli \
      php7-mysqlnd \
      php7-opcache \
      php7-openssl \
      php7-pdo \
      php7-pdo_mysql \
      php7-pdo_pgsql \
      php7-pdo_sqlite \
      php7-phar \
      php7-posix \
      php7-redis@testing \
      php7-session \
      php7-soap \
      php7-tokenizer \
      php7-xml \
      php7-xmlreader \
      php7-xmlwriter \
      php7-zip \
      php7-zlib \
      curl \
      monit \
      bash \
      xz \
      ca-certificates \
      openssl \
      tar \
  && mkdir -p /var/run \
  && rm -rf /tmp/* \
  && rm -rf /var/cache/apk/*

COPY conf/monit/ /etc/monit.d/
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY check_wwwdata.sh /usr/bin/check_wwwdata
RUN chmod +x /docker-entrypoint.sh /usr/bin/check_wwwdata

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["php-fpm7", "-g", "/var/run/php-fpm.pid"]
