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

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};

// Utils for testing purposes

use super::tests_lib::{
    get_mock_times, get_mock_absorptions, equals_with_error, deploy_project, setup_project,
    default_setup_and_deploy, fuzzing_setup, perform_fuzzed_transfer, buy_utils, deploy_offsetter,
    deploy_minter, deploy_erc20
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

/// set_project_carbon

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

#[test]
fn test_get_project_carbon_not_set() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] default project_carbon is 0
    let fetched_value = project.get_project_carbon();
    assert(fetched_value == 0, 'default project_carbon is not 0');
}

#[test]
fn test_set_project_carbon_twice() {
    let (project_address, _) = deploy_project();
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

/// set_absorptions

#[test]
fn test_set_absorptions() {
    let (project_address, mut spy) = deploy_project();
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
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] reverting when times and absorptions have different lengths
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span(); // length 3
    let absorptions: Span<u64> = array![0, 1179750].span(); // length 2
    project.set_absorptions(times, absorptions);
}

#[test]
#[should_panic(expected: ('Inputs cannot be empty',))]
fn test_set_absorptions_revert_empty_inputs() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] reverting when times and absorptions are empty arrays
    let times: Span<u64> = array![].span();
    let absorptions: Span<u64> = array![].span();
    project.set_absorptions(times, absorptions);
}

#[test]
#[should_panic(expected: ('Times not sorted',))]
fn test_set_absorptions_revert_times_not_sorted() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] reverting when times array is not sorted
    let times: Span<u64> = array![1651363200, 1659312000, 1657260800].span(); // not sorted
    let absorptions: Span<u64> = array![0, 1179750, 2359500].span();
    project.set_absorptions(times, absorptions);
}

#[test]
#[should_panic(expected: 'Times not sorted')]
fn test_set_absorptions_revert_duplicate_times() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1651363200, 1667260800].span(); // duplicate times
    let absorptions: Span<u64> = array![0, 1179750, 2359500].span();
    project.set_absorptions(times, absorptions);
}

#[test]
#[should_panic(expected: 'Absorptions not sorted',)]
fn test_set_absorptions_revert_absorptions_not_sorted() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] reverting when absorptions array is not sorted
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
    let absorptions: Span<u64> = array![0, 2359500, 1179750].span(); // not sorted
    project.set_absorptions(times, absorptions);
}

#[test]
fn test_set_absorptions_exact_one_year_interval() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1609459200, 1640995200, 1672531200]
        .span(); // exactly one year apart
    let absorptions: Span<u64> = array![0, 1179750, 2359500].span();
    project.set_absorptions(times, absorptions);
    assert(project.get_absorptions() == absorptions, 'absorptions not set correctly');
    assert(project.get_times() == times, 'times not set correctly');
}

#[test]
fn test_set_absorptions_edge_case_timestamps() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![0, 1, 2, 3, 4, 5, 6, 7].span(); // very small timestamps
    let absorptions: Span<u64> = array![
        0, 1179750, 2359500, 3539250, 4719000, 5898750, 7078500, 8258250
    ]
        .span();
    project.set_absorptions(times, absorptions);
    assert(project.get_absorptions() == absorptions, 'absorptions error');
    assert(project.get_times() == times, 'times error');
}

#[test]
fn test_set_absorptions_change_length() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
    let absorptions: Span<u64> = array![0, 1179750, 2359500].span();

    project.set_absorptions(times, absorptions);
    assert(project.get_absorptions() == absorptions, 'absorptions error');

    let new_times: Span<u64> = array![1675209600, 1682899200].span();
    let new_absorptions: Span<u64> = array![3539250, 4719000].span();
    project.set_absorptions(new_times, new_absorptions);
    let length = project.get_absorptions().len();

    assert(length == new_absorptions.len(), 'length error');
    assert(project.get_absorptions() == new_absorptions, 'absorptions error');
    assert(project.get_times() == new_times, 'times error');
}

/// get_absorption

