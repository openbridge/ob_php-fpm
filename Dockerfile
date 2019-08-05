FROM alpine:3.10
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
      openssl-dev \
  && echo ' http://dl-cdn.alpinelinux.org/alpine/v3.9/community' >> /etc/apk/repositories \
  && apk add --no-cache --update \
      php7 \
      php7-dev \
      php7-bcmath \
      php7-dom \
      php7-common \
      php7-ctype \
      php7-cli \
      php7-curl \
      php7-fileinfo \
      php7-fpm \
      php7-gettext \
      php7-gd \
      php7-iconv \
      php7-json \
      php7-mbstring \
      php7-mcrypt \
      php7-mysqli \
      php7-mysqlnd \
      php7-opcache \
      php7-odbc \
      php7-pdo \
      php7-pdo_mysql \
      php7-pdo_pgsql \
      php7-pdo_sqlite \
      php7-phar \
      php7-posix \
      php7-redis \
      php7-session \
      php7-simplexml \
      php7-soap \
      php7-tokenizer \
      php7-xml \
      php7-xmlreader \
      php7-xmlwriter \
      php7-simplexml \
      php7-zip \
      php7-zlib \
      mysql-client\
      curl \
      monit \
      bash \
      xz \
      openssl \
      icu-libs \
      ca-certificates \
      libxml2-dev \
      tar \
  && mkdir -p /var/run \
  && mkdir -p ${LOG_PREFIX} \
  && rm -rf /tmp/* \
  && rm -rf /var/cache/apk/* \
  && touch ${LOG_PREFIX}/access.log \
  && touch ${LOG_PREFIX}/error.log \
  && ln -sf /dev/stdout ${LOG_PREFIX}/access.log \
  && ln -sf /dev/stderr ${LOG_PREFIX}/error.log

COPY conf/monit/ /etc/monit.d/
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY check_wwwdata.sh /usr/bin/check_wwwdata
COPY check_folder.sh /usr/bin/check_folder

EXPOSE 9000

RUN chmod +x /docker-entrypoint.sh /usr/bin/check_wwwdata /usr/bin/check_folder

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["php-fpm7", "-g", "/var/run/php-fpm.pid"]
