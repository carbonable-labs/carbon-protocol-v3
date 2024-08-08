#!/bin/bash
source ../.env 
source .env 

# Function to set the contract path based on the given parameter
set_contract_path() {
    case $1 in
        project)
            CONTRACT_PATH="./target/dev/carbon_v3_Project.contract_class.json"
            ;;
        offsetter)
            CONTRACT_PATH="./target/dev/carbon_v3_Offsetter.contract_class.json"
            ;;
        mock_stable)
            CONTRACT_PATH="./target/dev/carbon_v3_USDCarb.contract_class.json"
            ;;
        minter)
            CONTRACT_PATH="./target/dev/carbon_v3_Minter.contract_class.json"
            ;;
        *)
            echo "Invalid parameter. Please use one of the following: project, offsetter, mock_stable, minter."
            exit 1
            ;;
    esac
}

# Check if a parameter is passed
if [ -z "$1" ]; then
    echo "No parameter provided. Please specify a parameter: project, offsetter, mock_stable, minter."
    exit 1
fi

# Set the contract path based on the provided parameter
set_contract_path $1

# Declare the contract
echo "Declaring the contract with CONTRACT_PATH=$CONTRACT_PATH..."
output=$(starkli declare "$CONTRACT_PATH" --account "$STARKNET_ACCOUNT" --rpc "$STARKNET_RPC" --keystore "$STARKNET_KEYSTORE" --keystore-password "$KEYSTORE_PASSWORD" 2>&1)

if [[ $output == *"Error"* ]]; then
    echo "Error: $output"
    exit 1
fi

echo -e "Contract declare: $output"