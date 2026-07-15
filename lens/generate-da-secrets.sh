#!/usr/bin/env bash
# Print a fresh BIP39 12-word seed phrase for EN_DA_SECRETS_SEED_PHRASE.
# Used only to initialize Avail blob verification; no funds or on-chain identity.

set -euo pipefail

python3 <<'PY'
import hashlib
import secrets
import urllib.request

WORDLIST_URL = (
    "https://raw.githubusercontent.com/bitcoin/bips/master/bip-0039/english.txt"
)


def load_wordlist() -> list[str]:
    with urllib.request.urlopen(WORDLIST_URL, timeout=30) as response:
        words = response.read().decode().split()
    if len(words) != 2048:
        raise SystemExit(f"unexpected BIP39 wordlist size: {len(words)}")
    return words


def generate_mnemonic(strength: int = 128) -> str:
    if strength not in (128, 160, 192, 224, 256):
        raise ValueError("unsupported BIP39 strength")

    words = load_wordlist()
    entropy = secrets.token_bytes(strength // 8)
    checksum_len = strength // 32
    entropy_bits = f"{int.from_bytes(entropy, 'big'):0{strength}b}"
    checksum_bits = f"{hashlib.sha256(entropy).digest()[0]:08b}"[:checksum_len]
    bits = entropy_bits + checksum_bits
    indices = [int(bits[i : i + 11], 2) for i in range(0, len(bits), 11)]
    return " ".join(words[index] for index in indices)


print(generate_mnemonic())
PY