#[test]
fn test_get_absorption_interpolation() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
        .span();
    let absorptions: Span<u64> = array![0, 1179750, 2359500, 3539250, 4719000].span();
    project.set_absorptions(times, absorptions);
    // Test midpoints between times for linear interpolation
    let mut i = 0;
    loop {
        let mid_time = (*times.at(i) + *times.at(i + 1)) / 2;
        let expected_absorption = (*absorptions.at(i) + *absorptions.at(i + 1)) / 2;
        let absorption = project.get_absorption(mid_time);
        assert(
            absorption > *absorptions.at(i) && absorption < *absorptions.at(i + 1),
            'Interpolation error'
        );
        assert(absorption == expected_absorption, 'Absorption value not expected');
        i += 1;

        if i >= times.len() - 1 {
            break;
        }
    }
}

#[test]
fn test_get_current_absorption_extrapolation() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
        .span();
    let absorptions: Span<u64> = array![0, 1179750, 2359500, 3539250, 4719000].span();
    project.set_absorptions(times, absorptions);
    // Test time before first absorption
    start_warp(CheatTarget::One(project_address), *times.at(0) - 86000);
    let current_absorption = project.get_current_absorption();
    // [Assert] current_absorption should equal first value for times before first time point
    assert(current_absorption == *absorptions.at(0), 'absorption error');
    // Test time after last absorption
    start_warp(CheatTarget::One(project_address), *times.at(times.len() - 1) + 86000);
    let current_absorption = project.get_current_absorption();
    // [Assert] current_absorption should equal last value for times after last time point
    assert(current_absorption == *absorptions.at(absorptions.len() - 1), 'absorption error');
}

/// get_current_absorption

#[test]
fn test_get_current_absorption_not_set() {
    let (project_address, _) = deploy_project();
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
    let (project_address, _) = deploy_project();
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

/// get_final_absorption

#[test]
fn test_get_final_absorption() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
    let absorptions: Span<u64> = array![0, 1179750, 2359500].span();
    project.set_absorptions(times, absorptions);
    assert(project.get_final_absorption() == 2359500, 'Final absorption not correct');
}

#[test]
fn test_get_final_absorption_no_data() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    assert(project.get_final_absorption() == 0, 'Final absorption not correct');
}

#[test]
fn test_get_final_absorption_single_value() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200].span();
    let absorptions: Span<u64> = array![1179750].span();
    project.set_absorptions(times, absorptions);
    assert(project.get_final_absorption() == 1179750, 'Final absorption not correct');
}

#[test]
fn test_get_final_absorption_after_updates() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
    let absorptions: Span<u64> = array![1000, 2000, 3000].span();
    project.set_absorptions(times, absorptions);

    let new_times: Span<u64> = array![1675209600, 1682899200].span();
    let new_absorptions: Span<u64> = array![4000, 5000].span();
    project.set_absorptions(new_times, new_absorptions);

    assert(project.get_final_absorption() == 5000, 'Final absorption not correct');
}

/// share_to_cc

#[test]
fn test_share_to_cc_zero_share() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let token_id: u256 = 1.into();
    let share: u256 = 0.into();
    let cc_value = project.share_to_cc(share, token_id);
    assert(cc_value == 0.into(), 'CC value should be zero');
}

#[test]
#[should_panic(expected: 'CC value exceeds vintage supply')]
fn test_share_to_cc_revert_exceeds_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let share: u256 = 2 * CC_DECIMALS_MULTIPLIER; // share is greater than 100%
    project.share_to_cc(share, 2025);
}

#[test]
fn test_share_to_cc_equal_to_multiplier() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let share: u256 = CC_DECIMALS_MULTIPLIER.into();
    let cc_supply = cc_handler.get_carbon_vintage(2025).supply;
    let result = project.share_to_cc(share, 2025);
    assert(result == cc_supply.into(), 'Result should equal cc_supply');
    assert(result > 0, 'Result should be greater than 0');
}

