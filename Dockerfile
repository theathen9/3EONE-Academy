# =========================================================
# 1. Node / Vite build
# =========================================================

FROM node:24.16.0-alpine AS frontend

WORKDIR /app

COPY package*.json ./

RUN npm ci

COPY . .

RUN npm run build


# =========================================================
# 2. Composer dependencies
# =========================================================

FROM composer:2 AS vendor

WORKDIR /app

COPY composer.json composer.lock ./

RUN composer install \
    --no-dev \
    --prefer-dist \
    --optimize-autoloader \
    --no-interaction \
    --no-progress \
    --no-scripts

COPY . .

RUN composer dump-autoload --optimize


# =========================================================
# 3. Application
# =========================================================

FROM php:8.4-fpm

RUN apt-get update && apt-get install -y \
    nginx \
    git \
    curl \
    unzip \
    zip \
    libpq-dev \
    libzip-dev \
    libicu-dev \
    libonig-dev \
    libxml2-dev \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libwebp-dev \
    && rm -rf /var/lib/apt/lists/*


# =========================================================
# PHP extensions
# =========================================================

RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp

RUN docker-php-ext-install -j"$(nproc)" \
    bcmath \
    exif \
    gd \
    intl \
    opcache \
    pdo_pgsql \
    pgsql \
    zip


# =========================================================
# PHP configuration
# =========================================================

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

RUN sed -i 's|^listen = .*|listen = 127.0.0.1:9000|' \
    /usr/local/etc/php-fpm.d/www.conf


# =========================================================
# Laravel
# =========================================================

WORKDIR /var/www/html

COPY . .

COPY --from=vendor /app/vendor ./vendor

COPY --from=frontend /app/public/build ./public/build


# =========================================================
# Laravel permissions
# =========================================================

RUN mkdir -p \
    storage/framework/cache \
    storage/framework/sessions \
    storage/framework/views \
    bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache


# =========================================================
# Laravel package discovery
# =========================================================

RUN php artisan package:discover --ansi


# =========================================================
# Nginx
# =========================================================

COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf


# =========================================================
# Startup
# =========================================================

COPY docker/nginx/start.sh /usr/local/bin/start.sh

RUN chmod +x /usr/local/bin/start.sh

EXPOSE 80

CMD ["/usr/local/bin/start.sh"]
