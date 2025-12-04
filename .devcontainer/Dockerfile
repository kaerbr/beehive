FROM alpine:3.23

RUN apk add --no-cache git kustomize age sops bash grep nano
# RUN export PS1="\[\033[1;36m\]\u\[\033[0;34m\]@\[\033[1;34m\]\h\[\033[0m\]:\[\033[1;36m\]\W\[\033[0m\]\$ "

# RUN useradd -ms /bin/bash newuser

# Create a non-root user 'vscode'
# We align the UID/GID with 1000 to match the default Linux/WSL user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN addgroup -g ${USER_GID} ${USERNAME} && adduser -u ${USER_UID} -G ${USERNAME} -s /bin/bash -D ${USERNAME}

# Standard-User setzen
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# RUN groupadd --gid $USER_GID $USERNAME && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME

# USER $USERNAME
# WORKDIR /home/$USERNAME

# CMD [ "bash" ]
