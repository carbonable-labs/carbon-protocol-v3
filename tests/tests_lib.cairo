// Starknet deps

use starknet::{ContractAddress, contract_address_const};

// External deps

use openzeppelin::utils::serde::SerializedAppend;
use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, EventSpy, spy_events, EventSpyTrait, EventSpyAssertionsTrait,
    start_cheat_caller_address, stop_cheat_caller_address
};

// Models 

use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
use carbon_v3::models::constants::CC_DECIMALS_MULTIPLIER;

// Components

use carbon_v3::components::vintage::interface::{
    IVintage, IVintageDispatcher, IVintageDispatcherTrait
};
use carbon_v3::components::minter::interface::{IMint, IMintDispatcher, IMintDispatcherTrait};

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};


///
/// Mock Data
///

fn get_mock_absorptions() -> Span<u128> {
    let absorptions: Span<u128> = array![
        // 0,
        // 1000000000,
        // 4799146600,
        // 8882860500,
        // 11843814000,
        // 37092250700,
        // 62340687400,
        // 87589124100,
        // 112837560800,
        // 138085997600,
        // 207617572100,
        // 277149146600,
        // 346680721200,
        // 416212295700,
        // 485743870300,
        // 555275444800,
        // 624807019300,
        // 694338593900,
        // 763870168400,
        // 800000000000
        0,
        25000000000000000, // 25 000CC, in grams
        50000000000000000,
        75000000000000000,
        100000000000000000,
        125000000000000000,
        150000000000000000,
        175000000000000000,
        200000000000000000,
        225000000000000000,
        250000000000000000,
        275000000000000000,
        300000000000000000,
        325000000000000000,
        350000000000000000,
        375000000000000000,
        400000000000000000,
        425000000000000000,
        450000000000000000,
        475000000000000000
    ]
        .span();
    let mut yearly_absorptions: Array<u128> = array![];
    let mut index: u32 = 0;
    let mut max = absorptions.len() - 1;
    loop {
        if index == max {
            break;
        }
        let current_abs = *absorptions.at(index + 1) - *absorptions.at(index);
        yearly_absorptions.append(current_abs);
        index += 1;
    };
    yearly_absorptions.span()
}


///
/// Math functions
/// 

fn equals_with_error(a: u256, b: u256, error: u256) -> bool {
    let diff = if a > b {
        a - b
    } else {
        b - a
    };
    diff <= error
}

// testing with shares is easier to determine the expected values instead of amount in dollars
fn share_to_buy_amount(project_address: ContractAddress, share: u256) -> u256 {
    let project = IProjectDispatcher { contract_address: project_address };
    let max_money_amount = project.get_max_money_amount();
    share * max_money_amount / CC_DECIMALS_MULTIPLIER
}

///
/// Deploy and setup functions
/// 

fn deploy_project() -> ContractAddress {
    let contract = snf::declare("Project").expect('Declaration failed');
    let starting_year: u64 = 2024;
    let number_of_years: u64 = 20;
    let mut calldata: Array<felt252> = array![
        contract_address_const::<'OWNER'>().into(), starting_year.into(), number_of_years.into()
    ];
    let (contract_address, _) = contract.deploy(@calldata).expect('Project deployment failed');

    contract_address
}

fn setup_project(
    contract_address: ContractAddress, project_carbon: u128, yearly_absorptions: Span<u128>
) {
    let vintages = IVintageDispatcher { contract_address };
    // Fake the owner to call set_vintages and set_project_carbon which can only be run by owner
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    start_cheat_caller_address(contract_address, owner_address);

    vintages.set_vintages(yearly_absorptions, 2024);
    vintages.set_project_carbon(project_carbon);
}

fn default_setup_and_deploy() -> ContractAddress {
    let project_address = deploy_project();
    let yearly_absorptions: Span<u128> = get_mock_absorptions();
    setup_project(project_address, 8000000000, yearly_absorptions);
    project_address
}

/// Deploys the offsetter contract.
fn deploy_offsetter(project_address: ContractAddress) -> ContractAddress {
    let contract = snf::declare("Offsetter").expect('Declaration failed');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    let mut calldata: Array<felt252> = array![];
    calldata.append(project_address.into());
    calldata.append(owner.into());

    let (contract_address, _) = contract.deploy(@calldata).expect('Offsetter deployment failed');

    contract_address
}

/// Deploys a minter contract.
fn deploy_minter(
    project_address: ContractAddress, payment_address: ContractAddress
) -> ContractAddress {
    let contract = snf::declare("Minter").expect('Declaration failed');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    let public_sale: bool = true;
    let max_value: felt252 = 8000000000;
    let unit_price: felt252 = 11;
    let mut calldata: Array<felt252> = array![
        project_address.into(),
        payment_address.into(),
        public_sale.into(),
        max_value,
        0,
        unit_price,
        0,
        owner.into()
    ];

    let (contract_address, _) = contract.deploy(@calldata).expect('Minter deployment failed');
    contract_address
}

/// Deploy erc20 contract.
fn deploy_erc20() -> ContractAddress {
    let contract = snf::declare("USDCarb").expect('Declaration failed');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    let mut calldata: Array<felt252> = array![];
    calldata.append(owner.into());
    calldata.append(owner.into());
    let (contract_address, _) = contract.deploy(@calldata).expect('Erc20 deployment failed');

    contract_address
}

