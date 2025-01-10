

<img src="images/php.png" alt="PHP" width="300">

# PHP-FPM Tubocharged
Not your average PHP-FPM service—this is a highly optimized, lightning-fast ⚡ PHP processing engine designed to supercharge your PHP applications like Wordpress. This PHP-FPM service takes the standard implementation and **amps it up** to deliver unparalleled performance.

## Fuels The Wordpress Accelerated Stack 🌐⚡🚦🌀

- 🔥 **Blazing Speed**: Optimized for ultra-fast execution of PHP scripts.
- 🛠️ **Advanced Configuration**: Tuned for modern, high-traffic workloads.
- 📦 **Docker-Ready**: Fully containerized for quick and easy deployment.
- 📈 **Performance Monitoring**: Built-in metrics for real-time insights.
- ⚙️ **Customizability**: Easily tweak configurations to fit your specific needs.
- 🧩 **Compatible**: Works seamlessly with existing PHP applications.

## Features 💡

1. **Enhanced Process Management** 🧑‍💻  
      - Dynamically adjusts PHP resources based on your host for maximum efficiency.

2. **Optimized Docker Setup** 🐳  
      - Custom-built Docker image with a minimal footprint for reduced overhead.

3. **High Concurrency** 🕒  
      - Supports numerous simultaneous connections with minimal latency.

4. **Comprehensive Tuning** 🎯  
      - Fine-tuned configurations to handle anything from small sites to enterprise-scale applications.

5. **Opcache Optimization** 🏗️ 
      - Preloads frequently used scripts into memory for instant execution.
      - Automatically adjusts Opcache memory consumption based on the available RAM in the container.
      - Prevents downtime by keeping compiled scripts in memory between requests.

6. **Redis Integration** 🔴 
      - Simplifies session storage by offloading it to Redis.
      - Enables persistent object caching for high-speed data retrieval.
      - Fully customizable through environment variables to connect to external or local Redis servers.

7. **Nginx Integration** 🌐
      - Nginx as a reverse proxy to PHP-FPM, handling SSL termination, caching, and static file delivery.
      - Configured to work with Brotli and Gzip compression for smaller page sizes and faster load times.
      - Supports dynamic FastCGI caching to offload repeated requests.

8. **Wordpress CLI** 🎯  
      - Wordpress CLI is pre-installed ready to automate configuration and operations.

## Getting Started 🚀

### Prerequisites 📋

- Docker installed on your machine 🐳
- Basic knowledge of PHP and containerized applications

## Build
```
docker build -t openbridge/php-fpm .
```

Or pull it:
```
docker pull openbridge/php-fpm
```

## Setting Your `APP_DOCROOT`

The default root app directory is `/usr/share/nginx/html`. If you want to change this default you need to see `APP_DOCROOT` via ENV variable. For example, if you want to use `/html` as your root you would set `APP_DOCROOT=/html`

IMPORTANT: The `APP_DOCROOT` should be the same directory that you use within NGINX for the `NGINX_DOCROOT` which is `/usr/share/nginx/html`. Incorrectly setting the root for your web and applciation files is usually is the basis for most config errors, especially using applications like Wordpress.

## Dynamic Resource Allocation
The PHP and cache settings are a function of the available system resources. This allocation factors in available memory and CPU which is assigned proportionately. The proportion of resources was defined according to researched best practices and reading PHP docs.

## Permissions
We have standardized on the user, group and UID/GID to work seamlessly with NGINX

```docker
&& addgroup -g 82 -S www-data \
&& adduser -u 82 -D -S -h /var/cache/php-fpm -s /sbin/nologin -G www-data www-data \
```
We are also make sure all the underlying permissions and owners are set correctly based on the doc root like `/usr/share/nginx/html`:

## Logging
Logs are sent to stdout and stderr PHP-FPM.
You will likely want to dispatch these logs to a service like Amazon Cloudwatch. This will allow you to setup alerts and triggers to perform tasks based on container activity.

## Issues

If you have any problems with or questions about this image, please contact us through a GitHub issue.

## Contributing

You are invited to contribute new features, fixes, or updates, large or small; we are always thrilled to receive pull requests, and do our best to process them as fast as we can.

Before you start to code, we recommend discussing your plans through a GitHub issue, especially for more ambitious contributions. This gives other contributors a chance to point you in the right direction, give you feedback on your design, and help you find out if someone else is working on the same thing.

## References

PHP

* https://www.kinamo.be/en/support/faq/determining-the-correct-number-of-child-processes-for-php-fpm-on-nginx
* https://www.if-not-true-then-false.com/2011/nginx-and-php-fpm-configuration-and-optimizing-tips-and-tricks/
* https://www.tecklyfe.com/adjusting-child-processes-php-fpm-nginx-fix-server-reached-pm-max_children-setting/
* https://serversforhackers.com/video/php-fpm-process-management
* https://devcenter.heroku.com/articles/php-concurrency

The image is based on the official PHP docker image:
* https://github.com/docker-library/php

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
