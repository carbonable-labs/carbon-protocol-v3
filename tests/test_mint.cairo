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
use carbon_v3::components::data::carbon_vintage::{CarbonVintage, CarbonVintageType};
use carbon_v3::components::absorber::carbon_handler::AbsorberComponent;

use carbon_v3::components::minter::interface::{IMintDispatcher, IMintDispatcherTrait};

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};

use carbon_v3::contracts::minter::Minter;

use carbon_v3::mock::usdcarb::USDCarb;

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
// Setup
//

/// Deploys a project contract.
fn deploy_project(owner: ContractAddress) -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Project');
    let uri = 'uri';
    let starting_year: u64 = 2024;
    let number_of_years: u64 = 20;
    let mut calldata: Array<felt252> = array![];
    calldata.append(uri);
    calldata.append(owner.into());
    calldata.append(starting_year.into());
    calldata.append(number_of_years.into());
    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

/// Deploy erc20 contract.
fn deploy_erc20(owner: ContractAddress) -> (ContractAddress, EventSpy) {
    let contract = snf::declare('USDCarb');
    let mut calldata: Array<felt252> = array![];
    calldata.append(owner.into());
    calldata.append(owner.into());
    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

/// Deploys a minter contract.
fn deploy_minter(
    owner: ContractAddress, project_address: ContractAddress, payment_address: ContractAddress
) -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Minter');
    let public_sale: bool = true;
    let max_value: felt252 = 8000000000;
    let unit_price: felt252 = 11;
    let mut calldata: Array<felt252> = array![];
    calldata.append(project_address.into());
    calldata.append(payment_address.into());
    calldata.append(public_sale.into());
    calldata.append(max_value);
    calldata.append(0);
    calldata.append(unit_price);
    calldata.append(0);
    calldata.append(owner.into());

    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

/// Sets up the project contract.
fn setup_project(
    contract_address: ContractAddress,
    project_carbon: u256,
    times: Span<u64>,
    absorptions: Span<u64>
) {
    let project = IAbsorberDispatcher { contract_address };

    project.set_absorptions(times, absorptions);
    project.set_project_carbon(project_carbon);
}

//
// Tests
//

// set_project_carbon

#[test]
fn test_set_project_carbon() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, mut spy) = deploy_project(owner_address);
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
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = deploy_project(owner_address);
    let (erc20_address, _) = deploy_erc20(owner_address);
    let (minter_address, _) = deploy_minter(owner_address, project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    // [Assert] project_carbon set correctly
    let sale_open = minter.is_public_sale_open();
    assert(sale_open == true, 'public sale not open');
}

#[test]
fn test_is_public_buy() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = deploy_project(owner_address);
    let (erc20_address, _) = deploy_erc20(owner_address);
    let (minter_address, _) = deploy_minter(owner_address, project_address, erc20_address);

    let times: Span<u64> = array![
        1674579600,
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

    let absorptions: Span<u64> = array![
        0,
        29609535,
        47991466,
        88828605,
        118438140,
        370922507,
        623406874,
        875891241,
        1128375608,
        1380859976,
        2076175721,
        2771491466,
        3466807212,
        4162122957,
        4857438703,
        5552754448,
        6248070193,
        6943385939,
        7638701684,
        8000000000
    ]
        .span();

    setup_project(project_address, 8000000000, times, absorptions,);
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

