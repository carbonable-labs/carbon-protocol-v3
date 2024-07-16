// Starknet deps

use starknet::{ContractAddress, contract_address_const};
use starknet::get_block_timestamp;

// External deps

use openzeppelin::tests::utils::constants as c;
use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std as snf;
use snforge_std::{
    CheatTarget, ContractClassTrait, test_address, spy_events, EventSpy, SpyOn, EventAssertions,
    start_warp, start_prank, stop_prank
};

// Components

use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
use carbon_v3::components::vintage::VintageComponent::{Event, ProjectCarbonUpdate};
use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
use carbon_v3::models::constants::CC_DECIMALS_MULTIPLIER;
use carbon_v3::components::vintage::VintageComponent;

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

const PROJECT_CARBON: u128 = 42;

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
    let vintages = IVintageDispatcher { contract_address: project_address };
    // [Prank] Use owner as caller to Project contract
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    start_prank(CheatTarget::One(project_address), owner_address);
    // [Assert] project_carbon set correctly
    vintages.set_project_carbon(PROJECT_CARBON);
    let fetched_value = vintages.get_project_carbon();
    assert(fetched_value == PROJECT_CARBON.into(), 'project_carbon wrong value');
    spy
        .assert_emitted(
            @array![
                (
                    project_address,
                    VintageComponent::Event::ProjectCarbonUpdate(
                        VintageComponent::ProjectCarbonUpdate {
                            old_carbon: 0, new_carbon: fetched_value
                        }
                    )
                )
            ]
        );
    // found events are removed from the spy after assertion, so the length should be 0
    assert(spy.events.len() == 0, 'number of events should be 0');
}

#[test]
#[should_panic(expected: 'Caller does not have role')]
fn test_set_project_carbon_without_owner_role() {
    let (project_address, _) = deploy_project();
    let vintages = IVintageDispatcher { contract_address: project_address };
    vintages.set_project_carbon(PROJECT_CARBON.into());
}

#[test]
fn test_get_project_carbon_not_set() {
    let (project_address, _) = deploy_project();
    let vintages = IVintageDispatcher { contract_address: project_address };
    // [Assert] default project_carbon is 0
    let fetched_value = vintages.get_project_carbon();
    assert(fetched_value == 0, 'default project_carbon is not 0');
}

#[test]
fn test_set_project_carbon_twice() {
    let (project_address, _) = deploy_project();
    let vintages = IVintageDispatcher { contract_address: project_address };
    // [Prank] Use owner as caller to Project contract
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    start_prank(CheatTarget::One(project_address), owner_address);
    // [Assert] project_carbon set correctly
    vintages.set_project_carbon(PROJECT_CARBON.into());
    let fetched_value = vintages.get_project_carbon();
    assert(fetched_value == PROJECT_CARBON.into(), 'project_carbon wrong value');
    // [Assert] project_carbon updated correctly
    let new_value: u128 = 100;
    vintages.set_project_carbon(new_value);
    let fetched_value = vintages.get_project_carbon();
    assert(fetched_value == new_value, 'project_carbon did not change');
}

/// TODO: set_vintages

// #[test]
// fn test_set_absorptions() {
//     let (project_address, mut spy) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     let times: Span<u64> = array![
//         1651363200,
//         1659312000,
//         1667260800,
//         1675209600,
//         1682899200,
//         1690848000,
//         1698796800,
//         2598134400
//     ]
//         .span();
//     let absorptions: Span<u64> = array![
//         0, 1179750, 2359500, 3539250, 4719000, 6685250, 8651500, 1573000000
//     ]
//         .span();

//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     // [Assert] absorptions & times set correctly
//     vintages.set_absorptions(times, absorptions);
//     assert(vintages.get_absorptions() == absorptions, 'absorptions not set correctly');
//     assert(vintages.get_times() == times, 'times not set correctly');
//     let current_time = get_block_timestamp();
//     spy
//         .assert_emitted(
//             @array![
//                 (
//                     project_address,
//                     VintageComponent::Event::AbsorptionUpdate(
//                         VintageComponent::AbsorptionUpdate { time: current_time }
//                     )
//                 )
//             ]
//         );
//     // found events are removed from the spy after assertion, so the length should be 0
//     assert(spy.events.len() == 0, 'number of events should be 0');

//     // [Assert] absorptions can be fetched correctly according to time
//     // at t = 1651363200
//     start_warp(CheatTarget::One(project_address), 1651363200);
//     assert(vintages.get_current_absorption() == 0, 'current absorption not correct');

