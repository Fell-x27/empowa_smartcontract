#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"

export TX_FILES="$SCRIPT_DIR"
export NFT_CORRECT_NAME="Empowa Collateral v1.2 - test"
export NFT_INCORRECT_NAME="Empowa Collateral v1.1 - test"
export PO_ASSET_NAME="EMP"
export EXCH_TIME=0
export RECALL_TIME=0

export NFT_VKEY="$TX_FILES/keys/nft_policy.vkey"
export NFT_SKEY="$TX_FILES/keys/nft_policy.skey"
export NFT_SCRIPT="$TX_FILES/keys/nft_policy.script"
export NFT_PID=$(cat "$TX_FILES/keys/nft_policy.id")

export POA_VKEY="$TX_FILES/keys/poa_policy.vkey"
export POA_SKEY="$TX_FILES/keys/poa_policy.skey"
export POA_SCRIPT="$TX_FILES/keys/poa_policy.script"
export POA_PID="$(cat "$TX_FILES/keys/poa_policy.id")"

export USER_VKEY="$TX_FILES/keys/user.vkey"
export USER_SKEY="$TX_FILES/keys/user.skey"
export USER_ADDR=$(cat "$TX_FILES/keys/user.addr")

export OWNER_VKEY="$TX_FILES/keys/owner.vkey"
export OWNER_SKEY="$TX_FILES/keys/owner.skey"
export OWNER_ADDR=$(cat "$TX_FILES/keys/owner.addr")
export OWNER_KEYHASH=$(cat "$TX_FILES/keys/owner.vkh")

export BOOTSTRAP_RDM="$TX_FILES/redeemers/bootstrap.json"
export EXCHANGE_RDM="$TX_FILES/redeemers/exchange.json"
export RECALL_RDM="$TX_FILES/redeemers/recall.json"