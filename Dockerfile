FROM php:8.3-fpm AS builder

LABEL author="Jan Kozak <galvani78@gmail.com>"

WORKDIR /app

VOLUME /app/var/

# Build argument to determine the role of the container
ARG CONTAINER_ROLE=web
ENV CONTAINER_ROLE=${CONTAINER_ROLE}
ENV PHP_INI_DIR=/usr/local/etc/php

RUN apt-get update && apt-get install -y --no-install-recommends \
    acl \
    file \
    gettext \
    git \
    unzip \
    libicu-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libkrb5-dev \
    libxml2-dev \
    libzip-dev \
    libonig-dev \
    libxslt-dev \
    libmagickwand-dev \
    zlib1g-dev \
    libmemcached-dev \
    nodejs \
    npm \
    default-mysql-client \
    librabbitmq-dev \
    libssh-dev \
    cron \
    curl \
    libc-client-dev \
    libkrb5-dev \
    libnss3-tools \
    libfcgi0ldbl \
    # Additional dependencies for building extensions
    autoconf \
    g++ \
    make \
    && rm -rf /var/lib/apt/lists/*

# Install supervisor
RUN apt-get update && apt-get install -y supervisor
RUN mkdir -p /var/log/supervisor
COPY docker/supervisord.conf /etc/supervisor/conf.d/messenger-worker.conf

# Configure and install GD extension
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd

# Configure and install IMAP extension
RUN docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-install -j$(nproc) imap

# Install basic extensions
RUN docker-php-ext-install -j$(nproc) \
    bcmath \
    calendar \
    exif \
    intl \
    mbstring \
    mysqli \
    opcache \
    pdo_mysql \
    soap \
    sockets \
    xml \
    zip \
    xsl

# Install PECL extensions
RUN pecl install apcu && docker-php-ext-enable apcu \
    && pecl install redis && docker-php-ext-enable redis \
    && pecl install amqp && docker-php-ext-enable amqp \
    && pecl install memcached && docker-php-ext-enable memcached \
    && pecl install imagick && docker-php-ext-enable imagick

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Create a custom configuration directory
RUN mkdir -p $PHP_INI_DIR/app.conf.d
ENV PHP_INI_SCAN_DIR=":$PHP_INI_DIR/app.conf.d"

# Copy base configuration (applies to all roles)
COPY --link ./docker/conf.d/base.ini $PHP_INI_DIR/app.conf.d/90-mautic-base.ini

# Copy role-specific configurations
COPY --link ./docker/conf.d/web.ini $PHP_INI_DIR/app.conf.d/95-mautic-web.ini
COPY --link ./docker/conf.d/cli.ini $PHP_INI_DIR/app.conf.d/95-mautic-cli.ini

# Create PHP-FPM configuration
COPY --link ./docker/php-fpm.d/www.conf /usr/local/etc/php-fpm.d/www.conf

COPY ./docker/php-fpm.d/www.conf /usr/local/etc/php-fpm.d/www.conf

COPY ./docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
COPY ./docker/crontab /etc/crontabs/www-data
RUN chmod +x /usr/local/bin/docker-entrypoint

# Now copy the application code
COPY --chown=www-data:www-data . /app
RUN ls -asl /app

RUN cd /app && composer install --no-dev --optimize-autoloader

RUN npm ci --prefer-offline --no-audit && \
    npx patch-package && \
    bin/console mautic:assets:generate

ENV MAX_REQUESTS=1000
ENV MAUTIC_CUSTOM_DEV_HOSTS='["localhost","127.0.0.1","172.18.0.1","172.19.0.1"]'

EXPOSE 9000
ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s CMD SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1