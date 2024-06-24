// Starknet deps

use starknet::{ContractAddress, contract_address_const};

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

use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
use carbon_v3::components::vintage::{VintageComponent, VintageComponent::{ProjectCarbonUpdate}};
use carbon_v3::models::constants::CC_DECIMALS_MULTIPLIER;
use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};


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

// set_project_carbon
// To rename: set_vintage ? vintages should be set in the constructor
// #[test]
fn test_set_project_carbon() { // let (project_address, mut spy) = deploy_project();
// let project = IVintageDispatcher { contract_address: project_address };
// // [Assert] project_carbon set correctly
// project.set_project_carbon(PROJECT_CARBON.into());
// let fetched_value = project.get_project_carbon();
// assert(fetched_value == PROJECT_CARBON.into(), 'project_carbon wrong value');
// spy
//     .assert_emitted(
//         @array![
//             (
//                 project_address,
//                 AbsorberComponent::Event::ProjectValueUpdate(
//                     AbsorberComponent::ProjectValueUpdate { value: PROJECT_CARBON.into() }
//                 )
//             )
//         ]
//     );
// // found events are removed from the spy after assertion, so the length should be 0
// assert(spy.events.len() == 0, 'number of events should be 0');
}

#[test]
fn test_get_project_carbon_not_set() {
    let (project_address, _) = deploy_project();
    let project = IVintageDispatcher { contract_address: project_address };
    // [Assert] default project_carbon is 0
    let fetched_value = project.get_project_carbon();
    assert(fetched_value == 0, 'default project_carbon is not 0');
}

// #[test]
// fn test_set_project_carbon_twice() { // TODO: check if needed
// let (project_address, _) = deploy_project();
// let project = IVintageDispatcher { contract_address: project_address };
// // [Assert] project_carbon set correctly
// project.set_project_carbon(PROJECT_CARBON.into());
// let fetched_value = project.get_project_carbon();
// assert(fetched_value == PROJECT_CARBON.into(), 'project_carbon wrong value');
// // [Assert] project_carbon updated correctly
// let new_value: u256 = 100;
// project.set_project_carbon(new_value.into());
// let fetched_value = project.get_project_carbon();
// assert(fetched_value == new_value, 'project_carbon did not change');
// }

// get_cc_vintages

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
//     let starting_year = 2024;
//     let mut index = 0;

//     let vintage = cc_vintages.at(index);
//     let expected__cc_vintage = CarbonVintage {
//         vintage: (starting_year + index).into(),
//         supply: 0, //*absorptions.at(index),
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
//             vintage: (starting_year + index).into(),
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
//         let expected__cc_vintage = CarbonVintage {
//             vintage: (starting_year + index).into(),
//             supply: 0,
//             failed: 0,
//             status: CarbonVintageType::Projected,
//         };

//         assert(*vintage == expected__cc_vintage, 'vintage not set correctly');
//         index += 1;
//     }
// }

#[test]
fn test_rebase_half_supply() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let project = IProjectDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);
    start_prank(CheatTarget::One(project_address), owner_address);
    let share = 50 * CC_DECIMALS_MULTIPLIER / 100; // 50%

    buy_utils(minter_address, erc20_address, share);

    let n = vintages.get_num_vintages();

    // Rebase every vintage with half the supply
    let mut index = 0;
    loop {
        if index == n {
            break;
        }
        let token_id: u256 = index.into() + 1;
        let vintage_before = vintages.get_carbon_vintage(token_id);
        let owner_balance_before = project.balance_of(owner_address, token_id);
        // rebase
        vintages.rebase_vintage(token_id, vintage_before.supply / 2);
        let vintage_after = vintages.get_carbon_vintage(token_id);
        let owner_balance_after = project.balance_of(owner_address, token_id);
        let expected_failed = vintage_before.supply - vintage_after.supply / 2;
        assert(vintage_after.supply == vintage_before.supply / 2, 'incorrect rebase');
        assert(owner_balance_after == owner_balance_before / 2, 'balance error after rebase');
        assert(vintage_after.failed == expected_failed, 'failed tokens not 0');
        index += 1;
    };
}