fn fuzzing_setup(cc_supply: u128) -> (ContractAddress, ContractAddress, ContractAddress) {
    let project_address = deploy_project();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    // Tests are done on a single vintage, thus the absorptions are the same
    let yearly_absorptions: Span<u128> = array![
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply
    ]
        .span();
    setup_project(project_address, 8000000000, yearly_absorptions);
    (project_address, minter_address, erc20_address)
}

/// Utility function to buy a share of the total supply.
/// The share is calculated as a percentage of the total supply. We use share instead of amount
/// to make it easier to determine the expected values, but in practice the amount is used.
fn buy_utils(
    owner_address: ContractAddress,
    caller_address: ContractAddress,
    minter_address: ContractAddress,
    total_cc_amount: u256
) {
    // [Prank] Use caller (usually user) as caller for the Minter contract
    start_cheat_caller_address(minter_address, caller_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let erc20_address: ContractAddress = minter.get_payment_token_address();
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };

    // If user wants to buy 1 carbon credit, the input should be 1*CC_DECIMALS_MULTIPLIER
    let money_to_buy = total_cc_amount * minter.get_unit_price() / CC_DECIMALS_MULTIPLIER;

    // [Prank] Use owner as caller for the ERC20 contract
    start_cheat_caller_address(erc20_address, owner_address); // Owner holds initial supply
    erc20.transfer(caller_address, money_to_buy);

    // [Prank] Use caller address (usually user) as caller for the ERC20 contract
    start_cheat_caller_address(erc20_address, caller_address);
    erc20.approve(minter_address, money_to_buy);

    // [Prank] Use Minter as caller for the ERC20 contract
    start_cheat_caller_address(erc20_address, minter_address);
    // [Prank] Use caller (usually user) as caller for the Minter contract
    start_cheat_caller_address(minter_address, caller_address);
    minter.public_buy(total_cc_amount);

    stop_cheat_caller_address(minter_address);
    stop_cheat_caller_address(erc20_address);
}


///
/// Tests functions to be called by the test runner
/// 

fn perform_fuzzed_transfer(
    raw_supply: u128,
    raw_share: u256,
    raw_last_digits_share: u256,
    percentage_of_balance_to_send: u256,
    max_supply_for_vintage: u128
) {
    let supply = raw_supply % max_supply_for_vintage;
    if raw_share == 0 || supply == 0 {
        return;
    }
    let last_digits_share = raw_last_digits_share % 100;
    let share_modulo = raw_share % CC_DECIMALS_MULTIPLIER;
    let share = share_modulo * 100 + last_digits_share;
    let share = share / 100;

    if share == 0 {
        return;
    }

    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    let (project_address, minter_address, _) = fuzzing_setup(supply);
    let project = IProjectDispatcher { contract_address: project_address };
    // Setup Roles for the contracts
    start_cheat_caller_address(project_address, owner_address);
    project.grant_minter_role(minter_address);
    start_cheat_caller_address(project_address, minter_address);

    buy_utils(owner_address, user_address, minter_address, share);

    start_cheat_caller_address(project_address, user_address);

    let token_id = 1;
    let initial_balance = project.balance_of(user_address, token_id);
    let amount = percentage_of_balance_to_send * initial_balance / 10_000;
    project
        .safe_transfer_from(
            user_address, receiver_address, token_id, amount.into(), array![].span()
        );
    let balance_owner = project.balance_of(user_address, token_id);
    assert(equals_with_error(balance_owner, initial_balance - amount, 10), 'Error balance owner 1');
    let balance_receiver = project.balance_of(receiver_address, token_id);
    assert(equals_with_error(balance_receiver, amount, 10), 'Error balance receiver 1');

    start_cheat_caller_address(project_address, receiver_address);
    project
        .safe_transfer_from(
            receiver_address, user_address, token_id, amount.into(), array![].span()
        );

    let balance_owner = project.balance_of(user_address, token_id);
    assert(equals_with_error(balance_owner, initial_balance, 10), 'Error balance owner 2');
    let balance_receiver = project.balance_of(receiver_address, token_id);
    assert(equals_with_error(balance_receiver, 0, 10), 'Error balance receiver 2');
}

fn helper_get_token_ids(project_address: ContractAddress) -> Span<u256> {
    let vintages = IVintageDispatcher { contract_address: project_address };
    let num_vintages: usize = vintages.get_num_vintages();
    let mut tokens: Array<u256> = Default::default();
    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        }
        index += 1;
        tokens.append(index.into())
    };
    tokens.span()
}

fn helper_sum_balance(project_address: ContractAddress, user_address: ContractAddress) -> u256 {
    let project = IProjectDispatcher { contract_address: project_address };
    let vintage = IVintageDispatcher { contract_address: project_address };
    let num_vintages: usize = vintage.get_num_vintages();
    let mut total_balance: u256 = 0;

    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        }
        let balance = project.balance_of(user_address, index.into());
        println!("Balance for vintage {}: {}", index, balance);
        println!("vintage: {}", vintage.get_carbon_vintage(index.into()));
        total_balance += balance;
        index += 1;
    };
    total_balance
}
