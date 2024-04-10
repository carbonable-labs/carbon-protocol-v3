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
    CheatTarget, ContractClassTrait, test_address, spy_events, EventSpy, SpyOn, EventAssertions, start_warp
};
use alexandria_storage::list::{List, ListTrait};

// Components

use carbon_v3::components::absorber::interface::{IAbsorberDispatcher, IAbsorberDispatcherTrait};
use carbon_v3::components::absorber::carbon::AbsorberComponent::{
    Event, AbsorptionUpdate, ProjectValueUpdate
};
use carbon_v3::components::absorber::carbon::AbsorberComponent;

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};

// Constants

const PROJECT_VALUE: u256 = 42;

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
    let uri: ByteArray = "uri";
    let mut calldata: Array<felt252> = array![];
    calldata.append_serde(uri.into());
    calldata.append_serde(c::OWNER());
    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

#[test]
fn test_set_project_value() {
    let (project_address, mut spy) = deploy_project(c::OWNER().into());
    let project = IAbsorberDispatcher { contract_address: project_address };
    project.set_project_value(PROJECT_VALUE.into());

    let fetched_value = project.get_project_value();
    assert(fetched_value == PROJECT_VALUE.into(), 'project_value not set correctly');

    spy
        .assert_emitted(
            @array![
                (
                    project_address,
                    AbsorberComponent::Event::ProjectValueUpdate(
                        AbsorberComponent::ProjectValueUpdate { value: PROJECT_VALUE.into() }
                    )
                )
            ]
        );
    // found events are removed from the spy after assertion
    assert(spy.events.len() == 0, 'number of events should be 0');
}

#[test]
fn test_get_project_value_not_set(){
    let (project_address, _) = deploy_project(c::OWNER().into());
    let project = IAbsorberDispatcher { contract_address: project_address };
    let fetched_value = project.get_project_value();
    assert(fetched_value == 0, 'initial project_value is not 0');
}

#[test]
fn test_set_project_value_twice() {
    let new_value: u256 = 100;
    let (project_address, mut spy) = deploy_project(c::OWNER().into());
    let project = IAbsorberDispatcher { contract_address: project_address };
    project.set_project_value(PROJECT_VALUE.into());

    let fetched_value = project.get_project_value();
    assert(fetched_value == PROJECT_VALUE.into(), 'project_value not set correctly');

    project.set_project_value(new_value.into());
    let fetched_value = project.get_project_value();
    assert(fetched_value == new_value, 'project_value didnt change');
}


#[test]
fn test_set_absorptions() {
    let (project_address, mut spy) = deploy_project(c::OWNER().into());
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
    ].span();
    let absorptions: Span<u64> = array![
        0, 1179750, 2359500, 3539250, 4719000, 6685250, 8651500, 1573000000
    ].span();

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
    // found events are removed from the spy after assertion
    assert(spy.events.len() == 0, 'number of events should be 0');

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
    let (project_address, _) = deploy_project(c::OWNER().into());
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();   // length 3
    let absorptions: Span<u64> = array![0, 1179750].span();                     // length 2
    project.set_absorptions(times, absorptions);
}

#[test]
#[should_panic(expected: ('Inputs cannot be empty',))]
fn test_set_absorptions_revert_empty_inputs() {
    let (project_address, _) = deploy_project(c::OWNER().into());
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![].span();
    let absorptions: Span<u64> = array![].span();
    project.set_absorptions(times, absorptions);
}

#[test]
#[should_panic(expected: ('Times not sorted',))]
fn test_set_absorptions_revert_times_not_sorted() {
    let (project_address, _) = deploy_project(c::OWNER().into());
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1657260800].span();   // not sorted
    let absorptions: Span<u64> = array![0, 1179750, 2359500].span();
    project.set_absorptions(times, absorptions);
}

#[test]
#[should_panic(expected: 'Absorptions not sorted',)]
fn test_set_absorptions_revert_absorptions_not_sorted() {
    let (project_address, _) = deploy_project(c::OWNER().into());
    let project = IAbsorberDispatcher { contract_address: project_address };
    let times: Span<u64> = array![1651363200, 1659312000, 1667260800].span();
    let absorptions: Span<u64> = array![0, 2359500, 1179750].span();   // not sorted
    project.set_absorptions(times, absorptions);
}