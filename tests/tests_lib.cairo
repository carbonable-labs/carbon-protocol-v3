use core::traits::TryInto;
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
use carbon_v3::models::constants::{CC_DECIMALS_MULTIPLIER, MULTIPLIER_TONS_TO_MGRAMS};

// Components

use carbon_v3::components::vintage::interface::{
    IVintage, IVintageDispatcher, IVintageDispatcherTrait
};
use carbon_v3::components::minter::interface::{IMint, IMintDispatcher, IMintDispatcherTrait};
use openzeppelin::token::erc1155::ERC1155Component;


// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};


///
/// Mock Data
///

const DEFAULT_REMAINING_MINTABLE_CC: u256 = 80000000000000;
const STARTING_YEAR: u32 = 2024;

fn get_mock_absorptions() -> Span<u256> {
    let absorptions: Span<u256> = array![
        0,
        100000000000,
        479914660000,
        888286050000,
        1184381400000,
        3709225070000,
        6234068740000,
        8758912410000,
        11283756080000,
        13808599760000,
        20761757210000,
        27714914660000,
        34668072120000,
        41621229570000,
        48574387030000,
        55527544480000,
        62480701930000,
        69433859390000,
        76387016840000,
        80000000000000,
        82500000000000,
    // 25000000000000000, // 25 000CC, in grams
    // 50000000000000000,
    // 75000000000000000,
    // 100000000000000000,
    // 125000000000000000,
    // 150000000000000000,
    // 175000000000000000,
    // 200000000000000000,
    // 225000000000000000,
    // 250000000000000000,
    // 275000000000000000,
    // 300000000000000000,
    // 325000000000000000,
    // 350000000000000000,
    // 375000000000000000,
    // 400000000000000000,
    // 425000000000000000,
    // 450000000000000000,
    // 475000000000000000,
    // 500000000000000000
    ]
        .span();

    let mut yearly_absorptions: Array<u256> = array![];
    let mut index: u32 = 0;
    loop {
        if index >= absorptions.len() - 1 {
            break;
        }
        let current_abs = *absorptions.at(index + 1) - *absorptions.at(index);
        yearly_absorptions.append(current_abs);
        index += 1;
    };

    let yearly_absorptions = yearly_absorptions.span();
    yearly_absorptions
}

