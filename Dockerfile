
###################
# OPERATING SYTSEM
###################

# The container uses CentOS 7.x
FROM centos:latest
MAINTAINER Thomas Spicer (thomas@openbridge.com)

###################
# STORAGE
###################

# Set the volume to to store activity
# /ebs is a standard mount point from the host
VOLUME ["/ebs"]

###################
# YUM PACKAGES
###################

# Add the latests EPEL 7 Repo
RUN yum install epel-release -y ;\
    rpm -Uvh http://rpms.famillecollet.com/enterprise/remi-release-7.rpm

# Run the update with the EPEL 7 Repo
RUN yum update -y

RUN yum --enablerepo=remi,remi-php70 install -y \
    initscripts \
    curl \
    cronie \
    pwgen \
    gcc-c++ \
    mysql \
    mysql-devel \
    pcre-devel \
    zlib-devel \
    openssl \
    openssl-devel \
    wget \
    make \
    unzip \
    php-fpm \
    php-cli \
    php-common \
    php-mysql \
    php-pear \
    php-bcmat \
    php-pdo \
    php-mysqlnd \
    php-gd \
    php-mbstring \
    php-soap \
    php-apc \
    php-tidy \
    php-mcrypt \
    php-xml \
    php-redis \
    php-dom \
    php-devel

###################
# PHP-FPM
###################

# Tweak php-fpm config
RUN sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php.ini ;\
    sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php.ini ;\
    sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php.ini ;\
    sed -i -e "s/zlib.output_compression\s*=\s*Off/zlib.output_compression = On/g" /etc/php.ini ;\
   #sed -i -e "s/cgi.fix_pathinfo=0/cgi.fix_pathinfo=1/g" /etc/php.ini ;\
    sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php-fpm.d/www.conf ;\
    sed -i -e "s/pm.max_children = 5/pm.max_children = 9/g" /etc/php-fpm.d/www.conf ;\
    sed -i -e "s/pm.start_servers = 2/pm.start_servers = 3/g" /etc/php-fpm.d/www.conf ;\
    sed -i -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" /etc/php-fpm.d/www.conf ;\
    sed -i -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" /etc/php-fpm.d/www.conf ;\
    sed -i -e "s/pm.max_requests = 500/pm.max_requests = 200/g" /etc/php-fpm.d/www.conf

# Fix ownership for php-fpm
RUN sed -i -e "s/;listen.mode = 0660/listen.mode = 0750/g" /etc/php-fpm.d/www.conf ;\
    sed -i -e "s/;listen.owner = nobody/listen.owner = nobody/g" /etc/php-fpm.d/www.conf ;\
    sed -i -e "s/;listen.group = nobody/listen.group = nobody/g" /etc/php-fpm.d/www.conf ;\
    sed -i -e "s/listen = 127.0.0.1:9000/listen = 9000/g" /etc/php-fpm.d/www.conf ;\
    sed -i -e "s/listen.allowed_clients = 127.0.0.1/;listen.allowed_clients = 172.17.0.1/g" /etc/php-fpm.d/www.conf ;\

    sed -i -e "s/user = apache/user = nginx/g" /etc/php-fpm.d/www.conf ;\
    sed -i -e "s/group = apache/group = nginx/g" /etc/php-fpm.d/www.conf ;\
    find /etc/php.d/ -name "*.ini" -exec sed -i -re 's/^(\s*)#(.*)/\1;\2/g' {} \;

# Add users for programs that need them
RUN groupadd nginx ;\
    groupmod -g 2011 nginx ;\
    useradd -u 2011 -s /bin/false -d /bin/null -c "nginx user" -g nginx nginx

###################
# NETWORK
###################

EXPOSE 9000

###################
# MONIT
###################

ENV MONIT_VERSION 5.19.0

# Add Monit binary
RUN mkdir -p /tmp/monit ;\
    cd /tmp/monit ;\
    wget https://bitbucket.org/tildeslash/monit/downloads/monit-${MONIT_VERSION}-linux-x64.tar.gz ;\
    tar -xf monit* && cd monit* ;\
    rm -Rf /usr/local/bin/mont ;\
    mv bin/monit /usr/local/bin ;\
    chmod u+x /usr/local/bin/monit ;\
    ln /usr/local/bin/monit /usr/bin/monit

EXPOSE 2888

ADD etc/monitrc /etc/monitrc
COPY etc/monit.d/* /etc/monit.d/

###################
# STARTUP
###################

# When this is present it prevents crond from running
RUN sed -i '/session    required   pam_loginuid.so/d' /etc/pam.d/crond

# Setup the Init services
COPY etc/init.d/* /etc/init.d/

# Auto start services
RUN chmod +x /etc/init.d/crond ;\
    chkconfig crond --add ;\
    chkconfig crond on

RUN chmod +x /etc/init.d/php-fpm ;\
    chkconfig php-fpm --add ;\
    chkconfig php-fpm on

ADD usr/local/bin/startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

CMD ["/usr/local/bin/startup.sh"]
