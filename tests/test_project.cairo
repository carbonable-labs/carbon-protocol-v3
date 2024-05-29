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

// Data 

use carbon_v3::data::carbon_vintage::{CarbonVintage, CarbonVintageType};

// Components

use carbon_v3::components::absorber::interface::{
    IAbsorber, IAbsorberDispatcher, IAbsorberDispatcherTrait, ICarbonCreditsHandler,
    ICarbonCreditsHandlerDispatcher, ICarbonCreditsHandlerDispatcherTrait
};
use carbon_v3::components::absorber::carbon_handler::AbsorberComponent::MULT_ACCURATE_SHARE;
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

fn default_setup() -> (ContractAddress, EventSpy) {
    let (project_address, spy) = deploy_project();

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
        10000000,
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

    (project_address, spy)
}

/// Mint shares without the minter contract. Testing purposes only.
fn mint_utils(project_address: ContractAddress, owner_address: ContractAddress, share: u256) {
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let cc_vintage_years: Span<u256> = cc_handler.get_vintage_years();
    let n = cc_vintage_years.len();

    let mut cc_shares: Array<u256> = ArrayTrait::<u256>::new();
    let mut index = 0;
    loop {
        if index == n {
            break;
        }
        cc_shares.append(share);
        index += 1;
    };
    let cc_shares = cc_shares.span();

    let project = IProjectDispatcher { contract_address: project_address };
    project.batch_mint(owner_address, cc_vintage_years, cc_shares);
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
    let (project_address, _) = default_setup();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let decimal: u8 = project_contract.decimals();
    assert(decimal == 6, 'Error of decimal');

    let share: u256 = 125000;
    let cc_distribution: Span<u256> = absorber.compute_carbon_vintage_distribution(share);
    let cc_vintage_years: Span<u256> = carbon_credits.get_vintage_years();
    project_contract.batch_mint(owner_address, cc_vintage_years, cc_distribution);
}

#[test]
fn test_project_set_vintage_status() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    carbon_credits.update_vintage_status(2025, 2);
    let vinatge: CarbonVintage = carbon_credits.get_carbon_vintage(2025);
    assert(vinatge.status == CarbonVintageType::Audited, 'Error of status');
}

/// Test balance_of
#[test]
fn test_project_balance_of() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    let share = 33 * MULT_ACCURATE_SHARE / 100;
    mint_utils(project_address, owner_address, share);

    let supply_vintage_2025 = carbon_credits.get_carbon_vintage(2025).supply;
    let expected_balance = 3300000;
    let balance = project_contract.balance_of(owner_address, 2025);
    assert(balance == expected_balance.into(), 'Error of balance');
}

#[test]
fn test_transfer_without_loss() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    let share = 33 * MULT_ACCURATE_SHARE / 100;
    mint_utils(project_address, owner_address, share);

    let expected_balance = 3300000;
    let balance = project_contract.balance_of(owner_address, 2025);
    assert(balance == expected_balance.into(), 'Error of balance');

    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    let receiver_balance = project_contract.balance_of(receiver_address, 2025);
    assert(receiver_balance == 0, 'Error of balance');

    project_contract
        .safe_transfer_from(owner_address, receiver_address, 2025, 3300000.into(), array![].span());

    let balance = project_contract.balance_of(owner_address, 2025);
    assert(balance == 0, 'Error of balance');

    let receiver_balance = project_contract.balance_of(receiver_address, 2025);
    assert(receiver_balance == 3300000.into(), 'Error of balance');
}

#[test]
fn test_transfer_rebase_transfer() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    let share = 33 * MULT_ACCURATE_SHARE / 100;
    mint_utils(project_address, owner_address, share);

    let initial_balance = project_contract.balance_of(owner_address, 2025);
    assert(initial_balance == 3300000.into(), 'Error of balance');

    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    project_contract
        .safe_transfer_from(
            owner_address, receiver_address, 2025, initial_balance.into(), array![].span()
        );
    let balance1 = project_contract.balance_of(owner_address, 2025);
    assert(balance1 == 0, 'Error of balance');
    let balance2 = project_contract.balance_of(receiver_address, 2025);
    assert(balance2 == initial_balance, 'Error of balance');

    let old_vintage_supply = cc_handler.get_vintage_supply(2025);
    absorber.rebase_vintage(2025, old_vintage_supply / 2);
    let balance1 = project_contract.balance_of(owner_address, 2025);
    assert(balance1 == 0, 'Error of balance');
    let balance2 = project_contract.balance_of(receiver_address, 2025);
    assert(balance2 == initial_balance / 2, 'Error of balance');
    start_prank(CheatTarget::One(project_address), receiver_address);
    project_contract
        .safe_transfer_from(
            receiver_address, owner_address, 2025, balance2.into(), array![].span()
        );

    let balance1 = project_contract.balance_of(owner_address, 2025);
    assert(balance1 == initial_balance / 2, 'Error of balance');

    absorber.rebase_vintage(2025, old_vintage_supply);
    let balance1 = project_contract.balance_of(owner_address, 2025);
    assert(balance1 == initial_balance, 'Error of balance');
}
