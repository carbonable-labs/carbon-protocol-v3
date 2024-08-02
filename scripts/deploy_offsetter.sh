#!/bin/bash

source ../.env 
source .env 


USAGE="Usage: ./deploy_offsetter.sh <CLASS_HASH> <PROJECT>"

#  CLASS_HASH var verification
if [ -z "$1" ]; then
    echo "Error: No CLASS_HASH provided.$USAGE"
    exit 1
fi

#  PROJECT var verification
if [ -z "$2" ]; then
    echo "Error: No project address provided.$USAGE"
    exit 1
fi

class_hash=$1
PROJECT=$2

# You can change this variables
OWNER=$DEPLOYER_ADDRESS


output=$(starkli deploy $class_hash "$PROJECT"  "$OWNER"  --account "$STARKNET_ACCOUNT" --rpc "$STARKNET_RPC" --keystore "$STARKNET_KEYSTORE" --keystore-password "$KEYSTORE_PASSWORD" 2>&1)
if [[ $output == *"Error"* ]]; then
    echo "Error: $output"
    exit 1
fi

echo "$output"
