FROM php:8.1-fpm-bullseye
MAINTAINER ThePhamDinh [thepd@smartosc.com]

ARG APP_ID=1000

RUN groupadd -g "$APP_ID" app \
  && useradd -g "$APP_ID" -u "$APP_ID" -d /var/www -s /bin/bash app

RUN mkdir -p /etc/nginx/html /var/www/html \
  && chown -R app:app /etc/nginx /var/www /usr/local/etc/php/conf.d

# RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash -

RUN apt-get update && apt-get install -y \
    cron \
    default-mysql-client \
    git \
    gnupg \
    gzip \
    libbz2-dev \
    libfreetype6-dev \
    libicu-dev \
    libjpeg62-turbo-dev \
    libmagickwand-dev \
    libmcrypt-dev \
    libonig-dev \
    libpng-dev \
    libsodium-dev \
    libssh2-1-dev \
    libwebp-dev \
    libxslt1-dev \
    libzip-dev \
    lsof \
    mailutils \
    msmtp \
    nodejs \
    procps \
    vim \
    zip \
  && rm -rf /var/lib/apt/lists/*

RUN pecl channel-update pecl.php.net && pecl install \
    imagick \
    redis \
    ssh2-1.3.1 \
    xdebug \
  && pecl clear-cache \
  && rm -rf /tmp/pear

RUN docker-php-ext-configure \
    gd --with-freetype --with-jpeg --with-webp \
  && docker-php-ext-install \
    bcmath \
    bz2 \
    calendar \
    exif \
    gd \
    gettext \
    intl \
    mbstring \
    mysqli \
    opcache \
    pcntl \
    pdo_mysql \
    soap \
    sockets \
    sodium \
    sysvmsg \
    sysvsem \
    sysvshm \
    xsl \
    zip \
  && docker-php-ext-enable \
    imagick \
    redis \
    ssh2 \
    xdebug

RUN version=$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;") \
    && architecture=$(uname -m) \
    && curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s https://blackfire.io/api/v1/releases/probe/php/linux/$architecture/$version \
    && mkdir -p /tmp/blackfire \
    && tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
    && mv /tmp/blackfire/blackfire-*.so $(php -r "echo ini_get ('extension_dir');")/blackfire.so \
    && rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz

RUN curl -sS https://getcomposer.org/installer | \
  php -- --install-dir=/usr/local/bin --filename=composer

COPY conf/blackfire.ini $PHP_INI_DIR/conf.d/blackfire.ini
COPY conf/msmtprc /etc/msmtprc
COPY conf/php.ini $PHP_INI_DIR
COPY conf/php-fpm.conf /usr/local/etc/
COPY conf/www.conf /usr/local/etc/php-fpm.d/

# Magento build
RUN composer config --global http-basic.repo.magento.com 9a88e8f9040ba41a8516077e2bbad8e0 9fe89f9ee74c4bf55d6a2da335837b4a && \
    composer create-project --repository=https://repo.magento.com/ magento/project-community-edition=2.4.4 . && \
    composer config --no-plugins allow-plugins.magento/magento-composer-installer true && \
    composer config --no-plugins allow-plugins.magento/inventory-composer-installer true && \
    composer config --no-plugins allow-plugins.laminas/laminas-dependency-plugin true && \
    bin/magento setup:install \
        --db-host="magento-mariadb" \
        --db-name="magento" \
        --db-user="magento" \
        --db-password="magento" \
        --base-url=https://magento.dev/ \
        --base-url-secure=https://magento.dev/ \
        --backend-frontname=admin \
        --admin-firstname=admin \
        --admin-lastname=admin \
        --admin-email=admin@gmail.com \
        --admin-user=admin \
        --admin-password=admin123 \
        --language=en_US \
        --currency=USD \
        --timezone=America/New_York \
        --cache-backend=redis \
        --cache-backend-redis-server=magento-redis \
        --cache-backend-redis-db=0 \
        --page-cache=redis \
        --page-cache-redis-server=magento-redis \
        --page-cache-redis-db=1 \
        --session-save=redis \
        --session-save-redis-host=magento-redis \
        --session-save-redis-log-level=4 \
        --session-save-redis-db=2 \
        --search-engine=elasticsearch7 \
        --elasticsearch-host=magento-elasticsearch \
        --elasticsearch-port=9200 \
        --use-rewrites=1 \
        --no-interaction && \
    bin/magento setup:static-content:deploy -f && \
    bin/magento indexer:reindex && \
    bin/magento config:set web/secure/base_url https://magento.dev/ && \
    bin/magento config:set web/unsecure/base_url https://magento.dev/ && \
    chown -R app:app /var/www/html/ && \
    bin/magento cache:flush && \
    bin/magento cache:flush && \
    bin/magento cron:install && \
    bin/magento cron:install

USER app:app
WORKDIR /var/www/html
EXPOSE 9000
