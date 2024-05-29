#!/bin/bash
source ../.env

# Check if --debug parameter is passed
debug="true"
for arg in "$@"
do
    if [ "$arg" == "--debug" ]
    then
        debug="true"
    fi
done

SIERRA_FILE=../target/dev/carbon_v3_USDCarb.contract_class.json
OWNER=0x01250AC88f300dcF578e4EA9ae6B16BB08004AFdc4cB0E5947192F7830612AA6

# build the solution
build() {
    output=$(scarb build 2>&1)

    if [[ $output == *"Error"* ]]; then
        echo "Error at building: $output"
        exit 1
    fi
}

# declare the contract
declare() {
    build
        if [[ $debug == "true" ]]; then
        printf "declare %s\n" "$SIERRA_FILE" > debug_usdcarb.log
    fi
    output=$(starkli declare $SIERRA_FILE --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)

    if [[ $output == *"Error"* ]]; then
        echo "Error at declaration: $output"
        exit 1
    fi

    # Check if ggrep is available
    if command -v ggrep >/dev/null 2>&1; then
        address=$(echo -e "$output" | ggrep -oP '0x[0-9a-fA-F]+')
    else
        # If ggrep is not available, use grep
        address=$(echo -e "$output" | grep -oP '0x[0-9a-fA-F]+')
    fi
    echo $address
}

# deploy the contract
# $1 - Recipient
# $2 - Owner
deploy() {
    class_hash=$(declare | tail -n 1)
    sleep 5
    if [[ $debug == "true" ]]; then
        printf "deploy %s %s \n" "$OWNER" "$OWNER" >> debug_usdcarb.log
    fi
    # output=$(starkli deploy --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)
    output=$(starkli deploy $class_hash "$OWNER" "$OWNER" --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)


    if [[ $output == *"Error"* ]]; then
        echo "Error at deployment: $output"
        exit 1
    fi

    # Check if ggrep is available
    if command -v ggrep >/dev/null 2>&1; then
        address=$(echo -e "$output" | ggrep -oP '0x[0-9a-fA-F]+' | tail -n 1) 
    else
        # If ggrep is not available, use grep
        address=$(echo -e "$output" | grep -oP '0x[0-9a-fA-F]+' | tail -n 1) 
    fi
    echo $address
}

contract_address=$(deploy)
echo $contract_address
printf "contract deployed at: %s\n" "$contract_address" >> debug_usdcarb.log