//     // at t = 1659312000
//     start_warp(CheatTarget::One(project_address), 1659312000);
//     assert(vintages.get_current_absorption() == 1179750, 'current absorption not correct');
// }

// #[test]
// #[should_panic(expected: 'Caller does not have role')]
// fn test_set_absorptions_without_owner_role() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     let times: Span<u64> = array![
//         1651363200,
//         1659312000,
//         1667260800,
//         1675209600,
//         1682899200,
//         1690848000,
//         1698796800,
//         2598134400
//     ]
//         .span();
//     let absorptions: Span<u64> = array![
//         0, 1179750, 2359500, 3539250, 4719000, 6685250, 8651500, 1573000000
//     ]
//         .span();

//     vintages.set_absorptions(times, absorptions);
// }

// #[test]
// #[should_panic(expected: ('Times and absorptions mismatch',))]
// fn test_set_absorptions_revert_length_mismatch() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract 
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     // [Assert] reverting when times and absorptions have different lengths
//     let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span(); // length 3
//     let absorptions: Span<u64> = array![0, 1179750].span(); // length 2
//     vintages.set_absorptions(times, absorptions);
// }

// #[test]
// #[should_panic(expected: ('Inputs cannot be empty',))]
// fn test_set_absorptions_revert_empty_inputs() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     // [Assert] reverting when times and absorptions are empty arrays
//     let times: Span<u64> = array![].span();
//     let absorptions: Span<u64> = array![].span();
//     vintages.set_absorptions(times, absorptions);
// }

// #[test]
// #[should_panic(expected: ('Times not sorted',))]
// fn test_set_absorptions_revert_times_not_sorted() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     // [Assert] reverting when times array is not sorted
//     let times: Span<u64> = array![1651363200, 1659312000, 1657260800].span(); // not sorted
//     let absorptions: Span<u64> = array![0, 1179750, 2359500].span();
//     vintages.set_absorptions(times, absorptions);
// }

// #[test]
// #[should_panic(expected: 'Times not sorted')]
// fn test_set_absorptions_revert_duplicate_times() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     let times: Span<u64> = array![1651363200, 1651363200, 1667260800].span(); // duplicate times
//     let absorptions: Span<u64> = array![0, 1179750, 2359500].span();
//     vintages.set_absorptions(times, absorptions);
// }

// #[test]
// #[should_panic(expected: 'Absorptions not sorted',)]
// fn test_set_absorptions_revert_absorptions_not_sorted() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     // [Assert] reverting when absorptions array is not sorted
//     let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
//     let absorptions: Span<u64> = array![0, 2359500, 1179750].span(); // not sorted
//     vintages.set_absorptions(times, absorptions);
// }

// #[test]
// fn test_set_absorptions_exact_one_year_interval() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     let times: Span<u64> = array![1609459200, 1640995200, 1672531200]
//         .span(); // exactly one year apart
//     let absorptions: Span<u64> = array![0, 1179750, 2359500].span();
//     vintages.set_absorptions(times, absorptions);
//     assert(vintages.get_absorptions() == absorptions, 'absorptions not set correctly');
//     assert(vintages.get_times() == times, 'times not set correctly');
// }

// #[test]
// fn test_set_absorptions_edge_case_timestamps() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     let times: Span<u64> = array![0, 1, 2, 3, 4, 5, 6, 7].span(); // very small timestamps
//     let absorptions: Span<u64> = array![
//         0, 1179750, 2359500, 3539250, 4719000, 5898750, 7078500, 8258250
//     ]
//         .span();
//     vintages.set_absorptions(times, absorptions);
//     assert(vintages.get_absorptions() == absorptions, 'absorptions error');
//     assert(vintages.get_times() == times, 'times error');
// }

// #[test]
// fn test_set_absorptions_change_length() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
//     let absorptions: Span<u64> = array![0, 1179750, 2359500].span();

//     vintages.set_absorptions(times, absorptions);
//     assert(vintages.get_absorptions() == absorptions, 'absorptions error');

//     let new_times: Span<u64> = array![1675209600, 1682899200].span();
//     let new_absorptions: Span<u64> = array![3539250, 4719000].span();
//     vintages.set_absorptions(new_times, new_absorptions);
//     let length = vintages.get_absorptions().len();

//     assert(length == new_absorptions.len(), 'length error');
//     assert(vintages.get_absorptions() == new_absorptions, 'absorptions error');
//     assert(vintages.get_times() == new_times, 'times error');
// }

// /// get_absorption

