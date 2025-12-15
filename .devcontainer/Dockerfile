FROM alpine:3.23

# Install packages and download tools with checksum verification
RUN apk add --no-cache bash grep yq-go nano git age sops kustomize flux kubectl k9s \
    # talosctl with checksum
    && wget -q "https://github.com/siderolabs/talos/releases/latest/download/sha256sum.txt" -O /tmp/checksums.txt \
    && wget -q "https://github.com/siderolabs/talos/releases/latest/download/talosctl-linux-amd64" -O /tmp/talosctl-linux-amd64 \
    && grep "talosctl-linux-amd64$" /tmp/checksums.txt | (cd /tmp && sha256sum -c -) \
    && mv /tmp/talosctl-linux-amd64 /usr/local/bin/talosctl \
    && chmod +x /usr/local/bin/talosctl \
    && rm /tmp/checksums.txt

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN addgroup -g ${USER_GID} ${USERNAME} && adduser -u ${USER_UID} -G ${USERNAME} -s /bin/bash -D ${USERNAME}

USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV EDITOR="code --wait"
