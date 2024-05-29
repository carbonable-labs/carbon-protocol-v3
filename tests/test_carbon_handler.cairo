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

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
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

//
// Tests
//

// set_project_carbon

#[test]
fn test_set_project_carbon() {
    let (project_address, mut spy) = deploy_project(c::OWNER());
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

#[test]
fn test_get_project_carbon_not_set() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] default project_carbon is 0
    let fetched_value = project.get_project_carbon();
    assert(fetched_value == 0, 'default project_carbon is not 0');
}

#[test]
fn test_set_project_carbon_twice() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] project_carbon set correctly
    project.set_project_carbon(PROJECT_CARBON.into());
    let fetched_value = project.get_project_carbon();
    assert(fetched_value == PROJECT_CARBON.into(), 'project_carbon wrong value');
    // [Assert] project_carbon updated correctly
    let new_value: u256 = 100;
    project.set_project_carbon(new_value.into());
    let fetched_value = project.get_project_carbon();
    assert(fetched_value == new_value, 'project_carbon did not change');
}

// set_absorptions

#[test]
fn test_set_absorptions() {
    let (project_address, mut spy) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![
        1651363200,
        1659312000,
        1667260800,
        1675209600,
        1682899200,
        1690848000,
        1698796800,
        2598134400
    ]
        .span();
    let absorptions: Span<u64> = array![
        0, 1179750, 2359500, 3539250, 4719000, 6685250, 8651500, 1573000000
    ]
        .span();
    // [Assert] absorptions & times set correctly
    project.set_absorptions(times, absorptions);
    assert(project.get_absorptions() == absorptions, 'absorptions not set correctly');
    assert(project.get_times() == times, 'times not set correctly');
    let current_time = get_block_timestamp();
    spy
        .assert_emitted(
            @array![
                (
                    project_address,
                    AbsorberComponent::Event::AbsorptionUpdate(
                        AbsorberComponent::AbsorptionUpdate { time: current_time }
                    )
                )
            ]
        );
    // found events are removed from the spy after assertion, so the length should be 0
    assert(spy.events.len() == 0, 'number of events should be 0');

    // [Assert] absorptions can be fetched correctly according to time
    // at t = 1651363200
    start_warp(CheatTarget::One(project_address), 1651363200);
    assert(project.get_current_absorption() == 0, 'current absorption not correct');

    // at t = 1659312000
    start_warp(CheatTarget::One(project_address), 1659312000);
    assert(project.get_current_absorption() == 1179750, 'current absorption not correct');
}

#[test]
#[should_panic(expected: ('Times and absorptions mismatch',))]
fn test_set_absorptions_revert_length_mismatch() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] reverting when times and absorptions have different lengths
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span(); // length 3
    let absorptions: Span<u64> = array![0, 1179750].span(); // length 2
    project.set_absorptions(times, absorptions);
}

#[test]
#[should_panic(expected: ('Inputs cannot be empty',))]
fn test_set_absorptions_revert_empty_inputs() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] reverting when times and absorptions are empty arrays
    let times: Span<u64> = array![].span();
    let absorptions: Span<u64> = array![].span();
    project.set_absorptions(times, absorptions);
}

#[test]
#[should_panic(expected: ('Times not sorted',))]
fn test_set_absorptions_revert_times_not_sorted() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] reverting when times array is not sorted
    let times: Span<u64> = array![1651363200, 1659312000, 1657260800].span(); // not sorted
    let absorptions: Span<u64> = array![0, 1179750, 2359500].span();
    project.set_absorptions(times, absorptions);
}

#[test]
#[should_panic(expected: 'Absorptions not sorted',)]
fn test_set_absorptions_revert_absorptions_not_sorted() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] reverting when absorptions array is not sorted
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
    let absorptions: Span<u64> = array![0, 2359500, 1179750].span(); // not sorted
    project.set_absorptions(times, absorptions);
}

// get_current_absorption

#[test]
fn test_get_current_absorption_not_set() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] absorption is 0 when not set at t = 0
    let absorption = project.get_current_absorption();
    assert(absorption == 0, 'default absorption should be 0');
    // [Assert] absorption is 0 when not set after t > 0
    start_warp(CheatTarget::One(project_address), 86000);
    let absorption = project.get_current_absorption();
    assert(absorption == 0, 'default absorption should be 0');
}

#[test]
fn test_current_absorption() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
        .span();
    let absorptions: Span<u64> = array![
        0, 1179750000000, 2359500000000, 3539250000000, 4719000000000
    ]
        .span();
    project.set_absorptions(times, absorptions);
    // [Assert] At start, absorption = absorptions[0]
    start_warp(CheatTarget::One(project_address), 0);
    let absorption = project.get_current_absorption();
    assert(absorption == *absorptions.at(0), 'Wrong absorption');
    // [Assert] After start, absorptions[0] < absorption < absorptions[1]
    start_warp(CheatTarget::One(project_address), *times.at(0) + 86000);
    let absorption = project.get_current_absorption();
    assert(absorption > *absorptions.at(0), 'Wrong absorption');
    assert(absorption < *absorptions.at(1), 'Wrong absorption');
    // [Assert] Before end, absorptions[-2] < absorption < absorptions[-1]
    start_warp(CheatTarget::One(project_address), *times.at(times.len() - 1) - 86000);
    let absorption = project.get_current_absorption();
    assert(absorption > *absorptions.at(absorptions.len() - 2), 'Wrong absorption');
    assert(absorption < *absorptions.at(absorptions.len() - 1), 'Wrong absorption');
    // [Assert] At end, absorption = absorptions[-1]
    start_warp(CheatTarget::One(project_address), *times.at(times.len() - 1));
    let absorption = project.get_current_absorption();
    assert(absorption == *absorptions.at(absorptions.len() - 1), 'Wrong absorption');
    // [Assert] After end, absorption = absorptions[-1]
    start_warp(CheatTarget::One(project_address), *times.at(times.len() - 1) + 86000);
    let absorption = project.get_current_absorption();
    assert(absorption == *absorptions.at(absorptions.len() - 1), 'Wrong absorption');
}

