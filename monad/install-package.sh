#!/usr/bin/env bash
#
# Install the official Monad APT package and pin the version from .env.
#
# Usage (as root): ./install-package.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
load_env "${SCRIPT_DIR}"
env_require MONAD_VERSION

mkdir -p /etc/apt/keyrings

if [[ ! -f /etc/apt/sources.list.d/category-labs.sources ]]; then
  cat <<'EOF' > /etc/apt/sources.list.d/category-labs.sources
Types: deb
URIs: https://pkg.category.xyz/
Suites: noble
Components: main
Signed-By: /etc/apt/keyrings/category-labs.gpg
EOF
fi

# refreshed on every run — upstream rotates the signing key
curl -fsSL https://pkg.category.xyz/keys/public-key.asc \
  | gpg --dearmor --yes -o /etc/apt/keyrings/category-labs.gpg

apt update
apt install -y curl nvme-cli aria2 jq

DEBIAN_FRONTEND=noninteractive apt install -y --reinstall \
  "monad=${MONAD_VERSION}" \
  --allow-downgrades --allow-change-held-packages

apt-mark hold monad

echo "installed monad=${MONAD_VERSION}"
monad-rpc -V
