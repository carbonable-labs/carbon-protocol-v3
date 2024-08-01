#!/bin/bash
source .env

# Chemin vers le fichier de contrat
CONTRACT_PATH="./target/dev/carbon_v3_USDCarb.contract_class.json"



# Déclaration du contrat
echo "Declaring the contract..."
DECLARE_OUTPUT=$(starkli declare "$CONTRACT_PATH" --account "$STARKNET_ACCOUNT" --rpc "$STARKNET_RPC" --keystore "$STARKNET_KEYSTORE" --keystore-password "$KEYSTORE_PASSWORD" 2>&1)
echo -e "\n\nDECLARE_OUTPUT: $DECLARE_OUTPUT\n\n"
