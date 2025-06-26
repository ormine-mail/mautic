FROM php:8.3-fpm AS base

LABEL author="Jan Kozak <galvani78@gmail.com>"

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

# Now copy the application code
COPY --chown=www-data:www-data . /app
RUN chmod +x /usr/local/bin/docker-entrypoint

RUN cd /app && composer install --no-dev --optimize-autoloader --no-scripts
RUN cd /app && composer require \
    datto/json-rpc-http:^1.0 \
    minwork/array:^1.0 \
    sentry/sentry:^3.0 \
    sentry/sentry-symfony:^4.0 \
    --no-scripts --no-interaction


ENV MAX_REQUESTS=1000
ENTRYPOINT ["docker-entrypoint"]

WORKDIR /app

FROM base AS web

RUN cd /app && npm ci --prefer-offline --no-audit && \
    npx patch-package && \
    bin/console mautic:assets:generate

RUN apt-get update && apt-get install -y nginx
RUN rm -f /etc/nginx/sites-enabled/default
COPY ./docker/nginx/nginx.conf /etc/nginx/sites-enabled/default

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s CMD curl -f http://localhost/ || exit 1
EXPOSE 80

FROM base AS worker

COPY ./docker/crontab /etc/cron.d/mautic-cron
RUN chmod 0644 /etc/cron.d/mautic-cron
RUN crontab /etc/cron.d/mautic-cron

# Install supervisor
RUN apt-get update && apt-get install -y supervisor
RUN mkdir -p /var/log/supervisor
COPY --link ./docker/supervisord.conf /etc/supervisor/conf.d/messenger-worker.conf

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s CMD SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1