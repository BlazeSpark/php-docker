# Source: https://github.com/dotnet/dotnet-docker
FROM mcr.microsoft.com/dotnet/runtime-deps:6.0-jammy as build

ARG RUNNER_ARCH="x64"
# Replace value with the latest runner release version
# source: https://github.com/actions/runner/releases
# ex: 2.303.0
ARG RUNNER_VERSION="2.311.0"
# Replace value with the latest runner-container-hooks release version
# source: https://github.com/actions/runner-container-hooks/releases
# ex: 0.3.1
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.5.0
ARG DOCKER_VERSION=24.0.6
ARG BUILDX_VERSION=0.11.2

# Install necessary tools
RUN apt update -y && apt install curl unzip lsb-release gpg -y

WORKDIR /actions-runner
RUN curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

RUN curl -fLo docker.tgz https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz \
    && tar zxvf docker.tgz \
    && rm -rf docker.tgz \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fLo /usr/local/lib/docker/cli-plugins/docker-buildx \
        "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64" \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

FROM mcr.microsoft.com/dotnet/runtime-deps:6.0-jammy

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ENV ImageOS=ubuntu22
ENV ACCEPT_EULA=Y
ENV MYSQL_ROOT_PASSWORD=root

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    sudo \
    lsb-release \
    git \
    curl \
    unzip \
    gpg \
    && rm -rf /var/lib/apt/lists/*
    
ARG MARIADB_VERSION=1:11.4.0+maria~ubu2204
ENV MARIADB_VERSION $MARIADB_VERSION

# Mysql setting up root password
RUN set -ex; \
	{ \
		echo "mariadb-server" mysql-server/root_password password 'unused'; \
		echo "mariadb-server" mysql-server/root_password_again password 'unused'; \
	} | debconf-set-selections; \
	apt-get update; \
# postinst script creates a datadir, so avoid creating it by faking its existance.
	mkdir -p /var/lib/mysql/mysql ; touch /var/lib/mysql/mysql/user.frm ; \
# mariadb-backup is installed at the same time so that `mysql-common` is only installed once from just mariadb repos
	apt-get install -y --no-install-recommends mariadb-server="$MARIADB_VERSION" mariadb-backup socat \
	; \
	rm -rf /var/lib/apt/lists/*; \
# purge and re-create /var/lib/mysql with appropriate ownership
	rm -rf /var/lib/mysql /etc/mysql/mariadb.conf.d/50-mysqld_safe.cnf; \
	mkdir -p /var/lib/mysql /run/mysqld; \
	chown -R mysql:mysql /var/lib/mysql /run/mysqld; \
# ensure that /run/mysqld (used for socket and lock files) is writable regardless of the UID our mysqld instance ends up having at runtime
	chmod 1777 /run/mysqld; \
# comment out a few problematic configuration values
	find /etc/mysql/ -name '*.cnf' -print0 \
		| xargs -0 grep -lZE '^(bind-address|log|user\s)' \
		| xargs -rt -0 sed -Ei 's/^(bind-address|log|user\s)/#&/'; \
# don't reverse lookup hostnames, they are usually another container
	printf "[mariadb]\nhost-cache-size=0\nskip-name-resolve\n" > /etc/mysql/mariadb.conf.d/05-skipcache.cnf; \
# Issue #327 Correct order of reading directories /etc/mysql/mariadb.conf.d before /etc/mysql/conf.d (mount-point per documentation)
	if [ -L /etc/mysql/my.cnf ]; then \
# 10.5+
		sed -i -e '/includedir/ {N;s/\(.*\)\n\(.*\)/\n\2\n\1/}' /etc/mysql/mariadb.cnf; \
	fi

# Configure MariaDB
RUN echo 'sort_buffer_size = 256000000' >> /etc/mysql/mariadb.conf.d/50-server.cnf

# Install Redis
RUN curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list \
    && apt-get update -y \
    && apt-get install -y --no-install-recommends \
    redis \
    && rm -rf /var/lib/apt/lists/*

RUN adduser --disabled-password --gecos "" --uid 1001 runner \
    && groupadd docker --gid 123 \
    && usermod -aG sudo runner \
    && usermod -aG docker runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
    && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers

WORKDIR /home/runner

COPY --chown=runner:docker --from=build /actions-runner .
COPY --from=build /usr/local/lib/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx

RUN install -o root -g root -m 755 docker/* /usr/bin/ && rm -rf docker

USER runner
