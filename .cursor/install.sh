#!/usr/bin/env bash
#
# Cloud Agent install: prepare the tooling this repo's development flow needs.
#
# This repository is a collection of Dockerized blockchain node deployments
# (docker-compose per chain) plus bash/Python maintenance tooling. The core
# dev experience is:
#   - docker + docker compose  (validate/run chain configs)
#   - bash / python3 / jq      (configure.sh, init scripts, audit tooling)
#   - scripts/check-auto-upgrades.sh (the CI check; queries upstream registries)
#
# Idempotent: safe to run repeatedly. Installs Docker Engine + Compose plugin
# and supporting CLI tools (shellcheck, aria2, yamllint). The Docker daemon is
# started per-boot by .cursor/start.sh, not here.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "==> install.sh: preparing blockchain-rpc-nodes tooling"

# --- Docker apt repository (idempotent) ---
if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker Engine + Compose plugin"
  sudo install -m 0755 -d /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  # shellcheck source=/dev/null
  . /etc/os-release
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -qq
  # --force-confold: keep default /etc/fuse.conf non-interactively (fuse3 dep).
  sudo apt-get install -y -qq \
    -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin \
    fuse-overlayfs
else
  echo "==> Docker already installed: $(docker --version)"
fi

# --- Supporting CLI tools ---
missing=()
command -v shellcheck >/dev/null 2>&1 || missing+=(shellcheck)
command -v aria2c     >/dev/null 2>&1 || missing+=(aria2)
if [ "${#missing[@]}" -gt 0 ]; then
  echo "==> Installing: ${missing[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y -qq "${missing[@]}"
fi

# yamllint via pip (not packaged consistently); user-local, on PATH via start.sh
if ! command -v yamllint >/dev/null 2>&1 && ! [ -x "$HOME/.local/bin/yamllint" ]; then
  echo "==> Installing yamllint (pip --user)"
  pip3 install --quiet --user --break-system-packages yamllint
fi

# --- Let the agent user talk to the Docker socket without sudo ---
sudo groupadd -f docker
sudo usermod -aG docker "$(id -un)" || true

echo "==> install.sh complete"
docker --version
docker compose version
