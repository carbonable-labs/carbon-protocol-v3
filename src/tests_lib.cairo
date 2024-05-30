use core::option::OptionTrait;
use core::traits::Into;
use core::array::SpanTrait;
// Starknet deps

use starknet::{ContractAddress, contract_address_const};

// External deps

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
use carbon_v3::components::absorber::carbon_handler::AbsorberComponent::CC_DECIMALS_MULTIPLIER;
use carbon_v3::components::minter::interface::{IMint, IMintDispatcher, IMintDispatcherTrait};

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};


///
/// Mock Data
///

fn get_mock_times() -> Span<u64> {
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
    times
}

fn get_mock_absorptions() -> Span<u64> {
    let absorptions: Span<u64> = array![
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
    absorptions
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

fn deploy_project() -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Project');
    let uri = 'uri';
    let starting_year: u64 = 2024;
    let number_of_years: u64 = 20;
    let mut calldata: Array<felt252> = array![];
    calldata.append(uri);
    calldata.append(contract_address_const::<'OWNER'>().into());
    calldata.append(starting_year.into());
    calldata.append(number_of_years.into());
    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

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

fn default_setup_and_deploy() -> (ContractAddress, EventSpy) {
    let (project_address, spy) = deploy_project();
    let times: Span<u64> = get_mock_times();
    let absorptions: Span<u64> = get_mock_absorptions();
    setup_project(project_address, 8000000000, times, absorptions,);
    (project_address, spy)
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

fn fuzzing_setup(cc_supply: u64) -> (ContractAddress, EventSpy) {
    let (project_address, spy) = deploy_project();

    let times: Span<u64> = get_mock_times();
    // Tests are done on a single vintage, thus the absorptions are the same
    let absorptions: Span<u64> = array![
        0,
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

///
/// Tests functions to be called by the test runner
/// 

fn perform_fuzzed_transfer(
    raw_supply: u64,
    raw_share: u256,
    raw_last_digits_share: u256,
    percentage_of_balance_to_send: u256,
    max_supply_for_vintage: u64
) {
    let supply = raw_supply % max_supply_for_vintage;
    if raw_share == 0 || supply == 0 {
        return;
    }
    let last_digits_share = raw_last_digits_share % 100;
    let share_modulo = raw_share % CC_DECIMALS_MULTIPLIER;
    let share = share_modulo * 100 + last_digits_share;

    if share == 0 {
        return;
    }

    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    let (project_address, _) = fuzzing_setup(supply);
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };
    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    mint_utils(project_address, owner_address, share);

    let initial_balance = project_contract.balance_of(owner_address, 2025);
    let amount = percentage_of_balance_to_send * initial_balance / 10_000;
    project_contract
        .safe_transfer_from(owner_address, receiver_address, 2025, amount.into(), array![].span());

    let balance_owner = project_contract.balance_of(owner_address, 2025);
    assert(
        equals_with_error(balance_owner, initial_balance - amount, 100), 'Error balance owner 1'
    );
    let balance_receiver = project_contract.balance_of(receiver_address, 2025);
    assert(equals_with_error(balance_receiver, amount, 100), 'Error balance receiver 1');

    start_prank(CheatTarget::One(project_address), receiver_address);
    project_contract
        .safe_transfer_from(receiver_address, owner_address, 2025, amount.into(), array![].span());

    let balance_owner = project_contract.balance_of(owner_address, 2025);
    assert(equals_with_error(balance_owner, initial_balance, 100), 'Error balance owner 2');
    let balance_receiver = project_contract.balance_of(receiver_address, 2025);
    assert(equals_with_error(balance_receiver, 0, 100), 'Error balance receiver 2');
}