#[test]
fn test_share_to_cc_half_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let share: u256 = 50 * CC_DECIMALS_MULTIPLIER / 100; // 50%
    let cc_supply = cc_handler.get_carbon_vintage(2025).supply;
    let result = project.share_to_cc(share, 2025);
    assert(result == cc_supply.into() / 2, 'Result error');
    assert(result > 0, 'Result should be greater than 0');
}

#[test]
fn test_share_to_cc_non_existent_token_id() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let token_id: u256 = 999.into(); // Assuming 999 does not exist
    let share: u256 = 50 * CC_DECIMALS_MULTIPLIER / 100; // 50%
    let result = project.share_to_cc(share, token_id);
    assert(result == 0.into(), 'Result should be 0');
}

#[test]
fn test_share_to_cc_zero_cc_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let share: u256 = 1000.into();
    let result = project.share_to_cc(share, 2025);
    assert(result == 0.into(), 'Result should be 0');
}

// cc_to_share

#[test]
fn test_cc_to_share_zero_cc_value() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let cc_value: u256 = 0.into();
    let share_value = project.cc_to_share(cc_value, 2025);
    assert(share_value == 0.into(), 'Share value should be zero');
}

#[test]
fn test_cc_to_share_equal_to_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let cc_supply = cc_handler.get_carbon_vintage(2025).supply.into();
    let cc_value: u256 = cc_supply;
    let result = project.cc_to_share(cc_value, 2025);
    assert(result == CC_DECIMALS_MULTIPLIER.into(), 'Result error');
    assert(result > 0, 'Result should be greater than 0');
}

#[test]
fn test_cc_to_share_half_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let cc_supply = cc_handler.get_carbon_vintage(2025).supply.into();
    let cc_value: u256 = cc_supply / 2;
    let result = project.cc_to_share(cc_value, 2025);
    assert(result == 50 * CC_DECIMALS_MULTIPLIER / 100, 'Result error');
    assert(result > 0, 'Result should be greater than 0');
}

#[test]
#[should_panic(expected: 'CC supply of vintage is 0')]
fn test_cc_to_share_zero_cc_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let cc_value: u256 = 1000.into();
    absorber.rebase_vintage(2025, 0);
    let result = project.cc_to_share(cc_value, 2025);

    let cc_supply = cc_handler.get_carbon_vintage(2025).supply.into();
    assert(cc_supply == 0, 'CC supply should be 0');
    assert(result == 0, 'Result should be 0');
}

#[test]
#[should_panic(expected: 'CC supply of vintage is 0')]
fn test_cc_to_share_non_existent_token_id() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let cc_value: u256 = 100000.into();
    project.cc_to_share(cc_value, 999);
}

#[test]
#[should_panic(expected: 'Share value exceeds 100%')]
fn test_cc_to_share_revert_exceeds_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let cc_supply = cc_handler.get_carbon_vintage(2025).supply.into();
    let cc_value: u256 = 2 * cc_supply;
    project.cc_to_share(cc_value, 2025);
}

/// get_cc_vintages

#[test]
fn test_get_cc_vintages() {
    let (project_address, _) = deploy_project();
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
        .span();

    let absorptions: Span<u64> = array![
        0, 1179750000000, 2359500000000, 3739250000000, 5119000000000
    ]
        .span();
    setup_project(project_address, 121099000000, times, absorptions);

    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] cc_vintages set according to absorptions
    let cc_vintages = cc_handler.get_cc_vintages();

    let starting_year: u64 = project.get_starting_year();
    let mut index = 0;

    let vintage = cc_vintages.at(index);
    let expected__cc_vintage = CarbonVintage {
        vintage: (starting_year.into() + index.into()),
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
            vintage: (starting_year.into() + index.into()),
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
        let expected__cc_vintage: CarbonVintage = CarbonVintage {
            vintage: (starting_year.into() + index.into()),
            supply: 0,
            failed: 0,
            status: CarbonVintageType::Unset,
        };
        assert(*vintage == expected__cc_vintage, 'vintage not set correctly');
        index += 1;
    }
}

/// get_vintage_years

