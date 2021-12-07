FROM shivammathur/node:latest
# shivammathur/node docker images are optimized for setup-php
# These base images will also work - ubuntu:focal, ubuntu:bionic, debian:bullseye, debian:buster, debian:stretch

ARG RUNNER_VERSION=ver
ARG RUNNER_URL=https://github.com/foo/bar
ARG RUNNER_TOKEN=tkn

RUN set -ex && apt-get update && apt-get install -y ca-certificates curl gnupg iputils-ping libicu-dev sudo --no-install-recommends

RUN adduser --disabled-password --gecos '' runner \
  && usermod -aG sudo runner \
  && mkdir -m 777 -p /home/runner \
  && sed -i 's/%sudo\s.*/%sudo ALL=(ALL:ALL) NOPASSWD : ALL/g' /etc/sudoers

USER runner
WORKDIR /home/runner

RUN sudo mkdir -p /opt/hostedtoolcache \
  && sudo chmod -R 777 /opt/hostedtoolcache

RUN sudo curl -o runner.tar.gz -sSL https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
  && sudo tar xf runner.tar.gz \
  && sudo bash ./bin/installdependencies.sh || true

CMD [ "bash", "-c", "./config.sh --url ${RUNNER_URL} --token ${RUNNER_TOKEN}; ./run.sh; sleep infinity"]
