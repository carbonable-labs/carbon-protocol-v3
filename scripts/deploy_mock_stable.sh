#!/bin/bash
source ../.env 
source .env 
# Vérification de l'argument CLASS_HASH
if [ -z "$1" ]; then
    echo "Error: No CLASS_HASH provided. Usage: ./deploy_stable.sh <CLASS_HASH>"
    exit 1
fi

CLASS_HASH=$1

# You can change the owner
OWNER_ADDRESS=$DEPLOYER_ADDRESS
echo "Owner : $OWNER_ADDRESS"


# Déploiement du contrat
echo "Deploying the contract..."
output=$(starkli deploy "$CLASS_HASH" "$DEPLOYER_ADDRESS" "$OWNER_ADDRESS" --account "$STARKNET_ACCOUNT" --rpc "$STARKNET_RPC" --keystore "$STARKNET_KEYSTORE" --keystore-password "$KEYSTORE_PASSWORD" 2>&1)
echo -e "Output: $output"
