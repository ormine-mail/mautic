#!/bin/sh
set -e

DB_HOST=${MAUTIC_DB_HOST}
DB_PORT=${MAUTIC_DB_PORT}
DB_USER=${MAUTIC_DB_USER}
DB_PASS=${MAUTIC_DB_PASSWORD}
DB_NAME=${MAUTIC_DB_NAME}
DB_PREFIX="${MAUTIC_DB_PREFIX:-}"
DB_DRIVER="${MAUTIC_DB_DRIVER:-pdo_mysql}"

if [ -z "${MAUTIC_SITE_URL}" ]; then
  echo "ERROR: MAUTIC_SITE_URL environment variable is not set!"
  echo "Please set MAUTIC_SITE_URL to your site's URL (e.g., https://mautic.example.com)"
  exit 1
fi

SITE_URL=${MAUTIC_SITE_URL}

# Check if Mautic is installed
is_mautic_installed() {
  MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" -e "SHOW TABLES LIKE 'users';" 2>/dev/null | grep -q 'users'
  return $?
}

# Check whether local.php is present, if not and mautic database is populated we need to create /app/config/local.php
create_local_config() {
  if [ ! -f /app/config/local.php ] && is_mautic_installed; then
    echo "Database exists but local.php is missing. Creating config file..."

    # Generate a random secret key if not provided
    if [ -z "${MAUTIC_SECRET_KEY}" ]; then
      SECRET_KEY=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1)
    else
      SECRET_KEY="${MAUTIC_SECRET_KEY}"
    fi

    # Create the local.php file
    cat > /app/config/local.php << EOF
<?php
\$parameters = array(
	'db_driver' => '${DB_DRIVER}',
	'db_host' => '${DB_HOST}',
	'db_host_ro' => null,
	'db_table_prefix' => '${DB_PREFIX:+\'$DB_PREFIX\'}',
	'db_port' => '${DB_PORT}',
	'db_name' => '${DB_NAME}',
	'db_user' => '${DB_USER}',
	'db_password' => '${DB_PASS}',
	'db_backup_tables' => false,
	'db_backup_prefix' => 'bak_',
	'secret_key' => '${SECRET_KEY}',
	'site_url' => '${SITE_URL}',
	'mailer_dsn' => '${MAILER_DSN}'
);
EOF

    echo "Successfully created /app/config/local.php"
    echo "Secret: ${SECRET_KEY}"

    # Ensure proper permissions for the config file
    chown www-data:www-data /app/config/local.php
    chmod 660 /app/config/local.php
  fi
}


# Count tables in database directly with MySQL
count_tables() {
  MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | wc -l
}

# Wait for database to be ready
wait_for_database() {
  echo "Waiting for database to be ready..."

  # Maximum number of attempts
  max_attempts=30
  attempt=0

  # Try to connect to the database
  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt+1))
    echo "Attempt $attempt of $max_attempts..."

    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1" "$DB_NAME" >/dev/null; then
      echo "Database connection successful!"
      return 0
    fi

    echo "Database not ready yet. Waiting 5 seconds..."
    sleep 5
  done

  echo "Could not connect to database after $max_attempts attempts!"
  return 1
}


# ------------------------------
# Mautic Installation Functions
# ------------------------------

