FROM php:7.3-apache

# persistent dependencies
RUN set -eux; \
apt-get update; \
apt-get install -y --no-install-recommends \
# Ghostscript is required for rendering PDF previews
ghostscript unzip \
; \
rm -rf /var/lib/apt/lists/*

# install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
RUN set -ex; \
\
savedAptMark="$(apt-mark showmanual)"; \
\
apt-get update; \
apt-get install -y --no-install-recommends \
libfreetype6-dev \
libjpeg-dev \
libmagickwand-dev \
libpng-dev \
libzip-dev \
; \
\
docker-php-ext-configure gd --with-freetype-dir=/usr --with-jpeg-dir=/usr --with-png-dir=/usr; \
docker-php-ext-install -j "$(nproc)" \
bcmath \
exif \
gd \
mysqli \
opcache \
zip \
; \
pecl install imagick-3.4.4; \
docker-php-ext-enable imagick; \
\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
apt-mark auto '.*' > /dev/null; \
apt-mark manual $savedAptMark; \
ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
| awk '/=>/ { print $3 }' \
| sort -u \
| xargs -r dpkg-query -S \
| cut -d: -f1 \
| sort -u \
| xargs -rt apt-mark manual; \
\
apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
echo 'opcache.memory_consumption=128'; \
echo 'opcache.interned_strings_buffer=8'; \
echo 'opcache.max_accelerated_files=4000'; \
echo 'opcache.revalidate_freq=2'; \
echo 'opcache.fast_shutdown=1'; \
} > /usr/local/etc/php/conf.d/opcache-recommended.ini


# set custom upload configurations for php
RUN { \
echo 'file_uploads = On'; \
echo 'memory_limit = 64M'; \
echo 'upload_max_filesize = 64M'; \
echo 'post_max_size = 64M'; \
echo 'max_execution_time = 600'; \
} > /usr/local/etc/php/conf.d/uploads.ini

# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
RUN { \
# https://www.php.net/manual/en/errorfunc.constants.php
# https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
echo 'display_errors = Off'; \
echo 'display_startup_errors = Off'; \
echo 'log_errors = On'; \
echo 'error_log = /dev/stderr'; \
echo 'log_errors_max_len = 1024'; \
echo 'ignore_repeated_errors = On'; \
echo 'ignore_repeated_source = Off'; \
echo 'html_errors = Off'; \
} > /usr/local/etc/php/conf.d/error-logging.ini

RUN set -eux; \
a2enmod rewrite expires; \
\
# https://httpd.apache.org/docs/2.4/mod/mod_remoteip.html
a2enmod remoteip; \
{ \
echo 'RemoteIPHeader X-Forwarded-For'; \
# these IP ranges are reserved for "private" use and should thus usually be safe inside Docker
echo 'RemoteIPTrustedProxy 10.0.0.0/8'; \
echo 'RemoteIPTrustedProxy 172.16.0.0/12'; \
echo 'RemoteIPTrustedProxy 192.168.0.0/16'; \
echo 'RemoteIPTrustedProxy 169.254.0.0/16'; \
echo 'RemoteIPTrustedProxy 127.0.0.0/8'; \
} > /etc/apache2/conf-available/remoteip.conf; \
a2enconf remoteip; \
# https://github.com/docker-library/wordpress/issues/383#issuecomment-507886512
# (replace all instances of "%h" with "%a" in LogFormat)
find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +

VOLUME /var/www/html


ENV WORDPRESS_VERSION 5.3.2
ENV WORDPRESS_SHA1 e7089e7163045e818634e3060f7e3c44dc2a7eaf


RUN set -ex; \
curl -o wordpress.zip -fSL "https://downloads.wordpress.org/release/wordpress-${WORDPRESS_VERSION}-no-content.zip"; \
echo "$WORDPRESS_SHA1 *wordpress.zip" | sha1sum -c -; \
# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
unzip wordpress.zip -d /usr/src/; \
rm wordpress.zip; \
chown -R www-data:www-data /usr/src/wordpress



COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
