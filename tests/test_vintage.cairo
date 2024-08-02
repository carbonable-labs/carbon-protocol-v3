// Starknet deps

use starknet::{ContractAddress, contract_address_const};
use starknet::get_block_timestamp;

// External deps

use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, test_address, spy_events, EventSpy, start_cheat_caller_address,
    stop_cheat_caller_address
};

// Components

use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
use carbon_v3::components::vintage::VintageComponent::{Event};
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
    get_mock_absorptions, equals_with_error, deploy_project, setup_project,
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
    let project_address = deploy_project();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    start_cheat_caller_address(project_address, owner_address);
    vintages.set_project_carbon(PROJECT_CARBON);
    let fetched_value = vintages.get_project_carbon();
    assert(fetched_value == PROJECT_CARBON.into(), 'project_carbon wrong value');
}

#[test]
#[should_panic(expected: 'Caller does not have role')]
fn test_set_project_carbon_without_owner_role() {
    let project_address = deploy_project();
    let vintages = IVintageDispatcher { contract_address: project_address };
    vintages.set_project_carbon(PROJECT_CARBON.into());
}

#[test]
fn test_get_project_carbon_not_set() {
    let project_address = deploy_project();
    let vintages = IVintageDispatcher { contract_address: project_address };
    // [Assert] default project_carbon is 0
    let fetched_value = vintages.get_project_carbon();
    assert(fetched_value == 0, 'default project_carbon is not 0');
}

#[test]
fn test_set_project_carbon_twice() {
    let project_address = deploy_project();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    start_cheat_caller_address(project_address, owner_address);
    vintages.set_project_carbon(PROJECT_CARBON.into());
    let fetched_value = vintages.get_project_carbon();
    assert(fetched_value == PROJECT_CARBON.into(), 'project_carbon wrong value');
    let new_value: u128 = 100;
    vintages.set_project_carbon(new_value);
    let fetched_value = vintages.get_project_carbon();
    assert(fetched_value == new_value, 'project_carbon did not change');
}

/// set_vintages

fn test_set_vintages() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = deploy_project();
    let yearly_absorptions = get_mock_absorptions();
    start_cheat_caller_address(project_address, owner_address);

    let starting_year = 2024;
    let vintages = IVintageDispatcher { contract_address: project_address };
    vintages.set_vintages(yearly_absorptions, starting_year);

    let cc_vintages = vintages.get_cc_vintages();
    let mut index = 0;
    loop {
        if index == cc_vintages.len() {
            break;
        }
        let vintage = cc_vintages.at(index);
        let expected__cc_vintage = CarbonVintage {
            year: (starting_year + index.into()),
            supply: *yearly_absorptions.at(index),
            failed: 0,
            created: 0,
            status: CarbonVintageType::Projected,
        };
        assert(*vintage == expected__cc_vintage, 'vintage not set correctly');
        index += 1;
    };

    // [Assert] cc_vintages set to default values for non-set yearly_absorptions
    loop {
        if index == cc_vintages.len() {
            break;
        }
        let vintage = cc_vintages.at(index);
        let expected__cc_vintage: CarbonVintage = CarbonVintage {
            year: (starting_year.into() + index.into()),
            supply: 0,
            failed: 0,
            created: 0,
            status: CarbonVintageType::Unset,
        };
        assert(*vintage == expected__cc_vintage, 'vintage not set correctly');
        index += 1;
    }
}

#[test]
#[should_panic(expected: 'Caller does not have role')]
fn test_set_vintages_without_owner_role() {
    let project_address = deploy_project();
    let yearly_absorptions = get_mock_absorptions();
    let starting_year = 2024;
    let vintages = IVintageDispatcher { contract_address: project_address };
    vintages.set_vintages(yearly_absorptions, starting_year);
}

/// get_carbon_vintage

#[test]
fn test_get_carbon_vintage() {
    let project_address = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let cc_vintages = vintages.get_cc_vintages();
    let mut index = 0;
    loop {
        if index == cc_vintages.len() {
            break;
        }
        let token_id: u256 = index.into();
        let vintage = vintages.get_carbon_vintage(token_id);
        let expected_vintage = cc_vintages.at(index);
        assert(vintage == *expected_vintage, 'Vintage not fetched correctly');
        index += 1;
    };
}

