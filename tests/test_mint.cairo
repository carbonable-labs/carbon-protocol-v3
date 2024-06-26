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
    default_setup_and_deploy, deploy_offsetter, deploy_erc20, deploy_minter
};

// Constants

const PROJECT_CARBON: u256 = 42;

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

// set_project_carbon

#[test]
fn test_set_project_carbon() {
    let (project_address, mut spy) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] project_carbon set correctly
    project.set_project_carbon(PROJECT_CARBON.into());
    let fetched_value = project.get_project_carbon();
    assert(fetched_value == PROJECT_CARBON.into(), 'project_carbon wrong value');
    spy
        .assert_emitted(
            @array![
                (
                    project_address,
                    AbsorberComponent::Event::ProjectValueUpdate(
                        AbsorberComponent::ProjectValueUpdate { value: PROJECT_CARBON.into() }
                    )
                )
            ]
        );
    // found events are removed from the spy after assertion, so the length should be 0
    assert(spy.events.len() == 0, 'number of events should be 0');
}


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

// is_public_buy

#[test]
fn test_is_public_buy() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();

    setup_project(project_address, 8000000000, times, absorptions,);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);
    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

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

    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.approve(minter_address, amount_to_buy);

    let tokenized_cc: Span<u256> = minter.public_buy(amount_to_buy, false);
    assert(tokenized_cc.len() == 20, 'cc should have 20 element');
}

// get_available_money_amount

#[test]
fn test_get_available_money_amount() {
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
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.approve(minter_address, amount_to_buy);
    minter.public_buy(amount_to_buy, false);

    // Test after the buy
    let remaining_money_after_buy = minter.get_available_money_amount();
    assert(
        remaining_money_after_buy == initial_money - amount_to_buy, 'remaining money wrong value'
    );

    // Buy all the remaining money
    let remaining_money_to_buy = remaining_money_after_buy;
    erc20.approve(minter_address, remaining_money_to_buy);
    minter.public_buy(remaining_money_to_buy, false);

    // Test after buying all the remaining money
    let remaining_money_after_buying_all = minter.get_available_money_amount();
    assert(remaining_money_after_buying_all == 0, 'remaining money wrong value');
}

// cancel_mint

#[test]
fn test_cancel_mint() {
    let (project_address, _) = deploy_project();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };

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

// get_carbonable_project_address

#[test]
fn test_get_carbonable_project_address() {
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

    // Ensure the carbonable project address is correct
    let carbonable_project_address = minter.get_carbonable_project_address();
    assert(carbonable_project_address == project_address, 'address does not match');
}

// get_payment_token_address

#[test]
fn test_get_payment_token_address() {
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

    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.is_setup(), 'Error during setup');

    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the unit price is not set initially
    let unit_price = minter.get_unit_price();
    assert(unit_price == 11, 'unit price should be 11');

    // Set the unit price
    let new_unit_price: u256 = 1000;
    minter.set_unit_price(new_unit_price);

    // Verify that the unit price is set correctly
    let unit_price_after = minter.get_unit_price();
    assert(unit_price_after == new_unit_price, 'unit price wrong value');

    // Set the unit price to a large value
    let new_unit_price_large: u256 = 1000000000;
    minter.set_unit_price(new_unit_price_large);

    // Verify that the unit price is set correctly
    let unit_price_after_large = minter.get_unit_price();
    assert(unit_price_after_large == new_unit_price_large, 'unit price wrong value');
    
}

// get_unit_price

#[test]
fn test_get_unit_price() {
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

    // Set the unit price
    let new_unit_price: u256 = 1000;
    minter.set_unit_price(new_unit_price);

    // Verify that the unit price is set correctly
    let unit_price_after = minter.get_unit_price();
    assert(unit_price_after == new_unit_price, 'unit price wrong value');
    
}
