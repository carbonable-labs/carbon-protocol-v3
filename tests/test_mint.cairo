use core::array::SpanTrait;
// Core deps

use array::ArrayTrait;
use result::ResultTrait;
use option::OptionTrait;
use traits::{Into, TryInto};
use zeroable::Zeroable;
use debug::PrintTrait;
use hash::HashStateTrait;
use pedersen::PedersenTrait;

// Starknet deps

use starknet::{ContractAddress, contract_address_const};
use starknet::{deploy_syscall, get_block_timestamp};
use starknet::testing::{set_caller_address, set_contract_address};

// External deps

use openzeppelin::tests::utils::constants as c;
use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use snforge_std as snf;
use snforge_std::{
    CheatTarget, ContractClassTrait, test_address, spy_events, EventSpy, SpyOn, EventAssertions,
    start_warp, start_prank, stop_prank
};
use alexandria_storage::list::{List, ListTrait};

// Components

use carbon_v3::components::absorber::interface::{
    IAbsorberDispatcher, IAbsorberDispatcherTrait, ICarbonCreditsHandlerDispatcher,
    ICarbonCreditsHandlerDispatcherTrait
};
use carbon_v3::components::absorber::carbon_handler::AbsorberComponent::{
    Event, AbsorptionUpdate, ProjectValueUpdate
};
use carbon_v3::data::carbon_vintage::{CarbonVintage, CarbonVintageType};
use carbon_v3::components::absorber::carbon_handler::AbsorberComponent;

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
    get_mock_times, get_mock_absorptions, equals_with_error, deploy_project, setup_project,
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
    // [Assert] project_carbon set correctly
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
    start_prank(CheatTarget::One(minter_address), owner_address);

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
    // [Prank] Use owner as caller to Project contract
    start_prank(CheatTarget::One(project_address), owner_address);
    let project = IProjectDispatcher { contract_address: project_address };
    // [Effect] Grant Minter role to Minter contract
    project.grant_minter_role(minter_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();

    setup_project(project_address, 8000000000, times, absorptions,);
    // [Prank] Stop prank on Project contract
    stop_prank(CheatTarget::One(project_address));

    let minter = IMintDispatcher { contract_address: minter_address };
    // [Assert] project_carbon set correctly
    let sale_open = minter.is_public_sale_open();
    assert(sale_open == true, 'public sale not open');

    /// [Check] remaining money to buy in Minter 
    let max_value: u256 = 8000000000;
    let remaining_money = minter.get_available_money_amount();
    assert(remaining_money == max_value, 'remaining money wrong value');

    /// [Approval] approve the minter to spend the money
    let amount_to_buy: u256 = 1000000000;
    // approve the minter to spend the money
    start_prank(CheatTarget::One(erc20_address), owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.transfer(user_address, amount_to_buy);

    start_prank(CheatTarget::One(erc20_address), user_address);
    erc20.approve(minter_address, amount_to_buy);
    // [Prank] Use user as caller to Minter and ERC20 contracts
    start_prank(CheatTarget::One(minter_address), user_address);
    start_prank(CheatTarget::One(erc20_address), minter_address);

    let tokenized_cc: Span<u256> = minter.public_buy(amount_to_buy, false);
    assert(tokenized_cc.len() == 20, 'cc should have 20 element');
}

// get_available_money_amount

#[test]
fn test_get_available_money_amount() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);
    // [Prank] Use owner as caller to Project and Minter contracts
    start_prank(CheatTarget::One(project_address), owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    // [Effect] Grant Minter role to Minter contract
    project_contract.grant_minter_role(minter_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);
    // [Prank] Stop prank on Project contract
    stop_prank(CheatTarget::One(project_address));

    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the public sale is open
    let sale_open = minter.is_public_sale_open();
    assert(sale_open == true, 'public sale not open');

    // Default initial amount of money = 8000000000
    let initial_money: u256 = 8000000000;

    // Verify if the initial value is correct
    let remaining_money = minter.get_available_money_amount();
    assert(remaining_money == initial_money, 'remaining money wrong value');

    let amount_to_buy: u256 = 1000;

    // Approve the minter to spend the money and execute a public buy
    start_prank(CheatTarget::One(erc20_address), owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.transfer(user_address, amount_to_buy);

    start_prank(CheatTarget::One(erc20_address), user_address);
    erc20.approve(minter_address, amount_to_buy);
    // [Prank] Use user as caller to Minter contract and Minter as caller to ERC20 contract
    start_prank(CheatTarget::One(minter_address), user_address);
    start_prank(CheatTarget::One(erc20_address), minter_address);

    minter.public_buy(amount_to_buy, false);
    stop_prank(CheatTarget::One(minter_address));
    stop_prank(CheatTarget::One(erc20_address));

    // Test after the buy
    let remaining_money_after_buy = minter.get_available_money_amount();
    assert(
        remaining_money_after_buy == initial_money - amount_to_buy, 'remaining money wrong value'
    );

    // Buy all the remaining money
    let remaining_money_to_buy = remaining_money_after_buy;
    start_prank(CheatTarget::One(erc20_address), owner_address);
    erc20.transfer(user_address, remaining_money_to_buy);

    start_prank(CheatTarget::One(erc20_address), user_address);
    erc20.approve(minter_address, remaining_money_to_buy);
    // [Prank] Use user as caller to Minter contract and Minter as caller to ERC20 contract
    start_prank(CheatTarget::One(minter_address), user_address);
    start_prank(CheatTarget::One(erc20_address), minter_address);
    minter.public_buy(remaining_money_to_buy, false);

    // Test after buying all the remaining money
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

    // [Prank] Use owner as caller to Minter contract
    start_prank(CheatTarget::One(minter_address), owner_address);

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

    // [Prank] Use owner as caller to Minter contract
    start_prank(CheatTarget::One(minter_address), owner_address);

    let minter = IMintDispatcher { contract_address: minter_address };

    let price: u256 = 100;

    minter.set_unit_price(price);
}

#[test]
fn test_get_max_money_amount() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);
    // [Prank] Use owner as caller to Project and Minter contracts
    start_prank(CheatTarget::One(project_address), owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    // [Effect] Grant Minter role to Minter contract
    project_contract.grant_minter_role(minter_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);
    // [Prank] Stop prank on Project contract
    stop_prank(CheatTarget::One(project_address));

    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the public sale is open
    let sale_open = minter.is_public_sale_open();
    assert(sale_open == true, 'public sale not open');

    // Default initial max amount of money = 8000000000
    let initial_max_money: u256 = 8000000000;

    // Verify if the initial max value is correct
    let max_money = minter.get_max_money_amount();
    assert(max_money == initial_max_money, 'max money amount is incorrect');

    let amount_to_buy: u256 = 1000;

    // Approve the minter to spend the money and execute a public buy
    start_prank(CheatTarget::One(erc20_address), owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.transfer(user_address, amount_to_buy);

    start_prank(CheatTarget::One(erc20_address), user_address);
    erc20.approve(minter_address, amount_to_buy);
    // [Prank] Use user as caller to Minter contract and Minter as caller to ERC20 contract
    start_prank(CheatTarget::One(minter_address), user_address);
    start_prank(CheatTarget::One(erc20_address), minter_address);

    minter.public_buy(amount_to_buy, false);
    stop_prank(CheatTarget::One(minter_address));
    stop_prank(CheatTarget::One(erc20_address));

    // Test after the buy
    let remaining_money_after_buy = minter.get_available_money_amount();
    let current_max_money = initial_max_money - amount_to_buy;
    assert(remaining_money_after_buy == current_max_money, 'remaining money is incorrect');

    // Buy all the remaining money
    let remaining_money_to_buy = remaining_money_after_buy;
    start_prank(CheatTarget::One(erc20_address), owner_address);
    erc20.transfer(user_address, remaining_money_to_buy);

    start_prank(CheatTarget::One(erc20_address), user_address);
    erc20.approve(minter_address, remaining_money_to_buy);
    // [Prank] Use user as caller to Minter contract and Minter as caller to ERC20 contract
    start_prank(CheatTarget::One(minter_address), user_address);
    start_prank(CheatTarget::One(erc20_address), minter_address);
    minter.public_buy(remaining_money_to_buy, false);

    // Test after buying all the remaining money
    let remaining_money_after_buying_all = minter.get_available_money_amount();
    assert(remaining_money_after_buying_all == 0, 'remaining money is incorrect');

    // Verify the max money amount remains unchanged
    let max_money_after_buying_all = minter.get_max_money_amount();
    assert(max_money_after_buying_all == initial_max_money, 'max money is incorrect');
}

#[test]
fn test_get_min_money_amount_per_tx() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);
    // [Prank] Use owner as caller to Project and Minter contracts
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(minter_address), user_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    // [Effect] Grant Minter role to Minter contract
    project_contract.grant_minter_role(minter_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);
    // [Prank] Stop prank on Project contract
    stop_prank(CheatTarget::One(project_address));

    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the public sale is open
    let sale_open = minter.is_public_sale_open();
    assert(sale_open == true, 'public sale not open');

    // Default initial min amount of money per transaction = 0
    let initial_min_money_per_tx: u256 = 0;

    // Verify if the initial min value is correct
    let min_money_per_tx = minter.get_min_money_amount_per_tx();
    assert!(min_money_per_tx == initial_min_money_per_tx, "initial min money per tx is incorrect");

    let amount_to_buy: u256 = 1000;

    // Approve the minter to spend the money and execute a public buy
    start_prank(CheatTarget::One(erc20_address), owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.transfer(user_address, amount_to_buy);

    start_prank(CheatTarget::One(erc20_address), user_address);
    erc20.approve(minter_address, amount_to_buy);

    // [Prank] Use user as caller to Minter contract
    start_prank(CheatTarget::One(minter_address), user_address);
    start_prank(CheatTarget::One(erc20_address), minter_address);

    minter.public_buy(amount_to_buy, false);

    // Test after the buy
    let remaining_money_after_buy = minter.get_available_money_amount();
    assert(remaining_money_after_buy == 8000000000 - amount_to_buy, 'remaining money is incorrect');

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
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);
    // [Prank] Use owner as caller to Project contract
    start_prank(CheatTarget::One(project_address), owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    // [Effect] Grant Minter role to Minter contract
    project_contract.grant_minter_role(minter_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);
    // [Prank] Stop prank on Project contract
    stop_prank(CheatTarget::One(project_address));

    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the public sale is open
    let sale_open = minter.is_public_sale_open();
    assert(sale_open == true, 'public sale not open');

    // Verify that the contract is not sold out initially
    let is_sold_out_initial = minter.is_sold_out();
    assert(!is_sold_out_initial, 'should not be sold out');

    // Default initial amount of money = 8000000000
    let initial_money: u256 = 8000000000;

    // Buy all the remaining money
    start_prank(CheatTarget::One(erc20_address), owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.transfer(user_address, initial_money);

    start_prank(CheatTarget::One(erc20_address), user_address);
    erc20.approve(minter_address, initial_money);

    // [Prank] Use user as caller to Minter contract
    start_prank(CheatTarget::One(minter_address), user_address);
    start_prank(CheatTarget::One(erc20_address), minter_address);
    minter.public_buy(initial_money, false);

    // Test after buying all the remaining money
    let remaining_money_after_buying_all = minter.get_available_money_amount();
    assert(remaining_money_after_buying_all == 0, 'remaining money wrong');

    // Verify that the contract is sold out after buying all the money
    let is_sold_out_after = minter.is_sold_out();
    assert(is_sold_out_after, 'should be sold out');
}

#[test]
fn test_set_min_money_amount_per_tx() {
    // Deploy required contracts
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);
    // [Prank] Use owner as caller to Project and Minter contracts
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    // [Effect] Grant Minter role to Minter contract
    project_contract.grant_minter_role(minter_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    // Start testing environment setup
    // [Prank] Use owner as caller to ERC20 contract
    start_prank(CheatTarget::One(erc20_address), owner_address);

    let minter = IMintDispatcher { contract_address: minter_address };

    // Verify that the min money amount per tx is 0 at the beginning
    let min_money_amount_per_tx = minter.get_min_money_amount_per_tx();
    assert(min_money_amount_per_tx == 0, 'Initial min per tx incorrect');

    // Test: setting a new valid min money amount per tx
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
#[should_panic]
fn test_set_min_money_amount_per_tx_panic() {
    // Deploy required contracts
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);
    // [Prank] Use owner as caller to Project and Minter contracts
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    // [Effect] Grant Minter role to Minter contract
    project_contract.grant_minter_role(minter_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    // Start testing environment setup
    // [Prank] Use owner as caller to ERC20 contract
    start_prank(CheatTarget::One(erc20_address), owner_address);

    let minter = IMintDispatcher { contract_address: minter_address };

    // Verify that the min money amount per tx was set correctly
    let min_money_amount_per_tx = minter.get_min_money_amount_per_tx();
    assert(min_money_amount_per_tx == 0, 'Initial min per tx incorrect');

    // Test: setting a new invalid min money amount per tx (should panic)
    let new_min_money_amount: u256 = 9999999999;
    minter.set_min_money_amount_per_tx(new_min_money_amount);
}

// get_carbonable_project_address

#[test]
fn test_get_carbonable_project_address() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    start_prank(CheatTarget::One(minter_address), user_address);

    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the carbonable project address is correct
    let carbonable_project_address = minter.get_carbonable_project_address();
    assert(carbonable_project_address == project_address, 'address does not match');
}

// get_payment_token_address

#[test]
fn test_get_payment_token_address() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    start_prank(CheatTarget::One(minter_address), user_address);

    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the payment token address is correct
    let payment_token_address = minter.get_payment_token_address();
    assert(payment_token_address == erc20_address, 'address does not match');
}