/// get_initial_cc_supply
#[test]
fn test_get_initial_cc_supply() {
    let project_address = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    // initial supply should be equal to supply before any rebases
    let cc_vintages = vintages.get_cc_vintages();
    let mut index = 0;
    loop {
        if index == cc_vintages.len() {
            break;
        }
        let token_id: u256 = index.into();
        let vintage = vintages.get_carbon_vintage(token_id);
        let initial_supply = vintages.get_initial_cc_supply(token_id);
        assert(initial_supply == vintage.supply, 'Initial supply error');
        index += 1;
    };

    // Do one positive rebase and check if initial supply is correct
    let token_id: u256 = 1;
    let initial_supply = vintages.get_carbon_vintage(token_id).supply;
    let diff = 50000;
    let new_cc_supply: u256 = initial_supply + diff;
    vintages.rebase_vintage(token_id, new_cc_supply);
    let fetched_initial_supply = vintages.get_initial_cc_supply(token_id);
    assert(vintages.get_carbon_vintage(token_id).created == diff, 'Created field error');
    assert(fetched_initial_supply == initial_supply, 'Initial supply error');

    // Do one negative rebase and check if initial supply is correct
    let new_cc_supply: u256 = new_cc_supply - diff;
    vintages.rebase_vintage(token_id, new_cc_supply);
    let fetched_initial_supply = vintages.get_initial_cc_supply(token_id);
    assert(fetched_initial_supply == initial_supply, 'Initial supply error');
    let diff = initial_supply - new_cc_supply + vintages.get_carbon_vintage(token_id).created;
    assert(vintages.get_carbon_vintage(token_id).failed == diff, 'Failed field error');
}

#[test]
fn test_get_carbon_vintage_non_existent_token_id() {
    let project_address = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let token_id: u256 = 999.into(); // Assuming 999 does not exist

    let default_vintage: CarbonVintage = Default::default();

    let vintage = vintages.get_carbon_vintage(token_id);
    assert(vintage == default_vintage, 'Vintage should be default');
}

/// get_cc_decimals

#[test]
fn test_get_cc_decimals() {
    let project_address = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let cc_decimals = vintages.get_cc_decimals();
    assert(cc_decimals == 8, 'CC decimals should be 8');
}

/// update_vintage_status

#[test]
fn test_update_vintage_status_valid() {
    let project_address = default_setup_and_deploy();
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
    let project_address = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let token_id: u256 = 1;
    let invalid_status: u8 = 5; // Example invalid status
    vintages.update_vintage_status(token_id, invalid_status);
}

#[test]
#[should_panic(expected: 'Caller does not have role')]
fn test_update_vintage_status_without_owner_role() {
    let project_address = deploy_project();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let vintages = IVintageDispatcher { contract_address: project_address };

    let token_id: u256 = 1;
    let new_status: u8 = 2;
    start_cheat_caller_address(project_address, user_address);
    vintages.update_vintage_status(token_id, new_status);
}

// #[test]  todo, what do we expect here?
// fn test_update_vintage_status_non_existent_token_id() {
//     let project_address = default_setup_and_deploy();
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
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let project = IProjectDispatcher { contract_address: project_address };

    start_cheat_caller_address(project_address, owner_address);
    project.grant_minter_role(minter_address);
    start_cheat_caller_address(project_address, minter_address);

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
        // Rebase
        start_cheat_caller_address(project_address, owner_address);
        vintages.rebase_vintage(token_id, old_vintage_supply / 2);
        stop_cheat_caller_address(project_address);
        let new_vintage_supply = vintages.get_carbon_vintage(token_id).supply;
        let new_cc_balance = project.balance_of(owner_address, token_id);
        let failed_tokens = vintages.get_carbon_vintage(token_id).failed;
        assert(new_vintage_supply == old_vintage_supply / 2, 'rebase not correct');
        assert(new_cc_balance == old_cc_balance / 2, 'balance error after rebase');
        assert(failed_tokens == old_vintage_supply - new_vintage_supply, 'failed tokens not 0');
        index += 1;
    };
}

