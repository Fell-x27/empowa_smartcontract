#!/bin/bash

#run as ". SCRIPT"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"

export ARTIFACTS_PATH="$(dirname "$SCRIPT_DIR")/artifacts"
export TX_FILES="$SCRIPT_DIR"

export CONTRACT_REF_UTXO="0ff92ccb584d044acd163cb7199a487703c38c5d7a55ff964f46f68d38430736#0"

export TREASURY_ASSET_NAME=$(echo -n "TRS" | xxd -ps | tr -d '\n')

export EXCH_TIME=85003316
export RECALL_TIME=85003616

export NFT_VKEY="$TX_FILES/keys/nft_policy.vkey"
export NFT_SKEY="$TX_FILES/keys/nft_policy.skey"
export NFT_SCRIPT="$TX_FILES/keys/nft_policy.script"
export NFT_PID=$(cat "$TX_FILES/keys/nft_policy.id")
export NFT_CORRECT_NAME=$(echo -n "Empowa Collateral v1.2 - test" | xxd -ps | tr -d '\n')
export NFT_INCORRECT_NAME=$(echo -n "Empowa Collateral v1.1 - test" | xxd -ps | tr -d '\n')

export POA_VKEY="$TX_FILES/keys/poa_policy.vkey"
export POA_SKEY="$TX_FILES/keys/poa_policy.skey"
export POA_SCRIPT="$TX_FILES/keys/poa_policy.script"
export POA_PID="$(cat "$TX_FILES/keys/poa_policy.id")"
export POA_ASSET_NAME=$(echo -n "EMP" | xxd -ps | tr -d '\n')

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

export CONTRACT_SCRIPT="$ARTIFACTS_PATH/testnet/contract.script"
export CONTRACT_ADDR=$(cat "$ARTIFACTS_PATH/testnet/contract.addr")
export CONTRACT_PID=$(cat "$ARTIFACTS_PATH/testnet/contract.pid")

