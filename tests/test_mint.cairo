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

use starknet::ContractAddress;
use starknet::{deploy_syscall, get_block_timestamp};
use starknet::testing::{set_caller_address, set_contract_address};

// External deps

use openzeppelin::tests::utils::constants as c;
use openzeppelin::utils::serde::SerializedAppend;
use snforge_std as snf;
use snforge_std::{
    CheatTarget, ContractClassTrait, test_address, spy_events, EventSpy, SpyOn, EventAssertions,
    start_warp
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

use carbon_v3::components::minter::interface::{
    IMintDispatcher, IMintDispatcherTrait
};

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
fn deploy_project(owner: felt252) -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Project');
    let uri = 'uri';
    let starting_year: u64 = 2024;
    let number_of_years: u64 = 20;
    let mut calldata: Array<felt252> = array![];
    calldata.append(uri);
    calldata.append(c::OWNER().into());
    calldata.append(starting_year.into());
    calldata.append(number_of_years.into());
    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

/// Deploy erc20 contract.
fn deploy_erc20(owner: felt252) -> (ContractAddress, EventSpy) {
    let contract = snf::declare('USDCarb');
    let mut calldata: Array<felt252> = array![];
    calldata.append(c::OWNER().into());
    calldata.append(c::OWNER().into());
    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

/// Deploys a minter contract.
fn deploy_minter(owner: felt252, project_address: ContractAddress, payment_address: ContractAddress) -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Minter');
    let public_sale: bool = true;
    let max_value: felt252 = 1573000000;
    let unit_price: felt252 = 11;
    let mut calldata: Array<felt252> = array![];
    calldata.append(project_address.into());
    calldata.append(payment_address.into());
    calldata.append(public_sale.into());
    calldata.append(max_value);
    calldata.append(0);
    calldata.append(unit_price);
    calldata.append(0);
    calldata.append(c::OWNER().into());
    
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
    let (project_address, mut spy) = deploy_project(c::OWNER().into());
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
    let (project_address, _) = deploy_project(c::OWNER().into());
    let (erc20_address, _) = deploy_erc20(c::OWNER().into());
    let (minter_address, _) = deploy_minter(c::OWNER().into(), project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    // [Assert] project_carbon set correctly
    let sale_open = minter.is_public_sale_open();
    assert(sale_open == true, 'public sale not open');
}