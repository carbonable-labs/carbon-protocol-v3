#!/bin/bash
source ./.env

# Check if --debug parameter is passed
debug="false"
for arg in "$@"
do
    if [ "$arg" == "--debug" ]
    then
        debug="true"
    fi
done

SIERRA_FILE=./target/dev/carbon_v3_Minter.contract_class.json
PROJECT=0x06bdcca1d679f32955b1fd1c3116d0b72ae42b31c2833e22ba179fd0581d5a31
OWNER=0x01e2F67d8132831f210E19c5Ee0197aA134308e16F7f284bBa2c72E28FC464D2
ERC20=0x01bd7237484b074609961b53f7d8978e921127e53a2af358e59b4b80eb29d640
PUBLIC_SALE_OPEN=1
MAX_VALUE=20000000000
UNIT_PRICE=11

# build the solution
build() {
    output=$(scarb build 2>&1)

    if [[ $output == *"Error"* ]]; then
        echo "Error: $output"
        exit 1
    fi
}

# declare the contract
declare() {
    build
    if [[ $debug == "true" ]]; then
        printf "declare %s --keystore-password KEYSTORE_PASSWORD --watch\n" "$SIERRA_FILE" > debug_minter.log
    fi
    output=$(starkli declare $SIERRA_FILE --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)

    if [[ $output == *"Error"* ]]; then
        echo "Error: $output"
        exit 1
    fi

    address=$(echo "$output" | grep -o 'Contract hash : 0x[0-9a-fA-F]\+' | awk '{print $NF}')
    echo $address
}

# deploy the contract
# $1 - Name
# $2 - Symbol
# $3 - Decimals
# $4 - Owner
deploy() {
    class_hash=$(declare | tail -n 1)
    sleep 5
    
    if [[ $debug == "true" ]]; then        
        printf "deploy %s %s %s %s u256:%s u256:%s %s --keystore-password KEYSTORE_PASSWORD --watch\n" "$class_hash" "$PROJECT"  "$ERC20" "$PUBLIC_SALE_OPEN" "$MAX_VALUE" "$UNIT_PRICE" "$OWNER" >> debug_minter.log
    fi
    output=$(starkli deploy $class_hash "$PROJECT" "$ERC20" "$PUBLIC_SALE_OPEN" u256:"$MAX_VALUE" u256:"$UNIT_PRICE" "$OWNER" --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)

    if [[ $output == *"Error"* ]]; then
        echo "Error: $output"
        exit 1
    fi

    address=$(echo "$output" |  grep -o 'Contract deployed: 0x[0-9a-fA-F]\+' | awk '{print $NF}')
    echo $address
}

contract_address=$(deploy)
echo $contract_address