fn get_mock_absorptions_times_2() -> Span<u256> {
    let yearly_absorptions: Span<u256> = get_mock_absorptions();
    let mut yearly_absorptions_times_2: Array<u256> = array![];
    let mut index = 0;
    loop {
        if index >= yearly_absorptions.len() {
            break;
        }
        yearly_absorptions_times_2.append(*yearly_absorptions.at(index) * 2);
        index += 1;
    };
    yearly_absorptions_times_2.span()
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

///
/// Deploy and setup functions
/// 

fn deploy_project() -> ContractAddress {
    let contract = snf::declare("Project").expect('Declaration failed');
    let number_of_years: u64 = 20;
    let mut calldata: Array<felt252> = array![
        contract_address_const::<'OWNER'>().into(), STARTING_YEAR.into(), number_of_years.into()
    ];
    let (contract_address, _) = contract.deploy(@calldata).expect('Project deployment failed');

    contract_address
}

fn setup_project(contract_address: ContractAddress, yearly_absorptions: Span<u256>) {
    let vintages = IVintageDispatcher { contract_address };
    // Fake the owner to call set_vintages and set_project_carbon which can only be run by owner
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    start_cheat_caller_address(contract_address, owner_address);
    vintages.set_vintages(yearly_absorptions, STARTING_YEAR);
    stop_cheat_caller_address(contract_address);
}

fn default_setup_and_deploy() -> ContractAddress {
    let project_address = deploy_project();
    let yearly_absorptions: Span<u256> = get_mock_absorptions();
    setup_project(project_address, yearly_absorptions);
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
    start_cheat_caller_address(project_address, owner);
    let public_sale: bool = true;
    let low: felt252 = DEFAULT_REMAINING_MINTABLE_CC.low.into();
    let high: felt252 = DEFAULT_REMAINING_MINTABLE_CC.high.into();
    let unit_price: felt252 = 11;
    let mut calldata: Array<felt252> = array![
        project_address.into(),
        payment_address.into(),
        public_sale.into(),
        low,
        high,
        unit_price,
        0,
        owner.into()
    ];

    let (contract_address, _) = contract.deploy(@calldata).expect('Minter deployment failed');
    contract_address
}

fn deploy_minter_specific_max_mintable(
    project_address: ContractAddress, payment_address: ContractAddress, max_mintable_cc: u256
) -> ContractAddress {
    let contract = snf::declare("Minter").expect('Declaration failed');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    let low: felt252 = max_mintable_cc.low.into();
    let high: felt252 = max_mintable_cc.high.into();
    start_cheat_caller_address(project_address, owner);
    let public_sale: bool = true;
    let unit_price: felt252 = 11;
    let mut calldata: Array<felt252> = array![
        project_address.into(),
        payment_address.into(),
        public_sale.into(),
        low,
        high,
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

fn fuzzing_setup(cc_supply: u256) -> (ContractAddress, ContractAddress, ContractAddress) {
    let project_address = deploy_project();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    // Tests are done on a single vintage, thus the yearly supply are the same
    let mut total_absorption = 0;
    let mut index = 0;
    let num_vintages: usize = 20;
    let mut yearly_absorptions: Array<u256> = Default::default();
    let mock_absorptions = get_mock_absorptions();
    loop {
        if index >= num_vintages {
            break;
        }
        total_absorption += cc_supply;
        yearly_absorptions.append(cc_supply);
        index += 1;
    };
    setup_project(project_address, mock_absorptions);
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

    // If user wants to buy 1 carbon credit, the input should be 1*MULTIPLIER_TONS_TO_MGRAMS
    let money_to_buy = total_cc_amount * minter.get_unit_price() / MULTIPLIER_TONS_TO_MGRAMS;

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
    raw_supply: u256,
    raw_cc_amount: u256,
    raw_last_digits_share: u256,
    percentage_of_balance_to_send: u256,
    max_supply_for_vintage: u256
) {
    let supply = raw_supply % max_supply_for_vintage;
    if raw_cc_amount == 0 || supply == 0 {
        return;
    }

    let cc_amount_to_buy = raw_cc_amount % supply;
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    let (project_address, minter_address, _) = fuzzing_setup(supply);
    let project = IProjectDispatcher { contract_address: project_address };
    // Setup Roles for the contracts
    start_cheat_caller_address(project_address, owner_address);
    project.grant_minter_role(minter_address);
    start_cheat_caller_address(project_address, minter_address);
    buy_utils(owner_address, user_address, minter_address, cc_amount_to_buy);
    let sum_balance = helper_sum_balance(project_address, user_address);
    assert(equals_with_error(sum_balance, cc_amount_to_buy, 100), 'Error sum balance');

    start_cheat_caller_address(project_address, user_address);

    // Check the balance of the user, total cc amount bought should be distributed proportionally
    helper_check_vintage_balances(project_address, user_address, cc_amount_to_buy);

    // Receiver should have 0 cc
    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    helper_check_vintage_balances(project_address, receiver_address, 0);

    let token_id = 1;
    let balance_vintage_user_before = project.balance_of(user_address, token_id);
    project
        .safe_transfer_from(
            user_address, receiver_address, token_id, balance_vintage_user_before, array![].span()
        );

    let balance_vintage_user_after = project.balance_of(user_address, token_id);
    assert(equals_with_error(balance_vintage_user_after, 0, 100), 'Error balance vintage user');

    let balance_vintage_receiver = project.balance_of(receiver_address, token_id);
    assert(
        equals_with_error(balance_vintage_receiver, balance_vintage_user_before, 100),
        'Error balance vintage receiver'
    );
// let token_id = 1;
// let initial_balance = project.balance_of(user_address, token_id);
// println!("initial_balance: {}", initial_balance);
// let vintages = IVintageDispatcher { contract_address: project_address };
// let number_of_vintages = vintages.get_num_vintages();
// println!("number_of_vintages: {}", number_of_vintages);
// let expected_balance_vintage = cc_amount_to_buy
//     / (number_of_vintages.into()); // Evenly distributed
// let amount = percentage_of_balance_to_send * initial_balance / 10_000;
// println!("expected balance: {}", expected_balance_vintage);
// println!("balance user: {}", initial_balance);
// println!("amount to send: {}", amount);
// equals_with_error(initial_balance, expected_balance_vintage, 100);
// project
//     .safe_transfer_from(
//         user_address, receiver_address, token_id, amount.into(), array![].span()
//     );
// let balance_owner = project.balance_of(user_address, token_id);
// assert(
//     equals_with_error(balance_owner, initial_balance - amount, 100), 'Error balance owner 1'
// );
// let balance_receiver = project.balance_of(receiver_address, token_id);
// assert(equals_with_error(balance_receiver, amount, 100), 'Error balance receiver 1');

// println!("2");
// start_cheat_caller_address(project_address, receiver_address);
// project
//     .safe_transfer_from(
//         receiver_address, user_address, token_id, amount.into(), array![].span()
//     );
// let balance_owner = project.balance_of(user_address, token_id);
// assert(equals_with_error(balance_owner, initial_balance, 100), 'Error balance owner 2');
// let balance_receiver = project.balance_of(receiver_address, token_id);
// assert(equals_with_error(balance_receiver, 0, 100), 'Error balance receiver 2');
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
        total_balance += balance;
        index += 1;
    };
    total_balance
}

fn helper_check_vintage_balances(
    project_address: ContractAddress, user_address: ContractAddress, total_cc_bought: u256
) {
    let project = IProjectDispatcher { contract_address: project_address };
    let vintages = IVintageDispatcher { contract_address: project_address };
    let num_vintages: usize = vintages.get_num_vintages();
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let token_ids = helper_get_token_ids(project_address);
    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        }
        let token_id = *token_ids.at(index);
        let proportion_supply = vintages.get_carbon_vintage(token_id).supply
            * CC_DECIMALS_MULTIPLIER
            / initial_total_supply;
        let balance = project.balance_of(user_address, token_id);
        let expected_balance = total_cc_bought * proportion_supply / CC_DECIMALS_MULTIPLIER;
        assert(equals_with_error(balance, expected_balance, 10), 'Error vintage balance');
        index += 1;
    };
}

