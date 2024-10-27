# Source: https://github.com/dotnet/dotnet-docker
FROM --platform=linux/amd64 mcr.microsoft.com/dotnet/runtime-deps:6.0-jammy AS build

# Replace value with the latest runner release version
# source: https://github.com/actions/runner/releases
# ex: 2.303.0
ARG RUNNER_VERSION="2.320.0"
ARG RUNNER_ARCH="x64"
# Replace value with the latest runner-container-hooks release version
# source: https://github.com/actions/runner-container-hooks/releases
# ex: 0.3.1
ARG RUNNER_CONTAINER_HOOKS_VERSION="0.6.1"

ARG NODE_VERSION=20

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update -qq \
  && apt-get upgrade -qq -y \
  && apt-get install -q -y --no-install-recommends \
    curl \
    wget \
    unzip \
    sudo\
    jq \
    gnupg \
    git \
    gpg \
    openssl \
    gpg-agent \
    software-properties-common \
  && curl -sL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -q -y \
    nodejs \
    && apt-get update -qq \
    && apt-add-repository ppa:ondrej/php -y \
    && apt-get update -qq \
    && apt-get install -q -y --no-install-recommends \
    php8.3 \
    php8.3-ctype \
    php8.3-curl \
    php8.3-fileinfo \
    php8.3-fpm \
    php8.3-iconv \
    php8.3-mbstring \
    php8.3-phar \
    php8.3-simplexml \
    php8.3-xml \
    php8.3-xmlwriter \
    php8.3-zip \
    php8.3-gd \
    php8.3-intl  \
    php8.3-tokenizer  \
    php8.3-xmlreader  \
    php8.3-posix \
    php8.3-redis \
    php8.3-mysql \
    php8.3-pcov

COPY  --from=composer:latest /usr/bin/composer /usr/local/bin/composer

RUN adduser --disabled-password --gecos "" --uid 1001 runner \
    && groupadd docker --gid 123 \
    && usermod -aG sudo runner \
    && usermod -aG docker runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
    && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers

# Imposta la password di root per MariaDB
ARG MYSQL_ROOT_PASSWORD=root

# Installazione di MariaDB con configurazione della password
RUN apt-get update -qq && \
    echo "mariadb-server mariadb-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections && \
    echo "mariadb-server mariadb-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections && \
    apt-get install -y mariadb-server && \
    service mariadb start && \
    # Disabilita l'uso di unix_socket per l'utente root e abilita l'autenticazione con password
    mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;"

# Configure MariaDB
RUN echo 'sort_buffer_size = 256000000' >> /etc/mysql/mariadb.conf.d/50-server.cnf

# Installa Redis
RUN apt-get update -qq && \
    apt-get install -y redis-server && \
    # Configura Redis per eseguire tutte le interfacce di rete (opzionale, solo per test)
    sed -i 's/^# bind 127.0.0.1 ::1/bind 0.0.0.0/' /etc/redis/redis.conf && \
    # Imposta Redis in modalità background
    echo "daemonize yes" >> /etc/redis/redis.conf

# Check available versions here: https://www.ubuntuupdates.org/package/google_chrome/stable/main/base/google-chrome-stable
ARG CHROME_VERSION="130.0.6723.69"
RUN wget --no-verbose -O /tmp/chrome.deb https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${CHROME_VERSION}-1_amd64.deb \
  && apt install -y /tmp/chrome.deb \
  && rm /tmp/chrome.deb \
  rm -f /etc/cron.daily/google-chrome /etc/apt/sources.list.d/google-chrome.list /etc/apt/sources.list.d/google-chrome.list.save && \
  echo "CHROME_BIN=/usr/bin/google-chrome" >> /etc/environment

ENV CHROMEDRIVER_DIR="/usr/local/share/chromedriver-linux64"

RUN  mkdir -p $CHROMEDRIVER_DIR && \
    curl -L -o /tmp/chromedriver.zip "https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chromedriver-linux64.zip" && \
    unzip -qq /tmp/chromedriver.zip -d "$CHROMEDRIVER_DIR" && \
    chmod +x "$CHROMEDRIVER_DIR/chromedriver" && \
    ln -s "$CHROMEDRIVER_DIR/chromedriver" /usr/bin/ && \
    echo "CHROMEWEBDRIVER=$CHROMEDRIVER_DIR" >> /etc/environment && \
    rm -f /tmp/chromedriver.zip

WORKDIR /home/runner

RUN curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

USER runner
