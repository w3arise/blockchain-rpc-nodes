FROM ubuntu:24.04

ARG USERNAME=hluser
ARG USER_UID=10000
ARG USER_GID=$USER_UID

# Define URLs as environment variables
ARG PUB_KEY_URL
ARG HL_VISOR_URL
ARG HL_VISOR_ASC_URL

# Create user and install dependencies
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update -y && apt-get install -y curl gnupg tini \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /home/$USERNAME/hl/data && chown -R $USERNAME:$USERNAME /home/$USERNAME/hl

USER $USERNAME
WORKDIR /home/$USERNAME

# Configure chain to Mainnet
RUN echo '{"chain": "Mainnet"}' > /home/$USERNAME/visor.json
COPY override_gossip_config.json /home/$USERNAME/override_gossip_config.json
USER root
RUN chown $USERNAME:$USERNAME /home/$USERNAME/override_gossip_config.json
USER $USERNAME

# Import GPG public key
RUN curl -o /home/$USERNAME/pub_key.asc $PUB_KEY_URL \
    && gpg --import /home/$USERNAME/pub_key.asc

# Download and verify hl-visor binary
RUN curl -o /home/$USERNAME/hl-visor $HL_VISOR_URL \
    && curl -o /home/$USERNAME/hl-visor.asc $HL_VISOR_ASC_URL \
    && gpg --verify /home/$USERNAME/hl-visor.asc /home/$USERNAME/hl-visor \
    && chmod +x /home/$USERNAME/hl-visor

# Expose gossip ports
EXPOSE 4000-4010

# Run a non-validating node. hl-visor installs no SIGTERM/SIGINT handler, so as
# PID 1 it ignores docker stop and never reaps its children. tini is PID 1
# instead and -g forwards the stop signal to the process group (hl-visor + hl-node).
# hl-visor panics if another process cmdline contains "hl-visor", so tini starts
# a wrapper that execs it rather than naming the binary directly.
RUN printf '#!/bin/sh\nexec /home/%s/hl-visor run-non-validator --replica-cmds-style recent-actions "$@"\n' $USERNAME > /home/$USERNAME/start-node \
    && chmod +x /home/$USERNAME/start-node
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/home/hluser/start-node"]
