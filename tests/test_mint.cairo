// TODO: 
// - check if is_setup is needed
// - refactor project setup into helper function?

// Starknet deps

use starknet::{ContractAddress, contract_address_const};

// External deps

use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, test_address, spy_events, EventSpy, CheatSpan, start_cheat_caller_address,
    stop_cheat_caller_address,
};

// Components

use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
use carbon_v3::components::vintage::VintageComponent;
use carbon_v3::components::vintage::VintageComponent::{Event, ProjectCarbonUpdate};
use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};


use carbon_v3::components::minter::interface::{IMintDispatcher, IMintDispatcherTrait};

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};
use carbon_v3::contracts::minter::Minter;
use carbon_v3::mock::usdcarb::USDCarb;

// Utils for testing purposes

use super::tests_lib::{
    get_mock_absorptions, equals_with_error, deploy_project, setup_project,
    default_setup_and_deploy, deploy_offsetter, deploy_erc20, deploy_minter, buy_utils
};

// Constants

const PROJECT_CARBON: u256 = 42;
const CC_DECIMALS_MULTIPLIER: u256 = 100_000_000_000_000;

// Signers

#[derive(Drop)]
struct Signers {
    owner: ContractAddress,
    anyone: ContractAddress,
}

#[derive(Drop)]
struct Contracts {
    project: ContractAddress,
    offseter: ContractAddress,
}

//
// Tests
//

// is_public_sale_open

#[test]
fn test_is_public_sale_open() {
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let sale_open = minter.is_public_sale_open();
    assert(sale_open == true, 'public sale not open');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_public_sale_open_without_owner_role() {
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };

    minter.set_public_sale_open(true);
}

#[test]
fn test_set_public_sale_open_with_owner_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    // [Prank] Use owner as caller to Minter contract
    start_cheat_caller_address(minter_address, owner_address);

    let minter = IMintDispatcher { contract_address: minter_address };

    minter.set_public_sale_open(true);
}

// public_buy

#[test]
fn test_public_buy() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);

    let yearly_absorptions: Span<u128> = get_mock_absorptions();
    let project_carbon: u128 = 8000000000;

    setup_project(project_address, project_carbon, yearly_absorptions);
    stop_cheat_caller_address(project_address);
    let minter = IMintDispatcher { contract_address: minter_address };

    let remaining_money = minter.get_available_money_amount();
    assert(remaining_money == project_carbon.into(), 'remaining money wrong value');

    let amount_to_buy: u256 = 1000000000;
    start_cheat_caller_address(erc20_address, owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.transfer(user_address, amount_to_buy);

    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, amount_to_buy);

    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);
    let tokenized_cc: Span<u256> = minter.public_buy(amount_to_buy, false);
    assert(tokenized_cc.len() == 19, 'should be 19 vintages');
}

// get_available_money_amount

#[test]
fn test_get_available_money_amount() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);

    let yearly_absorptions: Span<u128> = get_mock_absorptions();

    setup_project(project_address, 8000000000, yearly_absorptions);
    stop_cheat_caller_address(project_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let initial_money: u256 = 8000000000;

    let remaining_money = minter.get_available_money_amount();
    assert(remaining_money == initial_money, 'remaining money wrong value');

    let amount_to_buy: u256 = 1000;

    start_cheat_caller_address(erc20_address, owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.transfer(user_address, amount_to_buy);

    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, amount_to_buy);

    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);
    minter.public_buy(amount_to_buy, false);
    stop_cheat_caller_address(minter_address);
    stop_cheat_caller_address(erc20_address);

    let remaining_money_after_buy = minter.get_available_money_amount();
    assert(
        remaining_money_after_buy == initial_money - amount_to_buy, 'remaining money wrong value'
    );

    // Buy all the remaining money
    let remaining_money_to_buy = remaining_money_after_buy;
    start_cheat_caller_address(erc20_address, owner_address);
    erc20.transfer(user_address, remaining_money_to_buy);

    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, remaining_money_to_buy);
    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);
    minter.public_buy(remaining_money_to_buy, false);

    let remaining_money_after_buying_all = minter.get_available_money_amount();
    assert(remaining_money_after_buying_all == 0, 'remaining money wrong value');
}

// cancel_mint

#[test]
fn test_cancel_mint() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };

    start_cheat_caller_address(minter_address, owner_address);

    // Ensure the mint is not canceled initially
    let is_canceled = minter.is_canceled();
    assert(!is_canceled, 'mint should not be canceled');

    // Cancel the mint
    minter.cancel_mint(true);

    // Verify that the mint is canceled
    let is_canceled_after = minter.is_canceled();
    assert(is_canceled_after, 'mint should be canceled');

    // Reopen the mint
    minter.cancel_mint(false);

    // Verify that the mint is reopened
    let is_canceled_reopened = minter.is_canceled();
    assert(!is_canceled_reopened, 'mint should be reopened')
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_unit_price_without_owner_role() {
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let price: u256 = 100;
    minter.set_unit_price(price);
}

#[test]
fn test_set_unit_price_with_owner_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(minter_address, owner_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let price: u256 = 100;
    minter.set_unit_price(price);
}

