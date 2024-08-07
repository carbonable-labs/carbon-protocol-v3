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

use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, test_address, spy_events, EventSpy, start_cheat_caller_address,
    stop_cheat_caller_address
};
// Components

use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
use carbon_v3::components::vintage::vintage::VintageComponent::{Event};
use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
use carbon_v3::components::vintage::VintageComponent;
use carbon_v3::components::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
use carbon_v3::components::offsetter::interface::{
    IOffsetHandlerDispatcher, IOffsetHandlerDispatcherTrait
};

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};
use carbon_v3::contracts::minter::Minter;
use carbon_v3::mock::usdcarb::USDCarb;

// Utils for testing purposes

use super::tests_lib::{
    default_setup_and_deploy, buy_utils, deploy_offsetter, deploy_erc20, deploy_minter
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

#[test]
fn test_offsetter_init() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    start_cheat_caller_address(offsetter_address, user_address);
    let token_id: u256 = 1;
    let carbon_pending = offsetter.get_carbon_retired(token_id);
    assert(carbon_pending == 0, 'carbon pending should be 0');

    let carbon_retired = offsetter.get_carbon_retired(token_id);
    assert(carbon_retired == 0, 'carbon retired should be 0');
}

// test_offsetter_retire_carbon_credits

#[test]
fn test_offsetter_retire_carbon_credits() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    let initial_balance = project.balance_of(user_address, token_id);

    let amount_to_offset = initial_balance / 2;

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, offsetter_address);
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_carbon_credits(token_id, amount_to_offset);
    // project.safe_transfer_from(user_address, offsetter_address, token_id, amount_to_offset, array![].span());

    let carbon_retired = offsetter.get_carbon_retired(token_id);
    assert(carbon_retired == amount_to_offset, 'Carbon retired is wrong');

    let final_balance = project.balance_of(user_address, token_id);
    assert(final_balance == initial_balance - amount_to_offset, 'Balance is wrong');
}

#[test]
#[should_panic(expected: 'Vintage status is not audited')]
fn test_offsetter_wrong_status() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    let vintages = IVintageDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let token_id: u256 = 1;
    let status = vintages.get_carbon_vintage(token_id).status;
    assert(status != CarbonVintageType::Audited.into(), 'Vintage status error');

    // [Effect] try to retire carbon credits
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_carbon_credits(token_id, 1000000);
}

#[test]
#[should_panic(expected: 'Not own enough carbon credits')]
fn test_retire_carbon_credits_insufficient_credits() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    project_contract.grant_offsetter_role(offsetter_address);

    stop_cheat_caller_address(project_address);
    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);

    start_cheat_caller_address(project_address, owner_address);
    let token_id: u256 = 1;
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());
    stop_cheat_caller_address(project_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    let user_balance = project_contract.balance_of(user_address, token_id);
    offsetter.retire_carbon_credits(token_id, user_balance + 1);
}

#[test]
fn test_retire_carbon_credits_exact_balance() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    project_contract.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    let token_id: u256 = 1;
    let user_balance = project_contract.balance_of(user_address, token_id);

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());
    stop_cheat_caller_address(project_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_carbon_credits(token_id, user_balance);

    let carbon_retired = offsetter.get_carbon_retired(token_id);
    assert(carbon_retired == user_balance, 'Carbon retired is wrong');

    let user_balance_after = project_contract.balance_of(user_address, token_id);
    assert(user_balance_after == 0, 'Balance is wrong');
}

#[test]
fn test_retire_carbon_credits_multiple_retirements() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    let token_id: u256 = 1;
    let balance_initial = project.balance_of(user_address, token_id);

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());
    stop_cheat_caller_address(project_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_carbon_credits(token_id, 50000);
    offsetter.retire_carbon_credits(token_id, 50000);

    let carbon_retired = offsetter.get_carbon_retired(token_id);
    assert(carbon_retired == 100000, 'Error retired carbon credits');

    let balance_final = project.balance_of(user_address, token_id);
    assert(balance_final == balance_initial - 100000, 'Error balance');
}

/// retire_list_carbon_credits

