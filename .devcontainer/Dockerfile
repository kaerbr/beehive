FROM alpine:3.23

ARG TALOS_VERSION=v1.12.4
ARG FLUX_VERSION=v2.7.5

# Install packages and download tools with checksum verification
RUN apk add --no-cache bash grep yq-go nano git age sops kustomize kubectl k9s helm \
    # talosctl with checksum
    && wget -q "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/sha256sum.txt" -O /tmp/talos-checksums.txt \
    && wget -q "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-amd64" -O /tmp/talosctl-linux-amd64 \
    && grep "talosctl-linux-amd64$" /tmp/talos-checksums.txt | (cd /tmp && sha256sum -c -) \
    && mv /tmp/talosctl-linux-amd64 /usr/local/bin/talosctl \
    && chmod +x /usr/local/bin/talosctl \
    && rm /tmp/talos-checksums.txt \
    # flux with checksum
    && FLUX_VERSION_NOV=${FLUX_VERSION#v} \
    && wget -q "https://github.com/fluxcd/flux2/releases/download/${FLUX_VERSION}/flux_${FLUX_VERSION_NOV}_checksums.txt" -O /tmp/flux-checksums.txt \
    && wget -q "https://github.com/fluxcd/flux2/releases/download/${FLUX_VERSION}/flux_${FLUX_VERSION_NOV}_linux_amd64.tar.gz" -O /tmp/flux_${FLUX_VERSION_NOV}_linux_amd64.tar.gz \
    && grep "flux_${FLUX_VERSION_NOV}_linux_amd64.tar.gz" /tmp/flux-checksums.txt | (cd /tmp && sha256sum -c -) \
    && tar -C /tmp -xzf /tmp/flux_${FLUX_VERSION_NOV}_linux_amd64.tar.gz \
    && mv /tmp/flux /usr/local/bin/flux \
    && chmod +x /usr/local/bin/flux \
    && rm /tmp/flux-checksums.txt /tmp/flux_${FLUX_VERSION_NOV}_linux_amd64.tar.gz

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN addgroup -g ${USER_GID} ${USERNAME} && adduser -u ${USER_UID} -G ${USERNAME} -s /bin/bash -D ${USERNAME}

USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV EDITOR="code --wait"
