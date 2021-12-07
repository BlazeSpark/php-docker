FROM shivammathur/node:latest
# shivammathur/node docker images are optimized for setup-php
# These base images will also work - ubuntu:focal, ubuntu:bionic, debian:bullseye, debian:buster, debian:stretch

ARG RUNNER_VERSION=ver
ARG RUNNER_URL=https://github.com/foo/bar
ARG RUNNER_TOKEN=tkn

RUN set -ex && apt-get update \ 
  && apt-get install -y ca-certificates curl gnupg iputils-ping libicu-dev sudo \ 
  dos2unix gcc git git-lfs libmcrypt4 libpcre3-dev libpng-dev chrony unzip make pv \
  --no-install-recommends

# install python
RUN apt-get install -y python3-pip build-essential libssl-dev libffi-dev python3-dev python3-venv
# install mysql
RUN echo "mysql-server mysql-server/root_password password root" | debconf-set-selections
RUN echo "mysql-server mysql-server/root_password_again password root" | debconf-set-selections
RUN apt-get install -y mysql-server

# install docker
RUN apt-get update
RUN apt-get -y install apt-transport-https software-properties-common
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"

RUN apt-get update
RUN apt-get -y install docker-ce

# install chrome driver
RUN curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -
RUN echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' | tee -a /etc/apt/sources.list.d/google-chrome.list

RUN apt-get update

RUN apt-get -y install libxpm4 libxrender1 libgtk2.0-0 libnss3 libgconf-2-4 chromium-browser xvfb gtk2-engines-pixbuf \
  xfonts-cyrillic xfonts-100dpi xfonts-75dpi xfonts-base xfonts-scalable imagemagick x11-apps google-chrome-stable

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
