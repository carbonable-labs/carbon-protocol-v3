#!/bin/bash
source .env

# Vérification de l'argument CLASS_HASH
if [ -z "$1" ]; then
    echo "Error: No CLASS_HASH provided. Usage: ./deploy_contract.sh <CLASS_HASH>"
    exit 1
fi

CLASS_HASH=$1
# Adresses pour le déploiement

OWNER_ADDRESS=$DEPLOYER_ADDRESS
echo "Owner : $OWNER_ADDRESS"


# Déploiement du contrat
echo "Deploying the contract..."
DEPLOY_OUTPUT=$(starkli deploy "$CLASS_HASH" "$DEPLOYER_ADDRESS" "$OWNER_ADDRESS" --account "$STARKNET_ACCOUNT" --rpc "$STARKNET_RPC" --keystore "$STARKNET_KEYSTORE" --keystore-password "$KEYSTORE_PASSWORD" 2>&1)
echo -e "\n\nDEPLOY_OUTPUT: $DEPLOY_OUTPUT\n\n"

# Affichage des transactions
echo "Contract deployment transaction:"
echo "$DEPLOY_OUTPUT" | grep -o 'Contract deployment transaction: 0x[0-9a-fA-F]\+' | awk '{print $NF}'