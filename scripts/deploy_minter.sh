#!/bin/bash

source ../.env 
source .env 


USAGE="Usage: ./deploy_minter.sh <CLASS_HASH> <StableCoin> <Project>"
# Vérification de l'argument CLASS_HASH
if [ -z "$1" ]; then
    echo "Error: No CLASS_HASH provided.$USAGE"
    exit 1
fi

# Vérification de l'argument CLASS_HASH
if [ -z "$2" ]; then
    echo "Error: No stablecoin stable provided.$USAGE"
    exit 1
fi

# Vérification de l'argument CLASS_HASH
if [ -z "$2" ]; then
    echo "Error: No project address provided.$USAGE"
    exit 1
fi

class_hash=$1
ERC20=$2
PROJECT=$3

# You can change this variables
OWNER=$DEPLOYER_ADDRESS
PUBLIC_SALE_OPEN=1
MAX_VALUE=20000000000
UNIT_PRICE=11

output=$(starkli deploy $class_hash "$PROJECT" "$ERC20" "$PUBLIC_SALE_OPEN" u256:"$MAX_VALUE" u256:"$UNIT_PRICE" "$OWNER"  --account "$STARKNET_ACCOUNT" --rpc "$STARKNET_RPC" --keystore "$STARKNET_KEYSTORE" --keystore-password "$KEYSTORE_PASSWORD" 2>&1)

if [[ $output == *"Error"* ]]; then
    echo "Error: $output"
    exit 1
fi
echo "$output"
