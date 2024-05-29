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
    Event, AbsorptionUpdate, ProjectValueUpdate, CC_DECIMALS_MULTIPLIER
};
use carbon_v3::data::carbon_vintage::{CarbonVintage, CarbonVintageType};
use carbon_v3::components::absorber::carbon_handler::AbsorberComponent;

use carbon_v3::components::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};

use carbon_v3::components::burner::interface::{IBurnHandlerDispatcher, IBurnHandlerDispatcherTrait};

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

/// Deploys a minter contract.
fn deploy_burner(
    owner: ContractAddress, project_address: ContractAddress
) -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Burner');
    let mut calldata: Array<felt252> = array![];
    calldata.append(project_address.into());
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

fn default_setup(owner: ContractAddress) -> (ContractAddress, EventSpy) {
    let (project_address, spy) = deploy_project(owner);

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

    (project_address, spy)
}

/// Mint shares without the minter contract. Testing purposes only.
fn mint_utils(project_address: ContractAddress, owner_address: ContractAddress, share: u256) {
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let cc_years_vintages: Span<u256> = cc_handler.get_years_vintage();
    let n = cc_years_vintages.len();

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
    project.batch_mint(owner_address, cc_years_vintages, cc_shares);
}

//
// Tests
//

#[test]
fn test_burner_init() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup(owner_address);
    let (burner_address, _) = deploy_burner(owner_address, project_address);

    let burner = IBurnHandlerDispatcher { contract_address: burner_address };

    // [Assert] cointract is empty
    start_prank(CheatTarget::One(burner_address), owner_address);
    let carbon_pending = burner.get_carbon_retired(2025);
    assert(carbon_pending == 0, 'carbon pending should be 0');

    let carbon_retired = burner.get_carbon_retired(2025);
    assert(carbon_retired == 0, 'carbon retired should be 0');
}

// Nominal cases

#[test]
fn test_burner_retirement() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup(owner_address);
    let (burner_address, _) = deploy_burner(owner_address, project_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(burner_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    assert(absorber.is_setup(), 'Error during setup');
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let decimal: u8 = project_contract.decimals();
    assert(decimal == 6, 'Error of decimal');

    let share: u256 = 10*CC_DECIMALS_MULTIPLIER; // 10%
    mint_utils(project_address, owner_address, share);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());

    // [Effect] try to retire carbon credits
    let burner = IBurnHandlerDispatcher { contract_address: burner_address };
    burner.retire_carbon_credits(2025, 100000);

    let carbon_retired = burner.get_carbon_retired(2025);
    assert(carbon_retired == 100000, 'Carbon retired is wrong');
}

// Error cases

#[test]
#[should_panic(expected: ('Not own enough carbon credits',))]
fn test_burner_not_enough_CC() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup(owner_address);
    let (burner_address, _) = deploy_burner(owner_address, project_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(burner_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    assert(absorber.is_setup(), 'Error during setup');
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let decimal: u8 = project_contract.decimals();
    assert(decimal == 6, 'Error of decimal');

    let share = 33 * CC_DECIMALS_MULTIPLIER;    
    mint_utils(project_address, owner_address, share);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());

    // [Effect] try to retire carbon credits
    let burner = IBurnHandlerDispatcher { contract_address: burner_address };
    let balance_owner = project_contract.balance_of(owner_address, 2025);
    burner.retire_carbon_credits(2025, balance_owner + 1);
}

#[test]
#[should_panic(expected: ('Vintage status is not audited',))]
fn test_burner_wrong_status() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup(owner_address);
    let (burner_address, _) = deploy_burner(owner_address, project_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(burner_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let absorber = IAbsorberDispatcher { contract_address: project_address };

    assert(absorber.is_setup(), 'Error during setup');
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let decimal: u8 = project_contract.decimals();
    assert(decimal == 6, 'Error of decimal');

    let share = 33 * CC_DECIMALS_MULTIPLIER;    
    mint_utils(project_address, owner_address, share);

    // [Effect] try to retire carbon credits
    let burner = IBurnHandlerDispatcher { contract_address: burner_address };
    burner.retire_carbon_credits(2025, 1000000);
}
