#!/bin/bash
source ../.env

# Check if --debug parameter is passed
debug="false"
for arg in "$@"
do
    if [ "$arg" == "--debug" ]
    then
        debug="true"
    fi
done

SIERRA_FILE=../target/dev/carbon_v3_Project.contract_class.json
NAME="TokCC"
SYMBOL="CARBT"
OWNER=0x01e2F67d8132831f210E19c5Ee0197aA134308e16F7f284bBa2c72E28FC464D2
STARTING_YEAR=2024
NUMBER_OF_YEARS=20
PROJECT_CARBON=121099000000
TIMES="21 1674579600 1706115600 1737738000 1769274000 1800810000 1832346000 1863968400 1895504400 1927040400 1958576400 1990198800 2021734800 2053270800 2084806800 2116429200 2147965200 2179501200 2211037200 2242659600 2274195600 2305731600"
ABSORPTIONS="21 0 29609535 47991466 88828605 118438140 370922507 623406874 875891241 1128375608 1380859976 2076175721 2771491466 3466807212 4162122957 4857438703 5552754448 6248070193 6943385939 7638701684 8000000000 8000000000"

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
        printf "declare %s\n" "$SIERRA_FILE" > debug_project.log
    fi
    output=$(starkli declare $SIERRA_FILE --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)

    if [[ $output == *"Error"* ]]; then
        echo "Error: $output"
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
# $1 - Name
# $2 - Symbol
# $3 - Decimals
# $4 - Owner
deploy() {
    class_hash=$(declare | tail -n 1)
    sleep 5
    if [[ $debug == "true" ]]; then
        printf "deploy %s %s %s %s %s %s \n" "$class_hash" "$NAME" "$SYMBOL" "$OWNER" "$STARTING_YEAR" "$NUMBER_OF_YEARS" >> debug_project.log
    fi
    output=$(starkli deploy $class_hash str:"$NAME" str:"$SYMBOL" "$OWNER" $STARTING_YEAR $NUMBER_OF_YEARS --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)

    if [[ $output == *"Error"* ]]; then
        echo "Error: $output"
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

setup() {
    contract=$(deploy)
    sleep 5
    
    if [[ $debug == "true" ]]; then
        printf "invoke %s set_project_carbon u256:%s \n" "$contract" "$PROJECT_CARBON" >> debug_project.log
    fi
    output=$(starkli invoke $contract set_project_carbon u256:$PROJECT_CARBON --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)
    if [[ $output == *"Error"* ]]; then
        echo "Error: $output"
        exit 1
    fi
    echo "Success: $output"

    if [[ $debug == "true" ]]; then
        printf "invoke %s set_absorptions %s %s \n" "$contract" "$TIMES" "$ABSORPTIONS" >> debug_project.log
    fi
    output=$(starkli invoke $contract set_absorptions $TIMES $ABSORPTIONS --keystore-password $KEYSTORE_PASSWORD --watch 2>&1)
    if [[ $output == *"Error"* ]]; then
        echo "Error: $output"
        exit 1
    fi
    echo "Success: $output"

    echo $contract
}

contract_address=$(setup)
echo $contract_address