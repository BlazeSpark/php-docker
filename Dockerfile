# Source: https://github.com/dotnet/dotnet-docker
FROM mcr.microsoft.com/dotnet/runtime-deps:6.0-jammy AS build

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
ARG MYSQL_ROOT_PASSWORD=root
ARG CHROME_VERSION="130.0.6723.69"

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1 \
    CHROME_BIN="/usr/bin/google-chrome"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update -qq && \
    apt-get upgrade -qq -y && \
    apt-get install -q -y --no-install-recommends \
    curl wget unzip sudo jq gnupg git gpg openssl gpg-agent software-properties-common \
    && curl -sL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-add-repository ppa:ondrej/php -y && \
    apt-get update -qq && \
    apt-get install -q -y --no-install-recommends \
    nodejs php8.3 php8.3-{ctype,curl,fileinfo,fpm,iconv,mbstring,phar,simplexml,xml,xmlwriter,zip,gd,intl,tokenizer,xmlreader,posix,redis,mysql,pcov} \
    && apt-get install -q -y mariadb-server redis-server \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

RUN adduser --disabled-password --gecos "" --uid 1001 runner \
    && groupadd docker --gid 123 \
    && usermod -aG sudo,docker runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
    && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers

# Configure MariaDB
RUN echo "mariadb-server mariadb-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections && \
    echo "mariadb-server mariadb-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections && \
    service mariadb start && \
    mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;" && \
    echo 'sort_buffer_size = 256000000' >> /etc/mysql/mariadb.conf.d/50-server.cnf

# Configure Redis to listen on all interfaces
RUN sed -i 's/^# bind 127.0.0.1 ::1/bind 0.0.0.0/' /etc/redis/redis.conf

# Install Chrome
RUN apt-get update -qq && \
    apt-get install -y fonts-liberation libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 \
                       libcairo2 libcups2 libdrm2 libgbm1 libgtk-3-0 libnspr4 libnss3 \
                       libpango-1.0-0 libvulkan1 libxcomposite1 libxdamage1 libxext6 \
                       libxfixes3 libxkbcommon0 libxrandr2 xdg-utils && \
    wget --no-verbose -O /tmp/chrome.deb https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${CHROME_VERSION}-1_amd64.deb && \
    apt install -y /tmp/chrome.deb && rm /tmp/chrome.deb

# Installazione di MinIO
RUN wget https://dl.min.io/server/minio/release/linux-amd64/archive/minio_20241013133411.0.0_amd64.deb -O minio.deb && \
    dpkg -i minio.deb

# Installazione di MinIO Client
RUN wget  https://dl.min.io/client/mc/release/linux-amd64/mc -O mc && \
    chmod +x mc && mv mc /usr/local/bin/mc

COPY /etc /etc

RUN chmod +x /etc/init.d/minio && \
    update-rc.d minio defaults

WORKDIR /home/runner

RUN curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz && \
    tar xzf ./runner.tar.gz && rm runner.tar.gz && \
    curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip && \
    unzip ./runner-container-hooks.zip -d ./k8s && rm runner-container-hooks.zip

USER runner