#[test]
fn test_get_max_money_amount() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    // Default initial max amount of money = 8000000000
    let initial_max_money: u256 = 8000000000;

    let max_money = minter.get_max_money_amount();
    assert(max_money == initial_max_money, 'max money amount is incorrect');

    let amount_to_buy: u256 = 1000;
    start_cheat_caller_address(erc20_address, owner_address);

    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.approve(minter_address, amount_to_buy);
    start_cheat_caller_address(minter_address, owner_address);
    start_cheat_caller_address(erc20_address, minter_address);

    minter.public_buy(amount_to_buy, false);
    stop_cheat_caller_address(minter_address);
    stop_cheat_caller_address(erc20_address);

    // Verify the max money amount remains unchanged
    let max_money_after_buying_all = minter.get_max_money_amount();
    assert(max_money_after_buying_all == initial_max_money, 'max money is incorrect');
}

#[test]
fn test_get_min_money_amount_per_tx() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);
    start_cheat_caller_address(project_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let initial_min_money_per_tx: u256 = 0; // default value
    let min_money_per_tx = minter.get_min_money_amount_per_tx();
    assert!(min_money_per_tx == initial_min_money_per_tx, "initial min money per tx is incorrect");

    let amount_to_buy: u256 = 1000;
    start_cheat_caller_address(erc20_address, owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.transfer(user_address, amount_to_buy);

    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, amount_to_buy);

    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);

    minter.public_buy(amount_to_buy, false);

    // Verify the min money amount per transaction remains unchanged
    let min_money_per_tx_after_buy = minter.get_min_money_amount_per_tx();
    assert!(
        min_money_per_tx_after_buy == initial_min_money_per_tx,
        "min money per tx after buy is incorrect"
    );
}

#[test]
fn test_is_sold_out() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let is_sold_out_initial = minter.is_sold_out();
    assert(!is_sold_out_initial, 'should not be sold out');

    let remaining_money = minter.get_available_money_amount();
    start_cheat_caller_address(erc20_address, owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.transfer(user_address, remaining_money);

    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, remaining_money);

    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);
    minter.public_buy(remaining_money, false);

    let remaining_money_after_buying_all = minter.get_available_money_amount();
    assert(remaining_money_after_buying_all == 0, 'remaining money wrong');

    let is_sold_out_after = minter.is_sold_out();
    assert(is_sold_out_after, 'should be sold out');
}

#[test]
fn test_set_min_money_amount_per_tx() {
    // Deploy required contracts
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    // Verify that the min money amount per tx is 0 at the beginning
    let min_money_amount_per_tx = minter.get_min_money_amount_per_tx();
    assert(min_money_amount_per_tx == 0, 'Initial min per tx incorrect');

    let new_min_money_amount: u256 = 500;
    minter.set_min_money_amount_per_tx(new_min_money_amount);
    let updated_min_money_amount_per_tx = minter.get_min_money_amount_per_tx();
    assert(updated_min_money_amount_per_tx == new_min_money_amount, 'Updated min money incorrect');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_min_money_amount_per_tx_without_owner_role() {
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let amount: u256 = 100;
    minter.set_min_money_amount_per_tx(amount);
}

#[test]
#[should_panic(expected: 'Invalid min money amount per tx')]
fn test_set_min_money_amount_per_tx_panic() {
    // Deploy required contracts
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);
    start_cheat_caller_address(project_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);

    start_cheat_caller_address(erc20_address, owner_address);
    let minter = IMintDispatcher { contract_address: minter_address };

    let min_money_amount_per_tx = minter.get_min_money_amount_per_tx();
    assert(min_money_amount_per_tx == 0, 'Initial min per tx incorrect');

    let new_min_money_amount: u256 = 9999999999;
    minter.set_min_money_amount_per_tx(new_min_money_amount);
}

// get_carbonable_project_address

#[test]
fn test_get_carbonable_project_address() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(minter_address, user_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let carbonable_project_address = minter.get_carbonable_project_address();
    assert(carbonable_project_address == project_address, 'address does not match');
}

// get_payment_token_address

#[test]
fn test_get_payment_token_address() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(minter_address, user_address);
    let minter = IMintDispatcher { contract_address: minter_address };

    let payment_token_address = minter.get_payment_token_address();
    assert(payment_token_address == erc20_address, 'address does not match');
}

// set_unit_price

#[test]
fn test_set_unit_price() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(erc20_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);
    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the unit price is not set initially
    let unit_price = minter.get_unit_price();
    assert(unit_price == 11, 'unit price should be 11');

    // Set the unit price
    let new_unit_price: u256 = 1000;
    start_cheat_caller_address(minter_address, owner_address);
    minter.set_unit_price(new_unit_price);
    stop_cheat_caller_address(minter_address);

    let unit_price_after = minter.get_unit_price();
    assert(unit_price_after == new_unit_price, 'unit price wrong value');

    // Set the unit price to a large value
    let new_unit_price_large: u256 = 1000000000;
    start_cheat_caller_address(minter_address, owner_address);
    minter.set_unit_price(new_unit_price_large);
    stop_cheat_caller_address(minter_address);

    // Verify that the unit price is set correctly
    let unit_price_after_large = minter.get_unit_price();
    assert(unit_price_after_large == new_unit_price_large, 'unit price wrong value');
}