// set_unit_price

#[test]
fn test_set_unit_price() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    // Start testing environment setup
    start_prank(CheatTarget::One(erc20_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);

    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the unit price is not set initially
    let unit_price = minter.get_unit_price();
    assert(unit_price == 11, 'unit price should be 11');

    // Set the unit price
    let new_unit_price: u256 = 1000;
    start_prank(CheatTarget::One(minter_address), owner_address);
    minter.set_unit_price(new_unit_price);
    stop_prank(CheatTarget::One(minter_address));

    // Verify that the unit price is set correctly
    let unit_price_after = minter.get_unit_price();
    assert(unit_price_after == new_unit_price, 'unit price wrong value');

    // Set the unit price to a large value
    let new_unit_price_large: u256 = 1000000000;
    start_prank(CheatTarget::One(minter_address), owner_address);
    minter.set_unit_price(new_unit_price_large);
    stop_prank(CheatTarget::One(minter_address));

    // Verify that the unit price is set correctly
    let unit_price_after_large = minter.get_unit_price();
    assert(unit_price_after_large == new_unit_price_large, 'unit price wrong value');
}

// get_unit_price

#[test]
fn test_get_unit_price() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    // Start testing environment setup
    start_prank(CheatTarget::One(minter_address), user_address);

    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the unit price is not set initially
    let unit_price = minter.get_unit_price();
    assert(unit_price == 11, 'unit price should be 11');
    stop_prank(CheatTarget::One(minter_address));

    // Set the unit price
    start_prank(CheatTarget::One(minter_address), owner_address);
    let new_unit_price: u256 = 1000;
    start_prank(CheatTarget::One(minter_address), owner_address);
    minter.set_unit_price(new_unit_price);
    stop_prank(CheatTarget::One(minter_address));

    // Verify that the unit price is set correctly
    start_prank(CheatTarget::One(minter_address), user_address);
    let unit_price_after = minter.get_unit_price();
    assert(unit_price_after == new_unit_price, 'unit price wrong value');
}

