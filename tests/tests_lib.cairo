// Starknet deps

use starknet::{ContractAddress, contract_address_const};

// External deps

use openzeppelin::utils::serde::SerializedAppend;
use snforge_std as snf;
use snforge_std::{CheatTarget, ContractClassTrait, EventSpy, SpyOn, start_prank, stop_prank};
use alexandria_storage::list::{List, ListTrait};

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

fn get_mock_times() -> Span<u64> {
    let times: Span<u64> = array![
        // 1674579600,
        1706115600,
        1737738000,
        1769274000,
        1800810000,
        1832346000,
        1863968400,
        1895504400,
        1927040400,
        1958576400,
        1990198800,
        2021734800,
        2053270800,
        2084806800,
        2116429200,
        2147965200,
        2179501200,
        2211037200,
        2242659600,
        2274195600
    ]
        .span();
    times
}

fn get_mock_absorptions() -> Span<u128> {
    let absorptions: Span<u128> = array![
        0,
        1000000000,
        4799146600,
        8882860500,
        11843814000,
        37092250700,
        62340687400,
        87589124100,
        112837560800,
        138085997600,
        207617572100,
        277149146600,
        346680721200,
        416212295700,
        485743870300,
        555275444800,
        624807019300,
        694338593900,
        763870168400,
        800000000000
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
fn share_to_buy_amount(minter_address: ContractAddress, share: u256) -> u256 {
    let minter = IMintDispatcher { contract_address: minter_address };
    let max_money_amount = minter.get_max_money_amount();
    share * max_money_amount / CC_DECIMALS_MULTIPLIER
}

///
/// Deploy and setup functions
/// 

fn deploy_project() -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Project');
    let uri = 'uri';
    let starting_year: u64 = 2024;
    let number_of_years: u64 = 20;
    let mut calldata: Array<felt252> = array![
        uri,
        contract_address_const::<'OWNER'>().into(),
        starting_year.into(),
        number_of_years.into()
    ];
    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

fn setup_project(
    contract_address: ContractAddress,
    project_carbon: u128,
    times: Span<u64>,
    absorptions: Span<u128>
) {
    let vintages = IVintageDispatcher { contract_address };
    // Fake the owner to call set_absorptions and set_project_carbon which can only be run by owner
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    start_prank(CheatTarget::One(contract_address), owner_address);

    vintages.set_vintages(absorptions, 2024);
    vintages.set_project_carbon(project_carbon);
}

fn default_setup_and_deploy() -> (ContractAddress, EventSpy) {
    let (project_address, spy) = deploy_project();
    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u128> = get_mock_absorptions();
    setup_project(project_address, 8000000000, times, absorptions,);
    (project_address, spy)
}

/// Deploys the offsetter contract.
fn deploy_offsetter(project_address: ContractAddress) -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Offsetter');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    let mut calldata: Array<felt252> = array![];
    calldata.append(project_address.into());
    calldata.append(owner.into());

    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

/// Deploys a minter contract.
fn deploy_minter(
    project_address: ContractAddress, payment_address: ContractAddress
) -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Minter');
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

    let contract_address = contract.deploy(@calldata).unwrap();
    let mut spy = snf::spy_events(SpyOn::One(contract_address));
    (contract_address, spy)
}

/// Deploy erc20 contract.
fn deploy_erc20() -> (ContractAddress, EventSpy) {
    let contract = snf::declare('USDCarb');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    let mut calldata: Array<felt252> = array![];
    calldata.append(owner.into());
    calldata.append(owner.into());
    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

fn fuzzing_setup(cc_supply: u128) -> (ContractAddress, ContractAddress, ContractAddress, EventSpy) {
    let (project_address, spy) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let times: Span<u64> = get_mock_times();
    // Tests are done on a single vintage, thus the absorptions are the same
    let absorptions: Span<u128> = array![
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
    setup_project(project_address, 8000000000, times, absorptions,);
    (project_address, minter_address, erc20_address, spy)
}

/// Utility function to buy a share of the total supply.
/// The share is calculated as a percentage of the total supply. We use share instead of amount
/// to make it easier to determine the expected values, but in practice the amount is used.
fn buy_utils(
    owner_address: ContractAddress,
    caller_address: ContractAddress,
    minter_address: ContractAddress,
    share: u256
) {
    // [Prank] Use caller (usually user) as caller for the Minter contract
    start_prank(CheatTarget::One(minter_address), caller_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let erc20_address: ContractAddress = minter.get_payment_token_address();
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };

    let amount_to_buy = share_to_buy_amount(minter_address, share);
    // [Prank] Use owner as caller for the ERC20 contract
    start_prank(CheatTarget::One(erc20_address), owner_address); // Owner holds initial supply
    erc20.transfer(caller_address, amount_to_buy);

    // [Prank] Use caller address (usually user) as caller for the ERC20 contract
    start_prank(CheatTarget::One(erc20_address), caller_address);
    erc20.approve(minter_address, amount_to_buy);

    // [Prank] Use Minter as caller for the ERC20 contract
    start_prank(CheatTarget::One(erc20_address), minter_address);
    // [Prank] Use caller (usually user) as caller for the Minter contract
    start_prank(CheatTarget::One(minter_address), caller_address);
    minter.public_buy(amount_to_buy, false);

    stop_prank(CheatTarget::One(erc20_address));
    stop_prank(CheatTarget::One(minter_address));
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
    let (project_address, minter_address, _, _) = fuzzing_setup(supply);
    // let vintages = IVintageDispatcher { contract_address: project_address };
    let project = IProjectDispatcher { contract_address: project_address };
    // Setup Roles for the contracts
    start_prank(CheatTarget::One(project_address), owner_address);
    project.grant_minter_role(minter_address);
    stop_prank(CheatTarget::One(project_address));

    // assert(vintages.is_setup(), 'Error during setup');
    buy_utils(owner_address, user_address, minter_address, share);

    start_prank(CheatTarget::One(project_address), user_address);

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

    start_prank(CheatTarget::One(project_address), receiver_address);
    project
        .safe_transfer_from(
            receiver_address, user_address, token_id, amount.into(), array![].span()
        );

    let balance_owner = project.balance_of(user_address, token_id);
    assert(equals_with_error(balance_owner, initial_balance, 10), 'Error balance owner 2');
    let balance_receiver = project.balance_of(receiver_address, token_id);
    assert(equals_with_error(balance_receiver, 0, 10), 'Error balance receiver 2');
}