// #[test]
// fn test_get_absorption_interpolation() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
//         .span();
//     let absorptions: Span<u64> = array![0, 1179750, 2359500, 3539250, 4719000].span();
//     vintages.set_absorptions(times, absorptions);
//     // Test midpoints between times for linear interpolation
//     let mut i = 0;
//     loop {
//         let mid_time = (*times.at(i) + *times.at(i + 1)) / 2;
//         let expected_absorption = (*absorptions.at(i) + *absorptions.at(i + 1)) / 2;
//         let absorption = vintages.get_absorption(mid_time);
//         assert(
//             absorption > *absorptions.at(i) && absorption < *absorptions.at(i + 1),
//             'Interpolation error'
//         );
//         assert(absorption == expected_absorption, 'Absorption value not expected');
//         i += 1;

//         if i >= times.len() - 1 {
//             break;
//         }
//     }
// }

// #[test]
// fn test_get_current_absorption_extrapolation() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
//         .span();
//     let absorptions: Span<u64> = array![0, 1179750, 2359500, 3539250, 4719000].span();
//     vintages.set_absorptions(times, absorptions);
//     // Test time before first absorption
//     start_warp(CheatTarget::One(project_address), *times.at(0) - 86000);
//     let current_absorption = vintages.get_current_absorption();
//     // [Assert] current_absorption should equal first value for times before first time point
//     assert(current_absorption == *absorptions.at(0), 'absorption error');
//     // Test time after last absorption
//     start_warp(CheatTarget::One(project_address), *times.at(times.len() - 1) + 86000);
//     let current_absorption = vintages.get_current_absorption();
//     // [Assert] current_absorption should equal last value for times after last time point
//     assert(current_absorption == *absorptions.at(absorptions.len() - 1), 'absorption error');
// }

// /// get_current_absorption

// #[test]
// fn test_get_current_absorption_not_set() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Assert] absorption is 0 when not set at t = 0
//     let absorption = vintages.get_current_absorption();
//     assert(absorption == 0, 'default absorption should be 0');
//     // [Assert] absorption is 0 when not set after t > 0
//     start_warp(CheatTarget::One(project_address), 86000);
//     let absorption = vintages.get_current_absorption();
//     assert(absorption == 0, 'default absorption should be 0');
// }

// #[test]
// fn test_current_absorption() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
//         .span();
//     let absorptions: Span<u64> = array![
//         0, 1179750000000, 2359500000000, 3539250000000, 4719000000000
//     ]
//         .span();
//     vintages.set_absorptions(times, absorptions);
//     // [Assert] At start, absorption = absorptions[0]
//     start_warp(CheatTarget::One(project_address), 0);
//     let absorption = vintages.get_current_absorption();
//     assert(absorption == *absorptions.at(0), 'Wrong absorption');
//     // [Assert] After start, absorptions[0] < absorption < absorptions[1]
//     start_warp(CheatTarget::One(project_address), *times.at(0) + 86000);
//     let absorption = vintages.get_current_absorption();
//     assert(absorption > *absorptions.at(0), 'Wrong absorption');
//     assert(absorption < *absorptions.at(1), 'Wrong absorption');
//     // [Assert] Before end, absorptions[-2] < absorption < absorptions[-1]
//     start_warp(CheatTarget::One(project_address), *times.at(times.len() - 1) - 86000);
//     let absorption = vintages.get_current_absorption();
//     assert(absorption > *absorptions.at(absorptions.len() - 2), 'Wrong absorption');
//     assert(absorption < *absorptions.at(absorptions.len() - 1), 'Wrong absorption');
//     // [Assert] At end, absorption = absorptions[-1]
//     start_warp(CheatTarget::One(project_address), *times.at(times.len() - 1));
//     let absorption = vintages.get_current_absorption();
//     assert(absorption == *absorptions.at(absorptions.len() - 1), 'Wrong absorption');
//     // [Assert] After end, absorption = absorptions[-1]
//     start_warp(CheatTarget::One(project_address), *times.at(times.len() - 1) + 86000);
//     let absorption = vintages.get_current_absorption();
//     assert(absorption == *absorptions.at(absorptions.len() - 1), 'Wrong absorption');
// }

// /// get_final_absorption

// #[test]
// fn test_get_final_absorption() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
//     let absorptions: Span<u64> = array![0, 1179750, 2359500].span();
//     vintages.set_absorptions(times, absorptions);
//     assert(vintages.get_final_absorption() == 2359500, 'Final absorption not correct');
// }