// set_unit_price_to_zero_panic

#[test]
#[should_panic]
fn test_set_unit_price_to_zero_panic() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    // Start testing environment setup
    start_prank(CheatTarget::One(erc20_address), owner_address);

    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

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

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    start_prank(CheatTarget::One(erc20_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    let minter = IMintDispatcher { contract_address: minter_address };
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    start_prank(CheatTarget::One(project_address), owner_address);
    project.grant_minter_role(minter_address);

    start_prank(CheatTarget::One(project_address), minter_address);
    let share: u256 = 10 * CC_DECIMALS_MULTIPLIER / 100; // 10%
    buy_utils(owner_address, owner_address, minter_address, share);
    start_prank(CheatTarget::One(erc20_address), user_address);
    buy_utils(owner_address, user_address, minter_address, share);

    let balance_owner_before_withdraw = erc20.balance_of(owner_address);

    let balance_to_withdraw = erc20.balance_of(minter_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
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

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    start_prank(CheatTarget::One(erc20_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    let minter = IMintDispatcher { contract_address: minter_address };
    start_prank(CheatTarget::One(project_address), owner_address);
    project.grant_minter_role(minter_address);

    start_prank(CheatTarget::One(project_address), minter_address);
    let share: u256 = 10 * CC_DECIMALS_MULTIPLIER / 100; // 10%
    buy_utils(owner_address, owner_address, minter_address, share);
    start_prank(CheatTarget::One(erc20_address), user_address);
    buy_utils(owner_address, user_address, minter_address, share);

    minter.withdraw();
}

#[test]
fn test_retrieve_amount() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = deploy_project();
    // Deploy erc20 used for the minter, and a second erc20 that isn't used
    let contract = snf::declare('USDCarb');
    let mut calldata: Array<felt252> = array![user_address.into(), user_address.into()];
    let erc20_address = contract.deploy(@calldata).unwrap();
    calldata = array![user_address.into(), user_address.into()];
    let second_erc20_address = contract.deploy(@calldata).unwrap();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    start_prank(CheatTarget::One(second_erc20_address), user_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let second_er20 = IERC20Dispatcher { contract_address: second_erc20_address };

    // Transfering incorrect token to minter
    second_er20.transfer(minter_address, 1000);
    start_prank(CheatTarget::One(second_erc20_address), minter_address);
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
    let contract = snf::declare('USDCarb');
    let mut calldata: Array<felt252> = array![user_address.into(), user_address.into()];
    let erc20_address = contract.deploy(@calldata).unwrap();
    calldata = array![user_address.into(), user_address.into()];
    let second_erc20_address = contract.deploy(@calldata).unwrap();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    // Setup the project with initial values
    setup_project(project_address, 8000000000, times, absorptions,);

    start_prank(CheatTarget::One(second_erc20_address), user_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let second_er20 = IERC20Dispatcher { contract_address: second_erc20_address };

    // Transfering incorrect token to minter
    second_er20.transfer(minter_address, 1000);
    start_prank(CheatTarget::One(minter_address), user_address);
    start_prank(CheatTarget::One(second_erc20_address), minter_address);
    minter.retrieve_amount(second_erc20_address, user_address, 1000);
}