#[test]
fn test_retire_list_carbon_credits_valid_inputs() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    let vintage_2024_id: u256 = 1;
    let vintage_2026_id: u256 = 3;
    let balance_initial_token_id = project.balance_of(user_address, vintage_2024_id);
    let balance_initial_2026 = project.balance_of(user_address, vintage_2026_id);

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(vintage_2024_id, CarbonVintageType::Audited.into());
    vintages.update_vintage_status(vintage_2026_id, CarbonVintageType::Audited.into());
    stop_cheat_caller_address(project_address);

    let vintages: Span<u256> = array![vintage_2024_id, vintage_2026_id].span();
    let carbon_values: Span<u256> = array![50000.into(), 50000.into()].span();
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_list_carbon_credits(vintages, carbon_values);

    let carbon_retired_token_id = offsetter.get_carbon_retired(vintage_2024_id);
    let carbon_retired_2026 = offsetter.get_carbon_retired(vintage_2026_id);
    assert(carbon_retired_token_id == 50000, 'Carbon retired value error');
    assert(carbon_retired_2026 == 50000, 'Carbon retired value error');

    let balance_final_token_id = project.balance_of(user_address, vintage_2024_id);
    let balance_final_2026 = project.balance_of(user_address, vintage_2026_id);
    assert(balance_final_token_id == balance_initial_token_id - 50000, 'Balance error');
    assert(balance_final_2026 == balance_initial_2026 - 50000, 'Balance error');
}

#[test]
#[should_panic(expected: 'Inputs cannot be empty')]
fn test_retire_list_carbon_credits_empty_inputs() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    start_cheat_caller_address(offsetter_address, user_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_list_carbon_credits(array![].span(), array![].span());
}

#[test]
#[should_panic(expected: 'Vintages and Values mismatch')]
fn test_retire_list_carbon_credits_mismatched_lengths() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(offsetter_address, user_address);

    let vintages: Span<u256> = array![token_id, token_id + 1].span();
    let carbon_values: Span<u256> = array![100000].span();
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_list_carbon_credits(vintages, carbon_values);
}

#[test]
#[should_panic(expected: 'Vintage status is not audited')]
fn test_retire_list_carbon_credits_partial_valid_inputs() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);

    start_cheat_caller_address(project_address, owner_address);
    let token_id: u256 = 1;
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());
    stop_cheat_caller_address(project_address);
    // Do not update 2026 to keep it invalid

    let vintages: Span<u256> = array![token_id, token_id + 1].span();
    let carbon_values: Span<u256> = array![50000.into(), 50000.into()].span();
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_list_carbon_credits(vintages, carbon_values);
}

#[test]
fn test_retire_list_carbon_credits_multiple_same_vintage() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    let token_id: u256 = 1;
    let initial_balance = project.balance_of(user_address, token_id);

    start_cheat_caller_address(project_address, owner_address);
    let token_id: u256 = 1;
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());
    stop_cheat_caller_address(project_address);

    let vintages: Span<u256> = array![token_id, token_id].span();
    let carbon_values: Span<u256> = array![50000.into(), 50000.into()].span();
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_list_carbon_credits(vintages, carbon_values);

    let carbon_retired = offsetter.get_carbon_retired(token_id);
    assert(carbon_retired == 100000, 'Error Carbon retired');

    let balance_final = project.balance_of(user_address, token_id);
    assert(balance_final == initial_balance - 100000, 'Error balance');
}
/// get_pending_retirement

#[test]
fn test_get_pending_retirement_no_pending() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    start_cheat_caller_address(offsetter_address, user_address);
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    let token_id: u256 = 1;

    // [Assert] No pending retirement should be zero
    let pending_retirement = offsetter.get_pending_retirement(token_id);
    assert(pending_retirement == 0.into(), 'Error pending retirement');
}

/// get_carbon_retired

#[test]
fn test_get_carbon_retired_no_retired() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    start_cheat_caller_address(offsetter_address, user_address);
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    let token_id: u256 = 1;

    let carbon_retired = offsetter.get_carbon_retired(token_id);
    assert(carbon_retired == 0.into(), 'Error about carbon retired');
}