// #[test]
// fn test_get_final_absorption_no_data() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     assert(vintages.get_final_absorption() == 0, 'Final absorption not correct');
// }

// #[test]
// fn test_get_final_absorption_single_value() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     let times: Span<u64> = array![1651363200].span();
//     let absorptions: Span<u64> = array![1179750].span();
//     vintages.set_absorptions(times, absorptions);
//     assert(vintages.get_final_absorption() == 1179750, 'Final absorption not correct');
// }

// #[test]
// fn test_get_final_absorption_after_updates() {
//     let (project_address, _) = deploy_project();
//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Prank] Use owner as caller to Project contract
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     start_prank(CheatTarget::One(project_address), owner_address);
//     let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
//     let absorptions: Span<u64> = array![1000, 2000, 3000].span();
//     vintages.set_absorptions(times, absorptions);

//     let new_times: Span<u64> = array![1675209600, 1682899200].span();
//     let new_absorptions: Span<u64> = array![4000, 5000].span();
//     vintages.set_absorptions(new_times, new_absorptions);

//     assert(vintages.get_final_absorption() == 5000, 'Final absorption not correct');
// }

/// share_to_cc

#[test]
fn test_share_to_cc_zero_share() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let token_id: u256 = 1.into();
    let share: u256 = 0.into();
    let cc_value = vintages.share_to_cc(share, token_id);
    assert(cc_value == 0.into(), 'CC value should be zero');
}

#[test]
#[should_panic(expected: 'CC value exceeds vintage supply')]
fn test_share_to_cc_revert_exceeds_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let share: u256 = 2 * CC_DECIMALS_MULTIPLIER; // share is greater than 100%
    let token_id = 1;
    vintages.share_to_cc(share, token_id);
}

#[test]
fn test_share_to_cc_equal_to_multiplier() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let share: u256 = CC_DECIMALS_MULTIPLIER.into();
    let token_id = 1;
    let supply = vintages.get_carbon_vintage(token_id).supply;
    let result = vintages.share_to_cc(share, token_id);
    assert(result == supply.into(), 'Result should equal cc_supply');
    assert(result > 0, 'Result should be greater than 0');
}

#[test]
fn test_share_to_cc_half_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let share: u256 = 50 * CC_DECIMALS_MULTIPLIER / 100; // 50%
    let token_id: u256 = 1;
    let cc_supply = vintages.get_carbon_vintage(token_id).supply;
    let result = vintages.share_to_cc(share, token_id);
    assert(result == cc_supply.into() / 2, 'Result error');
    assert(result > 0, 'Result should be greater than 0');
}

#[test]
fn test_share_to_cc_non_existent_token_id() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let token_id: u256 = 999.into(); // Assuming 999 does not exist
    let share: u256 = 50 * CC_DECIMALS_MULTIPLIER / 100; // 50%
    let result = vintages.share_to_cc(share, token_id);
    assert(result == 0.into(), 'Result should be 0');
}

#[test]
fn test_share_to_cc_zero_cc_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let token_id: u256 = 1;
    let share: u256 = 1000.into();
    let result = vintages.share_to_cc(share, token_id);
    assert(result == 0.into(), 'Result should be 0');
}

// cc_to_share

#[test]
fn test_cc_to_share_zero_cc_value() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let token_id: u256 = 1;
    let cc_value: u256 = 0.into();
    let share_value = vintages.cc_to_share(cc_value, token_id);
    assert(share_value == 0.into(), 'Share value should be zero');
}

#[test]
fn test_cc_to_share_equal_to_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let token_id: u256 = 1;

    let cc_supply = vintages.get_carbon_vintage(token_id).supply.into();
    let cc_value: u256 = cc_supply;
    let result = vintages.cc_to_share(cc_value, token_id);
    assert(result == CC_DECIMALS_MULTIPLIER.into(), 'Result error');
    assert(result > 0, 'Result should be greater than 0');
}

#[test]
fn test_cc_to_share_half_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let token_id: u256 = 1;

    let cc_supply = vintages.get_carbon_vintage(token_id).supply.into();
    let cc_value: u256 = cc_supply / 2;
    let result = vintages.cc_to_share(cc_value, token_id);
    assert(result == 50 * CC_DECIMALS_MULTIPLIER / 100, 'Result error');
    assert(result > 0, 'Result should be greater than 0');
}

