#!/bin/bash
source .env

# echo $KEYSTORE_PASSWORD
# Chemins vers les fichiers nécessaires
CONTRACT_PATH="./target/dev/carbon_v3_USDCarb.contract_class.json"


# Demande du mot de passe du keystore
echo -n "Enter keystore password: "
read -s KEYSTORE_PASSWORD
echo

# Déclaration du contrat
echo "Declaring the contract..."
DECLARE_OUTPUT=$(starkli declare "$CONTRACT_PATH" --account "$STARKNET_ACCOUNT" --rpc "$STARKNET_RPC" --keystore "$STARKNET_KEYSTORE"  2>&1)
echo "\n\nDECLARE_OUTPUT: $DECLARE_OUTPUT\n\n"
CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -o 'Class hash declared: 0x[0-9a-fA-F]\+' | awk '{print $NF}')
echo "Class hash declared: $CLASS_HASH"

# Adresses pour le déploiement (ici deux fois la même pour cet exemple)
RECIPIENT_ADDRESS="0x0614d7b81d06b81363ec009e16861561b702ba9fdc335ff1a18d2169029fbfc8"
OWNER_ADDRESS="0x0614d7b81d06b81363ec009e16861561b702ba9fdc335ff1a18d2169029fbfc8"

# Déploiement du contrat
echo "Deploying the contract..."
DEPLOY_OUTPUT=$(starkli deploy "$CLASS_HASH" "$RECIPIENT_ADDRESS" "$OWNER_ADDRESS" --account "$STARKNET_ACCOUNT" --rpc "$STARKNET_RPC" --keystore "$STARKNET_KEYSTORE" 2>&1)

CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -o 'Contract deployed: 0x[0-9a-fA-F]\+' | awk '{print $NF}')
echo "Contract deployed at address: $CONTRACT_ADDRESS"

# Affichage des transactions
echo "Contract declaration transaction:"
echo "$DECLARE_OUTPUT" | grep -o 'Contract declaration transaction: 0x[0-9a-fA-F]\+' | awk '{print $NF}'
echo "Contract deployment transaction:"
echo "$DEPLOY_OUTPUT" | grep -o 'Contract deployment transaction: 0x[0-9a-fA-F]\+' | awk '{print $NF}'