# Install Mautic safely
install_mautic() {
  echo "Running Mautic installation..."

  # Try to create a lock file for installation
  if mkdir -p /app/var/cache && touch /app/var/cache/.installing_mautic.$$ && mv /app/var/cache/.installing_mautic.$$ /app/var/cache/.installing_mautic 2>/dev/null; then
    echo "Installing Mautic..."

    # Check if database appears to be empty or nearly empty
    table_count=$(count_tables)
    echo "Found $table_count tables in database."

    # If database has fewer than 5 tables, assume it's a fresh install
    if [ "$table_count" -lt 5 ]; then
      echo "Database appears to be fresh (fewer than 5 tables). Proceeding with installation."

      # Clear the cache first to ensure clean state
      php bin/console cache:clear --no-warmup

      if [ -z "${MAUTIC_ADMIN_EMAIL}" ]; then
        echo "ERROR: MAUTIC_ADMIN_EMAIL environment variable is not set!"
        echo "Please set MAUTIC_ADMIN_EMAIL to your admin email address"
        exit 1
      fi

      if [ -z "${MAUTIC_ADMIN_PASSWORD}" ]; then
        echo "ERROR: MAUTIC_ADMIN_PASSWORD environment variable is not set!"
        echo "Please set MAUTIC_ADMIN_PASSWORD to a secure password"
        exit 1
      fi

      # Use Mautic's installer with all required database parameters
      echo "Installing Mautic database and default data, site url: $SITE_URL"
      php bin/console mautic:install "$SITE_URL" --force \
        --db_driver="$DB_DRIVER" \
        --db_host="$DB_HOST" \
        --db_port="$DB_PORT" \
        --db_name="$DB_NAME" \
        --db_user="$DB_USER" \
        --db_password="$DB_PASS" \
        --db_table_prefix="$DB_PREFIX" \
        --admin_firstname="Mautic" \
        --admin_lastname="Administrator" \
        --admin_username="admin" \
        --admin_email="${MAUTIC_ADMIN_EMAIL}" \
        --admin_password="${MAUTIC_ADMIN_PASSWORD}"

      echo "Installing Mautic plugins..."
      php bin/console mautic:plugins:install

      # Install assets
      echo "Generating assets..."
      php bin/console mautic:assets:generate --no-interaction
    else
      echo "Database contains $table_count tables. Refusing automatic installation to prevent data loss."
      echo "Manual intervention required. Please either:"
      echo "1. Empty the database manually and restart the container"
      echo "2. Complete the installation manually using the web interface"
      exit 1
    fi

    # Mark as installed
    touch /app/var/cache/.mautic_installed
    echo "$(date): Mautic was installed by $(hostname)" > /app/var/cache/.mautic_installed
    rm -f /app/var/cache/.installing_mautic
    echo "Mautic installation completed."
  else
    echo "Another instance is handling Mautic installation, waiting..."
    # Wait for installation to complete
    for i in $(seq 1 60); do
      if [ ! -f /app/var/cache/.installing_mautic ]; then
        echo "Mautic installation completed by another container."
        break
      fi
      sleep 2
      if [ $i -eq 60 ]; then
        echo "Warning: Installation timeout after waiting 2 minutes. Continuing anyway..."
      fi
    done
  fi
}

# Run database migrations (only if already installed)
run_migrations() {
  echo "Running database migrations..."
  php bin/console doctrine:migrations:migrate --no-interaction
  echo "Database migrations completed."
}

# Ensure correct file permissions
fix_permissions() {
  echo "Fixing permissions..."

  # Create directories if they don't exist
  mkdir -p /app/var/cache /app/var/logs /app/var/tmp /app/var/spool /app/media/files /app/media/images

  chgrp -R www-data /app/config
  chmod -R 775 /app/config
  echo "Setting correct ownership for mounted volumes..."

  # Ensure proper permissions
  chmod 775 /app
  chmod 775 /app/var
  chmod 775 /app/var/cache
  chmod 775 /app/var/logs
  chmod 775 /app/var/tmp
  chmod 775 /app/var/spool
  chmod 775 /app/media
  chmod 775 /app/media/files
  chmod 775 /app/media/images

  # Change ownership selectively
  chown -v www-data:www-data /app/var
  chown -v www-data:www-data /app/var/cache
  chown -v www-data:www-data /app/var/logs
  chown -v www-data:www-data /app/var/tmp
  chown -v www-data:www-data /app/var/spool
  chown -v www-data:www-data /app/media
}

# Warm up cache
warm_cache() {
  echo "Warming up cache..."
  php bin/console cache:clear
  echo "Cache warmup completed."
}