#[test]
#[should_panic(expected: 'CC supply of vintage is 0')]
fn test_cc_to_share_zero_cc_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let token_id: u256 = 1;

    let cc_value: u256 = 1000.into();
    vintages.rebase_vintage(token_id, 0);
    let result = vintages.cc_to_share(cc_value, token_id);

    let cc_supply = vintages.get_carbon_vintage(token_id).supply.into();
    assert(cc_supply == 0, 'CC supply should be 0');
    assert(result == 0, 'Result should be 0');
}

#[test]
#[should_panic(expected: 'CC supply of vintage is 0')]
fn test_cc_to_share_non_existent_token_id() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let cc_value: u256 = 100000.into();
    vintages.cc_to_share(cc_value, 999);
}

#[test]
#[should_panic(expected: 'Share value exceeds 100%')]
fn test_cc_to_share_revert_exceeds_supply() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let token_id: u256 = 1;

    let cc_supply = vintages.get_carbon_vintage(token_id).supply.into();
    let cc_value: u256 = 2 * cc_supply;
    vintages.cc_to_share(cc_value, token_id);
}

/// get_cc_vintages

// #[test]
// fn test_get_cc_vintages() {
//     let (project_address, _) = deploy_project();
//     let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
//         .span();

//     let absorptions: Span<u64> = array![
//         0, 1179750000000, 2359500000000, 3739250000000, 5119000000000
//     ]
//         .span();
//     setup_project(project_address, 121099000000, times, absorptions);

//     let vintages = IVintageDispatcher { contract_address: project_address };
//     // [Assert] cc_vintages set according to absorptions
//     let cc_vintages = vintages.get_cc_vintages();

//     let starting_year: u64 = vintages.get_starting_year();
//     let mut index = 0;

//     let vintage = cc_vintages.at(index);
//     let expected__cc_vintage = CarbonVintage {
//         vintage: (starting_year.into() + index.into()),
//         supply: *absorptions.at(index),
//         failed: 0,
//         status: CarbonVintageType::Projected,
//     };
//     assert(*vintage == expected__cc_vintage, 'vintage not set correctly');
//     index += 1;
//     loop {
//         if index == absorptions.len() {
//             break;
//         }
//         let vintage = cc_vintages.at(index);
//         let expected__cc_vintage = CarbonVintage {
//             vintage: (starting_year.into() + index.into()),
//             supply: *absorptions.at(index) - *absorptions.at(index - 1),
//             failed: 0,
//             status: CarbonVintageType::Projected,
//         };
//         assert(*vintage == expected__cc_vintage, 'vintage not set correctly');
//         index += 1;
//     };
//     // [Assert] cc_vintages set to default values for non-set absorptions
//     loop {
//         if index == cc_vintages.len() {
//             break;
//         }
//         let vintage = cc_vintages.at(index);
//         let expected__cc_vintage: CarbonVintage = CarbonVintage {
//             vintage: (starting_year.into() + index.into()),
//             supply: 0,
//             failed: 0,
//             status: CarbonVintageType::Unset,
//         };
//         assert(*vintage == expected__cc_vintage, 'vintage not set correctly');
//         index += 1;
//     }
// }

/// get_vintage_years

#[test]
fn test_get_vintage_multiple() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let carbon_vintages = vintages.get_cc_vintages();
    let starting_year = 2024_u32;

    let mut index: usize = 0;
    loop {
        if index == carbon_vintages.len() {
            break;
        }
        let year = *carbon_vintages.at(index).year;
        assert(year == (starting_year + index.into()).into(), 'Year not set correctly');
        index += 1;
    }
}

/// get_carbon_vintage

// #[test]
// fn test_get_carbon_vintage() {
//     let (project_address, _) = deploy_project();

//     let times: Span<u64> = array![1651363200, 1659312000, 1667260800, 1675209600, 1682899200]
//         .span();

//     let absorptions: Span<u64> = array![
//         0, 1179750000000, 2359500000000, 3739250000000, 5119000000000
//     ]
//         .span();
//     setup_project(project_address, 121099000000, times, absorptions);

//     let vintages = IVintageDispatcher { contract_address: project_address };

//     let mut index = 0;

//     let cc_vintage = cc_handler
//         .get_carbon_vintage((vintages.get_starting_year() + index.into()).into());
//     let expected_cc_vintage = CarbonVintage {
//         vintage: (vintages.get_starting_year() + index.into()).into(),
//         supply: *absorptions.at(index),
//         failed: 0,
//         status: CarbonVintageType::Projected,
//     };

//     assert(cc_vintage == expected_cc_vintage, 'cc_vintage not set correctly');
//     index += 1;

