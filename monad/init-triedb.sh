#!/usr/bin/env bash
#
# Initialize the dedicated TrieDB NVMe storage and publish it as /dev/triedb.
#
# Accepts either a whole device (partitioned here as a single triedb partition)
# or an existing partition on that device (used as-is).
#
# Usage (as root): ./init-triedb.sh [/dev/nvme1n1|/dev/nvme1n1p1]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
load_env "${SCRIPT_DIR}"

echo "Block devices on this host:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
echo ""

DEVICE="${1:-}"
if [[ -z "${DEVICE}" ]]; then
  DEFAULT_DEVICE="${TRIEDB_DRIVE:-}"
  [[ "${DEFAULT_DEVICE}" == *"<"* ]] && DEFAULT_DEVICE=""
  read -r -p "TrieDB device — whole disk or partition${DEFAULT_DEVICE:+ [${DEFAULT_DEVICE}]}: " DEVICE
  DEVICE="${DEVICE:-${DEFAULT_DEVICE}}"
fi

if [[ -z "${DEVICE}" ]]; then
  echo "ERROR: no device given" >&2
  exit 1
fi

if [[ ! -b "${DEVICE}" ]]; then
  echo "ERROR: ${DEVICE} is not a block device" >&2
  exit 1
fi

DEVICE_TYPE="$(lsblk -ndo TYPE "${DEVICE}")"
case "${DEVICE_TYPE}" in
  disk) PARENT_DEVICE="${DEVICE}" ;;
  part) PARENT_DEVICE="/dev/$(lsblk -ndo PKNAME "${DEVICE}")" ;;
  *)
    echo "ERROR: ${DEVICE} is a '${DEVICE_TYPE}' — pass a whole disk or a partition" >&2
    exit 1
    ;;
esac

MOUNTED="$(lsblk -nro MOUNTPOINT "${DEVICE}" | grep -v '^$' || true)"
if [[ -n "${MOUNTED}" ]]; then
  echo "ERROR: ${DEVICE} has mounted filesystems — unmount before continuing:" >&2
  echo "${MOUNTED}" >&2
  exit 1
fi

echo ""
echo "TrieDB target: ${DEVICE} (${DEVICE_TYPE} on ${PARENT_DEVICE})"
if [[ "${DEVICE_TYPE}" == "disk" ]]; then
  echo "The whole disk will be relabelled GPT with a single triedb partition."
else
  echo "Only this partition will be used; the rest of ${PARENT_DEVICE} is left alone."
fi
echo "Verify this is NOT your OS disk (check lsblk output above)."
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL "${PARENT_DEVICE}"

read -r -p "Erase ${DEVICE} and use it for TrieDB? Type YES to continue: " confirm
if [[ "${confirm}" != "YES" ]]; then
  echo "aborted"
  exit 1
fi

# TrieDB requires 512-byte logical blocks. Reformatting the NVMe namespace wipes
# every partition on it, so it is only safe when the whole disk was selected.
SECTOR_SIZE="$(blockdev --getss "${DEVICE}")"
if [[ "${SECTOR_SIZE}" != "512" ]]; then
  if [[ "${DEVICE_TYPE}" != "disk" ]]; then
    echo "ERROR: ${DEVICE} has ${SECTOR_SIZE}-byte logical blocks; TrieDB needs 512." >&2
    echo "       Reformat the namespace first (destroys all partitions on it):" >&2
    echo "       nvme format --lbaf=0 ${PARENT_DEVICE}" >&2
    exit 1
  fi
  echo "setting 512-byte LBA on ${DEVICE}"
  nvme format --lbaf=0 --force "${DEVICE}"
  udevadm settle
fi

if [[ "${DEVICE_TYPE}" == "disk" ]]; then
  wipefs -a "${DEVICE}"
  parted -s "${DEVICE}" mklabel gpt
  parted -s "${DEVICE}" mkpart triedb 0% 100%
  partprobe "${DEVICE}"
  udevadm settle

  PARTITION="$(lsblk -nro NAME,TYPE "${DEVICE}" | awk '$2 == "part" { print "/dev/" $1; exit }')"
  if [[ -z "${PARTITION}" || ! -b "${PARTITION}" ]]; then
    echo "ERROR: no partition created on ${DEVICE}" >&2
    exit 1
  fi
else
  PARTITION="${DEVICE}"
  wipefs -a "${PARTITION}"
fi

PARTUUID="$(blkid -s PARTUUID -o value "${PARTITION}")"
if [[ -z "${PARTUUID}" ]]; then
  echo "ERROR: ${PARTITION} has no PARTUUID — it must live in a GPT partition table" >&2
  exit 1
fi
echo "TrieDB partition: ${PARTITION} (PARTUUID ${PARTUUID})"

echo "ENV{ID_PART_ENTRY_UUID}==\"${PARTUUID}\", MODE=\"0666\", SYMLINK+=\"triedb\"" \
  > /etc/udev/rules.d/99-triedb.rules

udevadm control --reload
udevadm trigger
udevadm settle

if [[ ! -e /dev/triedb ]]; then
  echo "ERROR: /dev/triedb symlink not created" >&2
  exit 1
fi

if [[ "$(readlink -f /dev/triedb)" != "$(readlink -f "${PARTITION}")" ]]; then
  echo "ERROR: /dev/triedb points at $(readlink -f /dev/triedb), expected ${PARTITION}" >&2
  exit 1
fi

if [[ "${TRIEDB_DRIVE:-}" != "${DEVICE}" ]]; then
  sed_inplace "s|^TRIEDB_DRIVE=.*|TRIEDB_DRIVE=${DEVICE}|" "${ENV_FILE}"
  echo "set TRIEDB_DRIVE=${DEVICE} in .env"
fi

systemctl start monad-mpt
journalctl -u monad-mpt -n 20 -o cat

echo "TrieDB initialized at /dev/triedb -> ${PARTITION}"