configure_php() {
  # Apply FPM configuration based on environment variables if this is a web container
  if [ "$CONTAINER_ROLE" = "web" ]; then
      # Configure PHP-FPM based on environment variables
      if [ -n "$PHP_FPM_PM" ]; then
          sed -i "s/pm = .*/pm = $PHP_FPM_PM/" /usr/local/etc/php-fpm.d/www.conf
      fi

      if [ -n "$PHP_FPM_MAX_CHILDREN" ]; then
          sed -i "s/pm.max_children = .*/pm.max_children = $PHP_FPM_MAX_CHILDREN/" /usr/local/etc/php-fpm.d/www.conf
      fi

      if [ -n "$PHP_FPM_START_SERVERS" ]; then
          sed -i "s/pm.start_servers = .*/pm.start_servers = $PHP_FPM_START_SERVERS/" /usr/local/etc/php-fpm.d/www.conf
      fi

      if [ -n "$PHP_FPM_MIN_SPARE_SERVERS" ]; then
          sed -i "s/pm.min_spare_servers = .*/pm.min_spare_servers = $PHP_FPM_MIN_SPARE_SERVERS/" /usr/local/etc/php-fpm.d/www.conf
      fi

      if [ -n "$PHP_FPM_MAX_SPARE_SERVERS" ]; then
          sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = $PHP_FPM_MAX_SPARE_SERVERS/" /usr/local/etc/php-fpm.d/www.conf
      fi

      # Enable web configuration, disable CLI configuration
      if [ -f "/usr/local/etc/php/conf.d/95-mautic-cli.ini" ]; then
          mv "/usr/local/etc/php/conf.d/95-mautic-cli.ini" "/usr/local/etc/php/conf.d/95-mautic-cli.ini.disabled"
      fi

  elif [ "$CONTAINER_ROLE" = "worker" ] || [ "$CONTAINER_ROLE" = "cron" ]; then
      # Enable CLI configuration, disable web configuration
      if [ -f "/usr/local/etc/php/conf.d/95-mautic-web.ini" ]; then
          mv "/usr/local/etc/php/conf.d/95-mautic-web.ini" "/usr/local/etc/php/conf.d/95-mautic-web.ini.disabled"
      fi
  fi
}

# ------------------------------
# Main Script Logic
# ------------------------------

configure_php

cd /app

# Wait for database to be ready
if ! wait_for_database; then
  echo "Error: Database connection failed. Check your database settings."
  exit 1
fi

## First install Composer dependencies for connected plugins
echo "Installing Composer dependencies..."
composer install --no-dev --optimize-autoloader --no-scripts

# Check if Mautic is installed and create local.php if needed
if is_mautic_installed; then
  echo "Mautic is already installed, checking local.php file..."
  create_local_config
else
  echo "Mautic is not installed, running initial installation..."
  install_mautic
fi

if [ "$CONTAINER_ROLE" = "web" ]; then
  echo "Running migrations..."
  run_migrations
fi

warm_cache

echo "Installing Mautic plugins..."
php bin/console mautic:plugins:install

fix_permissions

echo "Container Role: $CONTAINER_ROLE"
echo "Current directory: $(pwd)"
echo "PHP Version: $(php -v | head -n 1)"

if [ -L /usr/local/etc/php/conf.d/99-mautic-role.ini ]; then
  rm -f /usr/local/etc/php/conf.d/99-mautic-role.ini
fi

# Set appropriate PHP config based on container role
if [ "$CONTAINER_ROLE" = "worker" ]; then
    echo "Starting Mautic worker with queue processing..."
    echo "Starting supervisor for worker role..."
    exec supervisord -n
elif [ "$CONTAINER_ROLE" = "web" ]; then
    echo "Starting web and FPM servers..."
    service nginx start
    # Start PHP-FPM in foreground
    exec php-fpm -F
elif [ "$CONTAINER_ROLE" = "cron" ]; then
    echo "Setting up cron environment..."
    env > /etc/environment

    crontab /etc/cron.d/mautic-cron

    echo "Installed crontab:"
    crontab -l

    echo "Starting cron instance in foreground..."
    exec cron -f -l 8
else
    echo "Unknown CONTAINER_ROLE: $CONTAINER_ROLE"
    echo "Expected values: web, worker, cron"
    exit 1
fi