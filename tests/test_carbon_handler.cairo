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
    default_setup_and_deploy, fuzzing_setup, perform_fuzzed_transfer, buy_utils, deploy_burner, deploy_minter, deploy_erc20
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

// set_absorptions

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
#[should_panic(expected: 'Absorptions not sorted',)]
fn test_set_absorptions_revert_absorptions_not_sorted() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };
    // [Assert] reverting when absorptions array is not sorted
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
    let absorptions: Span<u64> = array![0, 2359500, 1179750].span(); // not sorted
    project.set_absorptions(times, absorptions);
}

// get_current_absorption

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

// get_cc_vintages

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
    let share = 50*CC_DECIMALS_MULTIPLIER /100; // 50%

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
