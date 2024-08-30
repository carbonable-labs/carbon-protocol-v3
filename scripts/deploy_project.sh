#!/bin/bash
source ../.env 
source .env 


USAGE="Usage: ./deploy_project.sh <CLASS_HASH>"

# You can change these variables
OWNER=$DEPLOYER_ADDRESS
FROM_TIMESTAMP=2024
DURATION_IN_YEARS=20

if [ -z "$1" ]; then
    echo "Error: No CLASS_HASH provided.$USAGE"
    exit 1
fi
deploy() {
    class_hash=$1
    output=$(starkli deploy $class_hash "$OWNER" $FROM_TIMESTAMP $DURATION_IN_YEARS --account "$STARKNET_ACCOUNT" --rpc "$STARKNET_RPC" --keystore "$STARKNET_KEYSTORE" --keystore-password "$KEYSTORE_PASSWORD" 2>&1)
    if [[ $output == *"Error"* ]]; then
        echo "Error at deployment: $output"
        exit 1
    fi
    echo "$output"
}

deploy $1