// compute_carbon_vintage_distribution

#[test]
fn test_compute_carbon_vintage_distribution() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();

    let absorptions: Span<u64> = array![0, 1179750000000, 2359500000000].span();
    setup_project(project_address, 121099000000, times, absorptions);

    let share = 10*CC_DECIMALS_MULTIPLIER;  // 10%
    // [Assert] carbon_vintage_distribution computed correctly
    let distribution = project.compute_carbon_vintage_distribution(share);
    assert(distribution == array![0, 117975000000, 117975000000].span(), 'Wrong distribution');
}

#[test]
fn test_compute_carbon_vintage_distribution_zero_share() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();

    let absorptions: Span<u64> = array![0, 1179750000000, 2359500000000].span();
    setup_project(project_address, 121099000000, times, absorptions);

    let share = 0;
    // [Assert] carbon_vintage_distribution computed correctly
    let distribution = project.compute_carbon_vintage_distribution(share);
    assert(distribution == array![0, 0, 0].span(), 'Wrong distribution');
}

#[test]
fn test_compute_carbon_vintage_distribution_full_share() {
    let (project_address, _) = deploy_project(c::OWNER());
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();

    let absorptions: Span<u64> = array![0, 1179750000000, 2359500000000].span();
    setup_project(project_address, 121099000000, times, absorptions);

    let share = 100*CC_DECIMALS_MULTIPLIER;  // 100%
    // [Assert] carbon_vintage_distribution computed correctly
    let distribution = project.compute_carbon_vintage_distribution(share);
    assert(distribution == array![0, 1179750000000, 1179750000000].span(), 'Wrong distribution');
}

// get_cc_vintages

#[test]
fn test_get_cc_vintages() {
    let (project_address, _) = deploy_project(c::OWNER());
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
        .span();

    let absorptions: Span<u64> = array![
        0, 1179750000000, 2359500000000, 3739250000000, 5119000000000
    ]
        .span();
    setup_project(project_address, 121099000000, times, absorptions);

    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    // [Assert] cc_vintages set according to absorptions
    let cc_vintages = cc_handler.get_cc_vintages();
    let starting_year = 2024;
    let mut index = 0;

    let vintage = cc_vintages.at(index);
    let expected__cc_vintage = CarbonVintage {
        vintage: (starting_year + index).into(),
        supply: *absorptions.at(index),
        failed: 0,
        status: CarbonVintageType::Projected,
    };
    assert(*vintage == expected__cc_vintage, 'vintage not set correctly');
    index += 1;
    loop {
        if index == absorptions.len() {
            break;
        }
        let vintage = cc_vintages.at(index);
        let expected__cc_vintage = CarbonVintage {
            vintage: (starting_year + index).into(),
            supply: *absorptions.at(index) - *absorptions.at(index - 1),
            failed: 0,
            status: CarbonVintageType::Projected,
        };
        assert(*vintage == expected__cc_vintage, 'vintage not set correctly');
        index += 1;
    };
    // [Assert] cc_vintages set to default values for non-set absorptions
    loop {
        if index == cc_vintages.len() {
            break;
        }
        let vintage = cc_vintages.at(index);
        let expected__cc_vintage = CarbonVintage {
            vintage: (starting_year + index).into(),
            supply: 0,
            failed: 0,
            status: CarbonVintageType::Projected,
        };

        assert(*vintage == expected__cc_vintage, 'vintage not set correctly');
        index += 1;
    }
}


#[test]
fn test_rebase_half_supply() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = deploy_project(owner_address);

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
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let project = IProjectDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let share = 500000; // 50%
    mint_utils(project_address, owner_address, share);

    let cc_vintage_years: Span<u256> = cc_handler.get_vintage_years();

    // Rebase every vintage with half the supply
    let mut index = 0;
    loop {
        if index == cc_vintage_years.len() {
            break;
        }
        let old_vintage_supply = cc_handler.get_carbon_vintage(*cc_vintage_years.at(index)).supply;
        let old_cc_balance = project.balance_of(owner_address, *cc_vintage_years.at(index));
        // rebase
        absorber.rebase_vintage(*cc_vintage_years.at(index), old_vintage_supply / 2);
        let new_vintage_supply = cc_handler.get_carbon_vintage(*cc_vintage_years.at(index)).supply;
        let new_cc_balance = project.balance_of(owner_address, *cc_vintage_years.at(index));
        let failed_tokens = cc_handler.get_carbon_vintage(*cc_vintage_years.at(index)).failed;
        assert(new_vintage_supply == old_vintage_supply / 2, 'rebase not correct');
        assert(new_cc_balance == old_cc_balance / 2, 'balance error after rebase');
        assert(failed_tokens == old_vintage_supply - new_vintage_supply, 'failed tokens not 0');
        index += 1;
    };
}
