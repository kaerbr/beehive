FROM alpine:3.23

RUN apk add --no-cache git kustomize age sops bash grep nano curl openssl findutils
RUN curl -sL https://talos.dev/install | sh

# Create a non-root user 'vscode'
# We align the UID/GID with 1000 to match the default Linux/WSL user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN addgroup -g ${USER_GID} ${USERNAME} && adduser -u ${USER_UID} -G ${USERNAME} -s /bin/bash -D ${USERNAME}

# Standard-User setzen
USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV EDITOR="code --wait"
