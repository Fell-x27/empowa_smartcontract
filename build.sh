#!/bin/bash

# Build for testnet
TESTNET_PATH="./artifacts/testnet/"
echo "TESTNET BUILD [${TESTNET_PATH}]"
mkdir -p "$TESTNET_PATH"
aiken build -t verbose
aiken blueprint convert > "$TESTNET_PATH/contract.script"
aiken blueprint address > "$TESTNET_PATH/contract.addr"
aiken blueprint policy > "$TESTNET_PATH/contract.pid"
echo ""
# Build for mainnet
MAINNET_PATH="./artifacts/mainnet/"
echo "MAINNET BUILD [${MAINNET_PATH}]"
mkdir -p "$MAINNET_PATH"
aiken build -t silent
aiken blueprint convert > "$MAINNET_PATH/contract.script"
aiken blueprint address --mainnet > "$MAINNET_PATH/contract.addr"
aiken blueprint policy  > "$MAINNET_PATH/contract.pid"

echo "Done!"
