use core::option::OptionTrait;
use core::traits::Into;
use core::array::SpanTrait;
// Starknet deps

use starknet::{ContractAddress, contract_address_const};

// External deps

use openzeppelin::tests::utils::constants as c;
use openzeppelin::utils::serde::SerializedAppend;
use snforge_std as snf;
use snforge_std::{CheatTarget, ContractClassTrait, EventSpy, SpyOn, start_prank, stop_prank};
use alexandria_storage::list::{List, ListTrait};

// Components

use carbon_v3::components::absorber::interface::{
    IAbsorber, IAbsorberDispatcher, IAbsorberDispatcherTrait, ICarbonCreditsHandler,
    ICarbonCreditsHandlerDispatcher, ICarbonCreditsHandlerDispatcherTrait
};
use carbon_v3::components::minter::interface::{IMint, IMintDispatcher, IMintDispatcherTrait};

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};

/// Deploys a project contract.
fn deploy_project() -> (ContractAddress, EventSpy) {
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

#[test]
fn test_constructor_ok() {
    let (_project_address, _spy) = deploy_project();
}

#[test]
fn test_is_setup() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };

    setup_project(
        project_address,
        1573000000,
        array![1706785200, 2306401200].span(),
        array![0, 1573000000].span(),
    );

    assert(project.is_setup(), 'Error during setup');
}

#[test]
fn test_project_batch_mint() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = deploy_project();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

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

    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let decimal: u8 = project_contract.decimals();
    assert(decimal == 6, 'Error of decimal');

    let share: u256 = 125000;
    let cc_distribution: Span<u256> = absorber.compute_carbon_vintage_distribution(share);
    let cc_years_vintages: Span<u256> = carbon_credits.get_years_vintage();
    project_contract.batch_mint(owner_address, cc_years_vintages, cc_distribution);
}
