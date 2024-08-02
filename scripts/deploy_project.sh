#!/bin/bash
source ../.env 
source .env 

OWNER=$DEPLOYER_ADDRESS

USAGE="Usage: ./deploy_project.sh <CLASS_HASH>"

if [ -z "$1" ]; then
    echo "Error: No CLASS_HASH provided.$USAGE"
    exit 1
fi
deploy() {
    class_hash=$1
    output=$(starkli deploy $class_hash "$OWNER" "$OWNER"  --account "$STARKNET_ACCOUNT" --rpc "$STARKNET_RPC" --keystore "$STARKNET_KEYSTORE" --keystore-password "$KEYSTORE_PASSWORD" 2>&1)
    if [[ $output == *"Error"* ]]; then
        echo "Error at deployment: $output"
        exit 1
    fi
    echo "$output"
}

deploy $1