// get_unit_price

#[test]
fn test_get_unit_price() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(minter_address, user_address);
    let minter = IMintDispatcher { contract_address: minter_address };

    let unit_price = minter.get_unit_price();
    assert(unit_price == 11, 'unit price should be 11');
    stop_cheat_caller_address(minter_address);

    start_cheat_caller_address(minter_address, owner_address);
    let new_unit_price: u256 = 1000;
    start_cheat_caller_address(minter_address, owner_address);
    minter.set_unit_price(new_unit_price);
    stop_cheat_caller_address(minter_address);

    start_cheat_caller_address(minter_address, user_address);
    let unit_price_after = minter.get_unit_price();
    assert(unit_price_after == new_unit_price, 'unit price wrong value');
}

// set_unit_price_to_zero_panic

#[test]
#[should_panic(expected: 'Invalid unit price')]
fn test_set_unit_price_to_zero_panic() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(minter_address, owner_address);
    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the unit price is not set initially
    let unit_price = minter.get_unit_price();
    assert(unit_price == 11, 'unit price should be 11');

    // Set the unit price to 0 and it should panic
    let new_unit_price: u256 = 0;
    minter.set_unit_price(new_unit_price);
}

#[test]
fn test_withdraw() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(erc20_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    let minter = IMintDispatcher { contract_address: minter_address };
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    start_cheat_caller_address(project_address, owner_address);
    project.grant_minter_role(minter_address);

    start_cheat_caller_address(project_address, minter_address);
    let share: u256 = 10 * CC_DECIMALS_MULTIPLIER / 100; // 10%
    buy_utils(owner_address, owner_address, minter_address, share);
    start_cheat_caller_address(erc20_address, user_address);
    buy_utils(owner_address, user_address, minter_address, share);

    let balance_owner_before_withdraw = erc20.balance_of(owner_address);

    let balance_to_withdraw = erc20.balance_of(minter_address);
    start_cheat_caller_address(minter_address, owner_address);
    minter.withdraw();

    let balance_owner_after = erc20.balance_of(owner_address);
    assert(
        balance_owner_after == balance_owner_before_withdraw + balance_to_withdraw,
        'balance should be the same'
    );
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_withdraw_without_owner_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(erc20_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);
    start_cheat_caller_address(project_address, owner_address);
    let project = IProjectDispatcher { contract_address: project_address };
    let minter = IMintDispatcher { contract_address: minter_address };
    project.grant_minter_role(minter_address);

    start_cheat_caller_address(project_address, minter_address);
    let share: u256 = 10 * CC_DECIMALS_MULTIPLIER / 100; // 10%
    buy_utils(owner_address, owner_address, minter_address, share);
    start_cheat_caller_address(erc20_address, user_address);
    buy_utils(owner_address, user_address, minter_address, share);

    start_cheat_caller_address(minter_address, user_address);
    minter.withdraw();
}

#[test]
fn test_retrieve_amount() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    // Deploy erc20 used for the minter, and a second erc20 that isn't used
    let contract = snf::declare("USDCarb").expect('Failed to declare contract');
    let mut calldata: Array<felt252> = array![user_address.into(), user_address.into()];
    let (erc20_address, _) = contract.deploy(@calldata).expect('Failed to deploy contract');
    calldata = array![user_address.into(), user_address.into()];
    let (second_erc20_address, _) = contract.deploy(@calldata).expect('Failed to deploy contract');
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(second_erc20_address, user_address);
    start_cheat_caller_address(minter_address, owner_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let second_er20 = IERC20Dispatcher { contract_address: second_erc20_address };

    // Transfering incorrect token to minter
    second_er20.transfer(minter_address, 1000);
    start_cheat_caller_address(second_erc20_address, minter_address);
    minter.retrieve_amount(second_erc20_address, owner_address, 1000);
    let balance_after = second_er20.balance_of(owner_address);
    assert(balance_after == 1000, 'balance should be the same');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_retrieve_amount_without_owner_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    // Deploy erc20 used for the minter, and a second erc20 that isn't used
    let contract = snf::declare("USDCarb").expect('Failed to declare contract');
    let mut calldata: Array<felt252> = array![user_address.into(), user_address.into()];
    let (erc20_address, _) = contract.deploy(@calldata).expect('Failed to deploy contract');
    calldata = array![user_address.into(), user_address.into()];
    let (second_erc20_address, _) = contract.deploy(@calldata).expect('Failed to deploy contract');
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(second_erc20_address, user_address);
    start_cheat_caller_address(minter_address, owner_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let second_er20 = IERC20Dispatcher { contract_address: second_erc20_address };

    // Transfering incorrect token to minter
    second_er20.transfer(minter_address, 1000);
    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(second_erc20_address, minter_address);
    minter.retrieve_amount(second_erc20_address, user_address, 1000);
}