#[test]
fn test_get_vintage_years_multiple() {
    let (project_address, _) = default_setup_and_deploy();
    let project = IAbsorberDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let starting_year = project.get_starting_year();
    let years = cc_handler.get_vintage_years();

    let mut index: u32 = 0;
    loop {
        if index == years.len() {
            break;
        }
        let year = *years.at(index);
        assert(year == (starting_year + index.into()).into(), 'Year not set correctly');
        index += 1;
    }
}

/// get_carbon_vintage

#[test]
fn test_get_carbon_vintage() {
    let (project_address, _) = deploy_project();

    let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
        .span();

    let absorptions: Span<u64> = array![
        0, 1179750000000, 2359500000000, 3739250000000, 5119000000000
    ]
        .span();
    setup_project(project_address, 121099000000, times, absorptions);

    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project = IAbsorberDispatcher { contract_address: project_address };

    let mut index = 0;

    let cc_vintage = cc_handler
        .get_carbon_vintage((project.get_starting_year() + index.into()).into());
    let expected_cc_vintage = CarbonVintage {
        vintage: (project.get_starting_year() + index.into()).into(),
        supply: *absorptions.at(index),
        failed: 0,
        status: CarbonVintageType::Projected,
    };

    assert(cc_vintage == expected_cc_vintage, 'cc_vintage not set correctly');
    index += 1;

    loop {
        if index == absorptions.len() {
            break;
        }
        let starting_year = project.get_starting_year();
        let cc_vintage = cc_handler.get_carbon_vintage((starting_year + index.into()).into());

        let expected_cc_vintage = CarbonVintage {
            vintage: (starting_year + index.into()).into(),
            supply: *absorptions.at(index) - *absorptions.at(index - 1),
            failed: 0,
            status: CarbonVintageType::Projected,
        };

        assert(cc_vintage == expected_cc_vintage, 'cc_vintage not set correctly');
        index += 1;
    };
}

#[test]
fn test_get_carbon_vintage_non_existent_token_id() {
    let (project_address, _) = default_setup_and_deploy();
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let token_id: u256 = 999.into(); // Assuming 999 does not exist

    let default_vintage: CarbonVintage = Default::default();

    let vintage = cc_handler.get_carbon_vintage(token_id);
    assert(vintage == default_vintage, 'Vintage should be default');
}

/// get_cc_decimals

#[test]
fn test_get_cc_decimals() {
    let (project_address, _) = default_setup_and_deploy();
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let cc_decimals = cc_handler.get_cc_decimals();
    assert(cc_decimals == 8, 'CC decimals should be 8');
}

/// update_vintage_status

#[test]
fn test_update_vintage_status_valid() {
    let (project_address, _) = default_setup_and_deploy();
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let token_id: u64 = 2024;

    let mut new_status: u8 = 0;
    loop {
        if new_status > 3 {
            break;
        }
        cc_handler.update_vintage_status(token_id, new_status);
        let updated_vintage = cc_handler.get_carbon_vintage(token_id.into());
        let status: u8 = updated_vintage.status.into();
        assert(status == new_status, 'Error status update');
        new_status += 1;
    };
}

#[test]
#[should_panic(expected: 'Invalid status')]
fn test_update_vintage_status_invalid() {
    let (project_address, _) = default_setup_and_deploy();
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let token_id: u64 = 1;
    let invalid_status: u8 = 5; // Example invalid status
    cc_handler.update_vintage_status(token_id, invalid_status);
}

// #[test]  todo, what do we expect here?
// fn test_update_vintage_status_non_existent_token_id() {
//     let (project_address, _) = default_setup_and_deploy();
//     let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
//     let token_id: u64 = 999; // Assuming 999 does not exist
//     let new_status: u8 = 2;
//     cc_handler.update_vintage_status(token_id, new_status);
// }

/// rebase_vintage

#[test]
fn test_rebase_half_supply() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let project = IProjectDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);
    start_prank(CheatTarget::One(project_address), owner_address);
    let share = 50 * CC_DECIMALS_MULTIPLIER / 100; // 50%

    buy_utils(minter_address, erc20_address, share);

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
