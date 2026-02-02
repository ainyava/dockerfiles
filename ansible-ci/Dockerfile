FROM python:3.13

RUN apt-get update \
    && apt-get install -y curl openssh-client apt-transport-https dnsutils neovim skopeo netcat-openbsd rsync git \
    && python3 -m pip install ansible
