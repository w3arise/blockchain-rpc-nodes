#!/usr/bin/env bash
#
# Metis publishes AWS EBS volume snapshots (not HTTP tarballs). This script
# prints the official IDs and skips import when datadirs already exist.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

DTL_DIR="${HOST_DTL_DATADIR:-$HOME/metis-l1dtl-data}"
L2_DIR="${HOST_L2GETH_DATADIR:-$HOME/metis-l2geth-data}"

dtl_init=false
l2_init=false
[[ -d "${DTL_DIR}/db" ]] && dtl_init=true
[[ -d "${L2_DIR}/geth/chaindata" ]] && l2_init=true

if [[ "${dtl_init}" == true && "${l2_init}" == true ]]; then
  echo "Datadirs already initialized — skip snapshot restore."
  echo "  l1dtl: ${DTL_DIR}"
  echo "  l2geth: ${L2_DIR}"
  exit 0
fi

cat <<'EOF'
Metis Andromeda recovery uses public AWS EBS snapshots (region us-east-2):

  l2geth: snap-0cbbd19f98af482be
  l1dtl:  snap-05bdfadeaf8ba2b82

Official steps: https://github.com/MetisProtocol/metis-ansible#snapshots

Create volumes from those snapshots, attach to a host, and copy or mount:

  l1dtl data -> HOST_DTL_DATADIR (container /data, DTL DB under db/)
  l2geth data -> HOST_L2GETH_DATADIR (container /root/.ethereum)

Recommended disk: ~750 GB gp3 for mainnet RPC.

Without snapshots, l2geth bootstraps from ROLLUP_STATE_DUMP_PATH (~82 KB genesis
dump) and syncs from L1 via DTL — slow and may hit "Refund counter below zero";
Metis FAQ suggests --cache.noprefetch=true on l2geth in that case.

Sepolia snapshots (us-east-1): l2geth snap-02a868bbfbafbc292, l1dtl snap-04b7bb8cbcd706cf9
EOF

echo ""
echo "Expected host paths from .env:"
echo "  HOST_DTL_DATADIR=${DTL_DIR}"
echo "  HOST_L2GETH_DATADIR=${L2_DIR}"