fn helper_check_vintage_balance(
    project_address: ContractAddress,
    user_address: ContractAddress,
    token_id: u256,
    total_cc_bought: u256
) {
    let project = IProjectDispatcher { contract_address: project_address };
    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let proportion_supply = vintages.get_carbon_vintage(token_id).supply
        * CC_DECIMALS_MULTIPLIER
        / initial_total_supply;
    let balance = project.balance_of(user_address, token_id);
    let expected_balance = total_cc_bought * proportion_supply / CC_DECIMALS_MULTIPLIER;
    assert(equals_with_error(balance, expected_balance, 10), 'Error vintage balance');
}

fn helper_expected_transfer_event(
    project_address: ContractAddress,
    operator: ContractAddress,
    from: ContractAddress,
    to: ContractAddress,
    token_ids: Span<u256>,
    total_cc_amount: u256
) -> ERC1155Component::Event {
    let project = IProjectDispatcher { contract_address: project_address };
    if token_ids.len() == 1 {
        ERC1155Component::Event::TransferSingle(
            ERC1155Component::TransferSingle {
                operator, from, to, id: *token_ids.at(0), value: total_cc_amount
            }
        )
    } else {
        let mut values: Array<u256> = Default::default();
        let mut index = 0;
        loop {
            if index >= token_ids.len() {
                break;
            }
            let value = project.internal_to_cc(total_cc_amount, *token_ids.at(index));
            values.append(value);
            index += 1;
        };
        let values = values.span();
        let mut index = 0;
        loop {
            if index >= token_ids.len() {
                break;
            }
            index += 1;
        };
        ERC1155Component::Event::TransferBatch(
            ERC1155Component::TransferBatch { operator, from, to, ids: token_ids, values }
        )
    }
}
