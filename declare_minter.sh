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

SIERRA_FILE=./target/dev/carbon_v3_Minter.contract_class.json

# Build the solution
build() {
    output=$(scarb build 2>&1)

    if [[ $output == *"Error"* ]]; then
        echo "Error: $output"
        exit 1
    fi
}

# Declare the contract
declare_contract() {
    build
    if [[ $debug == "true" ]]; then
        printf "declare %s --keystore-password KEYSTORE_PASSWORD --watch\n" "$SIERRA_FILE" > debug_minter.log
    fi
    output=$(starkli declare $SIERRA_FILE --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)

    if [[ $output == *"Error"* ]]; then
        echo "Error: $output"
        exit 1
    fi

    # class_hash=$(
        echo "$output"
        #  | grep -o 'Contract hash : 0x[0-9a-fA-F]\+' | awk '{print $NF}')
    # echo "Class hash: $class_hash"
}

declare_contract