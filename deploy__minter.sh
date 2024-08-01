#!/bin/bash
source ./.env

# Check if --debug parameter is passed
debug="false"
for arg in "$@"
do
    if [ "$arg" == "--debug" ]; then
        debug="true"
    fi
done

# Vérification de l'argument CLASS_HASH
if [ -z "$1" ]; then
    echo "Error: No CLASS_HASH provided. Usage: ./deploy_contract.sh <CLASS_HASH>"
    exit 1
fi

# Vérification de l'argument CLASS_HASH
if [ -z "$2" ]; then
    echo "Error: No CLASS_HASH provided. Usage: ./deploy_contract.sh <CLASS_HASH>"
    exit 1
fi

class_hash=$1
PROJECT=0x06bdcca1d679f32955b1fd1c3116d0b72ae42b31c2833e22ba179fd0581d5a31
OWNER=$DEPLOYER_ADDRESS
ERC20=$2
PUBLIC_SALE_OPEN=1
MAX_VALUE=20000000000
UNIT_PRICE=11

# Deploy the contract
deploy() {
    sleep 5
    
    if [[ $debug == "true" ]]; then        
        printf "deploy %s %s %s %s u256:%s u256:%s %s --keystore-password KEYSTORE_PASSWORD --watch\n" "$class_hash" "$PROJECT"  "$ERC20" "$PUBLIC_SALE_OPEN" "$MAX_VALUE" "$UNIT_PRICE" "$OWNER" >> debug_minter.log
    fi
    output=$(starkli deploy $class_hash "$PROJECT" "$ERC20" "$PUBLIC_SALE_OPEN" u256:"$MAX_VALUE" u256:"$UNIT_PRICE" "$OWNER" --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)

    if [[ $output == *"Error"* ]]; then
        echo "Error: $output"
        exit 1
    fi

    # contract_address=$(
        echo "$output"
        #  | grep -o 'Contract deployed: 0x[0-9a-fA-F]\+' | awk '{print $NF}')
    # echo "Contract deployed at address: $contract_address"
}

deploy