//     loop {
//         if index == absorptions.len() {
//             break;
//         }
//         let starting_year = vintages.get_starting_year();
//         let cc_vintage = vintages.get_carbon_vintage((starting_year + index.into()).into());

//         let expected_cc_vintage = CarbonVintage {
//             vintage: (starting_year + index.into()).into(),
//             supply: *absorptions.at(index) - *absorptions.at(index - 1),
//             failed: 0,
//             status: CarbonVintageType::Projected,
//         };

//         assert(cc_vintage == expected_cc_vintage, 'cc_vintage not set correctly');
//         index += 1;
//     };
// }

#[test]
fn test_get_carbon_vintage_non_existent_token_id() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let token_id: u256 = 999.into(); // Assuming 999 does not exist

    let default_vintage: CarbonVintage = Default::default();

    let vintage = vintages.get_carbon_vintage(token_id);
    assert(vintage == default_vintage, 'Vintage should be default');
}

/// get_cc_decimals

#[test]
fn test_get_cc_decimals() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let cc_decimals = vintages.get_cc_decimals();
    assert(cc_decimals == 8, 'CC decimals should be 8');
}

/// update_vintage_status

#[test]
fn test_update_vintage_status_valid() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let token_id: u256 = 1;

    let mut new_status: u8 = 0;
    loop {
        if new_status > 3 {
            break;
        }
        vintages.update_vintage_status(token_id, new_status);
        let updated_vintage = vintages.get_carbon_vintage(token_id.into());
        let status: u8 = updated_vintage.status.into();
        assert(status == new_status, 'Error status update');
        new_status += 1;
    };
}

#[test]
#[should_panic(expected: 'Invalid status')]
fn test_update_vintage_status_invalid() {
    let (project_address, _) = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let token_id: u256 = 1;
    let invalid_status: u8 = 5; // Example invalid status
    vintages.update_vintage_status(token_id, invalid_status);
}

#[test]
#[should_panic(expected: 'Caller does not have role')]
fn test_update_vintage_status_without_owner_role() {
    let (project_address, _) = deploy_project();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let token_id: u256 = 1;
    let new_status: u8 = 2;
    start_prank(CheatTarget::One(project_address), contract_address_const::<'USER'>());
    vintages.update_vintage_status(token_id, new_status);
}

// #[test]  todo, what do we expect here?
// fn test_update_vintage_status_non_existent_token_id() {
//     let (project_address, _) = default_setup_and_deploy();
// 
//     let token_id: u64 = 999; // Assuming 999 does not exist
//     let new_status: u8 = 2;
//     vintages.update_vintage_status(token_id, new_status);
// }

/// rebase_vintage

#[test]
fn test_rebase_half_supply() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let project = IProjectDispatcher { contract_address: project_address };

    // [Prank] Use owner as caller to Project contract
    start_prank(CheatTarget::One(project_address), owner_address);
    // [Effect] Grant Minter role to Minter contract
    project.grant_minter_role(minter_address);
    // [Prank] Stop prank on Project contract
    stop_prank(CheatTarget::One(project_address));
    // [Prank] Simulate production flow, Minter calls Project contract
    start_prank(CheatTarget::One(project_address), minter_address);

    let share = 50 * CC_DECIMALS_MULTIPLIER / 100; // 50%

    buy_utils(owner_address, user_address, minter_address, share);

    let num_vintages = vintages.get_num_vintages();

    // Rebase every vintage with half the supply
    let mut index = 0;
    loop {
        if index == num_vintages {
            break;
        }
        let token_id: u256 = index.into();
        let old_vintage_supply = vintages.get_carbon_vintage(token_id).supply;
        let old_cc_balance = project.balance_of(owner_address, token_id);
        // rebase
        // [Prank] use owner to rebase rebase_vintage
        start_prank(CheatTarget::One(project_address), owner_address);
        vintages.rebase_vintage(token_id, old_vintage_supply / 2);
        // [Prank] stop prank on vintages contract
        stop_prank(CheatTarget::One(project_address));
        let new_vintage_supply = vintages.get_carbon_vintage(token_id).supply;
        let new_cc_balance = project.balance_of(owner_address, token_id);
        let failed_tokens = vintages.get_carbon_vintage(token_id).failed;
        assert(new_vintage_supply == old_vintage_supply / 2, 'rebase not correct');
        assert(new_cc_balance == old_cc_balance / 2, 'balance error after rebase');
        assert(failed_tokens == old_vintage_supply - new_vintage_supply, 'failed tokens not 0');
        index += 1;
    };
}
