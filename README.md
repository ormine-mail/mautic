# Custom Mautic Docker Image

A customized Docker image for Mautic with improved database connectivity and configuration options.

## Author and Maintainer

- Jan Kozak <galvani78@gmail.com>

## Features

- Multiple container roles (web, worker, cron)
- Detailed logging and feedback

## Usage

### Basic Usage

```bash
docker run -e DB_HOST=your-db-host \
  -e DB_PORT=3306 \
  -e DB_USER=your-username \
  -e DB_PASS=your-password \
  -e DB_NAME=your-db-name \
  -e CONTAINER_ROLE=web \
  -p 8080:80 \
  yourusername/mautic:latest
```

### Local Database Connection

For connecting to a database on your host machine:

```bash
docker run --network="host" \
  -e DB_HOST=127.0.0.1 \
  -e DB_PORT=3306 \
  -e DB_USER=your-username \
  -e DB_PASS=your-password \
  -e DB_NAME=your-db-name \
  -e CONTAINER_ROLE=web \
  yourusername/mautic:latest
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| DB_HOST | mysql | Database host |
| DB_PORT | 3306 | Database port |
| DB_USER | root | Database username |
| DB_PASS | password | Database password |
| DB_NAME | mautic | Database name |
| CONTAINER_ROLE | web | Container role (web, worker, cron) |
| PHP_FPM_MAX_CHILDREN | 5 | PHP-FPM max children |
| MAUTIC_ADMIN_USERNAME | admin | Admin username for first-time setup |
| MAUTIC_ADMIN_PASSWORD | | Admin password for first-time setup |

## License

© 2024 Jan Kozak. All rights reserved.

This is a proprietary software distribution based on Shoplio with custom modifications and improvements. Unauthorized reproduction, distribution, or use is strictly prohibited.
