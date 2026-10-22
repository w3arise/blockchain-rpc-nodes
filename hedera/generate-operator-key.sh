#!/usr/bin/env bash
#
# Generate a Hedera ECDSA operator key inside a throwaway Node container.
# Prints the DER private key on the terminal. Does not write .env and does
# not create or fund an account.

set -euo pipefail

NODE_IMAGE="${NODE_IMAGE:-node:22-bookworm}"

echo "Image: ${NODE_IMAGE}"
echo "Starting a one-shot container. It is removed when this script exits."
echo "npm output and the key are printed below. Nothing is written to .env."
echo

docker run --rm -i "${NODE_IMAGE}" bash -s <<'EOF'
set -euo pipefail

echo "Working directory: /tmp (container filesystem, discarded on exit)"
cd /tmp

echo
echo "----- npm init -----"
npm init -y

echo
echo "----- npm install @hashgraph/sdk -----"
npm install @hashgraph/sdk

echo
echo "----- operator key -----"
node --input-type=module <<'JS'
import { PrivateKey } from "@hashgraph/sdk";

const privateKey = PrivateKey.generateECDSA();
const publicKey = privateKey.publicKey;

console.log("key type = ECDSA secp256k1");
console.log("OPERATOR_KEY_FORMAT=DER");
console.log("OPERATOR_KEY_MAIN=" + privateKey.toStringDer());
console.log("public key = " + publicKey.toStringDer());
console.log("evm address = 0x" + publicKey.toEvmAddress());
JS
EOF

echo
echo "Copy OPERATOR_KEY_MAIN into hedera/.env. This value is a private key."
echo "OPERATOR_ID_MAIN does not exist until this public key is registered on Hedera mainnet and the account holds HBAR."
