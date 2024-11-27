// Starknet deps

use starknet::{ContractAddress, contract_address_const};

// External deps

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, test_address, spy_events, EventSpy, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use snforge_std::cheatcodes::events::{EventsFilterTrait, EventSpyTrait, EventSpyAssertionsTrait};

// Components

use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
use carbon_v3::models::carbon_vintage::CarbonVintageType;
use carbon_v3::components::vintage::VintageComponent;
use carbon_v3::components::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
use carbon_v3::components::offsetter::interface::{
    IOffsetHandlerDispatcher, IOffsetHandlerDispatcherTrait
};
use carbon_v3::components::offsetter::OffsetComponent;
// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};
use carbon_v3::contracts::minter::Minter;
use carbon_v3::mock::usdcarb::USDCarb;

// Utils for testing purposes

use super::tests_lib::{
    default_setup_and_deploy, buy_utils, deploy_offsetter, deploy_erc20, deploy_minter,
    helper_expected_transfer_event
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
    offsetter: ContractAddress,
}


/// Utils to import mock data
use super::tests_lib::{
    MERKLE_ROOT_FIRST_WAVE, MERKLE_ROOT_SECOND_WAVE, get_bob_first_wave_allocation,
    get_bob_second_wave_allocation, get_alice_second_wave_allocation, get_john_multiple_allocations
};

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
    let carbon_pending = offsetter.get_pending_retirement(user_address, token_id);
    assert(carbon_pending == 0, 'carbon pending should be 0');

    let carbon_retired = offsetter.get_carbon_retired(user_address, token_id);
    assert(carbon_retired == 0, 'carbon retired should be 0');
}

// test_offsetter_deposit_vintage

#[test]
fn test_offsetter_deposit_vintage() {
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

    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    let mut spy = spy_events();
    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintage(token_id, amount_to_offset);

    let expected_event = helper_expected_transfer_event(
        project_address,
        offsetter_address,
        user_address,
        offsetter_address,
        array![token_id].span(),
        amount_to_offset
    );

    spy.assert_emitted(@array![(project_address, expected_event)]);

    let carbon_pending = offsetter.get_pending_retirement(user_address, token_id);
    assert(carbon_pending == amount_to_offset, 'Carbon pending is wrong');
    let final_balance = project.balance_of(user_address, token_id);
    assert(final_balance == initial_balance - amount_to_offset, 'Balance is wrong');
}

#[test]
#[should_panic(expected: 'Offset: Invalid vintage')]
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
    offsetter.deposit_vintage(token_id, 1000000);
}

#[test]
#[should_panic(expected: 'Offset: Not enough carbon')]
fn test_deposit_vintage_insufficient_credits() {
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
    offsetter.deposit_vintage(token_id, user_balance + 1);
}

#[test]
fn test_deposit_vintage_exact_balance() {
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
    start_cheat_caller_address(project_address, user_address);
    project_contract.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintage(token_id, user_balance);

    let carbon_pending = offsetter.get_pending_retirement(user_address, token_id);
    assert(carbon_pending == user_balance, 'Carbon pending is wrong');

    let user_balance_after = project_contract.balance_of(user_address, token_id);
    assert(user_balance_after == 0, 'Balance is wrong');
}

#[test]
fn test_deposit_vintage_multiple_retirements() {
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
    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintage(token_id, 50000);
    offsetter.deposit_vintage(token_id, 50000);

    let carbon_pending = offsetter.get_pending_retirement(user_address, token_id);
    assert(carbon_pending == 100000, 'Error pending carbon credits');

    let balance_final = project.balance_of(user_address, token_id);
    assert(balance_final == balance_initial - 100000, 'Error balance');
}

/// deposit_vintages

#[test]
fn test_deposit_vintages_valid_inputs() {
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
    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintages(vintages, carbon_values);

    let carbon_pending_token_id = offsetter.get_pending_retirement(user_address, vintage_2024_id);
    let carbon_pending_2026 = offsetter.get_pending_retirement(user_address, vintage_2026_id);
    assert(carbon_pending_token_id == 50000, 'Carbon pending value error');
    assert(carbon_pending_2026 == 50000, 'Carbon pending value error');

    let balance_final_token_id = project.balance_of(user_address, vintage_2024_id);
    let balance_final_2026 = project.balance_of(user_address, vintage_2026_id);
    assert(balance_final_token_id == balance_initial_token_id - 50000, 'Balance error');
    assert(balance_final_2026 == balance_initial_2026 - 50000, 'Balance error');
}

#[test]
#[should_panic(expected: 'Offset: Inputs cannot be empty')]
fn test_deposit_vintages_empty_inputs() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    start_cheat_caller_address(offsetter_address, user_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.deposit_vintages(array![].span(), array![].span());
}

#[test]
#[should_panic(expected: 'Offset: Array length mismatch')]
fn test_deposit_vintages_mismatched_lengths() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(offsetter_address, user_address);

    let vintages: Span<u256> = array![token_id, token_id + 1].span();
    let carbon_values: Span<u256> = array![100000].span();
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.deposit_vintages(vintages, carbon_values);
}

#[test]
#[should_panic(expected: 'Offset: Invalid vintage')]
fn test_deposit_vintages_partial_valid_inputs() {
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

    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintages(vintages, carbon_values);
}

#[test]
fn test_deposit_vintages_multiple_same_vintage() {
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
    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(offsetter_address, user_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintages(vintages, carbon_values);

    let carbon_pending = offsetter.get_pending_retirement(user_address, token_id);
    assert(carbon_pending == 100000, 'Error Carbon pending');

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
    let pending_retirement = offsetter.get_pending_retirement(user_address, token_id);
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

    let carbon_retired = offsetter.get_carbon_retired(user_address, token_id);
    assert(carbon_retired == 0.into(), 'Error about carbon retired');
}


/// confirm_offset

#[test]
fn test_confirm_offset() {
    /// Test a simple confirm offset scenario where Bob claims his retirement from the first wave.
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();

    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, bob_address, minter_address, cc_to_mint);
    let initial_balance = project.balance_of(bob_address, token_id);

    let amount_to_offset: u256 = amount.into();

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());

    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, offsetter_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    offsetter.set_merkle_root(root);

    start_cheat_caller_address(project_address, bob_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    let mut spy = spy_events();
    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintage(token_id, amount_to_offset);

    let expected_event = helper_expected_transfer_event(
        project_address,
        offsetter_address,
        bob_address,
        offsetter_address,
        array![token_id].span(),
        amount_to_offset
    );

    spy.assert_emitted(@array![(project_address, expected_event)]);

    let carbon_pending = offsetter.get_pending_retirement(bob_address, token_id);
    assert(carbon_pending == amount_to_offset, 'Carbon pending is wrong');
    let final_balance = project.balance_of(bob_address, token_id);
    assert(final_balance == initial_balance - amount_to_offset, 'Balance is wrong');

    let current_retirement = offsetter.get_retirement(token_id, bob_address);
    let new_retirement = current_retirement + amount.clone().into();

    assert!(!offsetter.check_claimed(bob_address, timestamp, amount, id));
    offsetter.confirm_offset(amount, timestamp, id, proof);
    assert!(offsetter.check_claimed(bob_address, timestamp, amount, id));

    assert!(offsetter.get_retirement(token_id, bob_address) == new_retirement)
}

#[test]
#[should_panic(expected: 'Offset: Already claimed')]
fn test_bob_confirms_twice() {
    /// Test that Bob trying to confirm the same offset twice, results in a panic.
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();

    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, bob_address, minter_address, cc_to_mint);
    let initial_balance = project.balance_of(bob_address, token_id);

    let amount_to_offset: u256 = amount.into();

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());

    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, offsetter_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    offsetter.set_merkle_root(root);

    start_cheat_caller_address(project_address, bob_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    let mut spy = spy_events();
    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintage(token_id, amount_to_offset);

    let expected_event = helper_expected_transfer_event(
        project_address,
        offsetter_address,
        bob_address,
        offsetter_address,
        array![token_id].span(),
        amount_to_offset
    );

    spy.assert_emitted(@array![(project_address, expected_event)]);

    let carbon_pending = offsetter.get_pending_retirement(bob_address, token_id);
    assert(carbon_pending == amount_to_offset, 'Carbon pending is wrong');
    let final_balance = project.balance_of(bob_address, token_id);
    assert(final_balance == initial_balance - amount_to_offset, 'Balance is wrong');

    offsetter.confirm_offset(amount, timestamp, id, proof.clone());
    assert!(offsetter.check_claimed(bob_address, timestamp, amount, id));

    offsetter.confirm_offset(amount, timestamp, id, proof);
}


#[test]
fn test_events_emission_on_claim_confirmation() {
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();

    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, bob_address, minter_address, cc_to_mint);
    let initial_balance = project.balance_of(bob_address, token_id);

    let amount_to_offset: u256 = amount.into();

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());

    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, offsetter_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    offsetter.set_merkle_root(root);

    start_cheat_caller_address(project_address, bob_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    let mut spy = spy_events();
    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintage(token_id, amount_to_offset);

    let expected_event = helper_expected_transfer_event(
        project_address,
        offsetter_address,
        bob_address,
        offsetter_address,
        array![token_id].span(),
        amount_to_offset
    );

    spy.assert_emitted(@array![(project_address, expected_event)]);

    let carbon_pending = offsetter.get_pending_retirement(bob_address, token_id);
    assert(carbon_pending == amount_to_offset, 'Carbon pending is wrong');
    let final_balance = project.balance_of(bob_address, token_id);
    assert(final_balance == initial_balance - amount_to_offset, 'Balance is wrong');

    let current_retirement = offsetter.get_retirement(token_id, bob_address);
    let new_retirement = current_retirement + amount.clone().into();

    let mut spy = spy_events();
    offsetter.confirm_offset(amount, timestamp, id, proof);

    let first_expected_event = OffsetComponent::Event::Retired(
        OffsetComponent::Retired {
            from: bob_address,
            project: project_address,
            token_id: token_id,
            old_amount: current_retirement,
            new_amount: new_retirement
        }
    );

    let second_expected_event = OffsetComponent::Event::AllocationClaimed(
        OffsetComponent::AllocationClaimed { claimee: bob_address, amount, timestamp, id }
    );

    spy
        .assert_emitted(
            @array![
                (offsetter_address, first_expected_event),
                (offsetter_address, second_expected_event)
            ]
        );

    assert!(offsetter.check_claimed(bob_address, timestamp, amount, id));
}


#[test]
#[should_panic(expected: 'Offset: Invalid proof')]
fn test_claim_confirmation_with_invalid_amount() {
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();

    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, bob_address, minter_address, cc_to_mint);
    let initial_balance = project.balance_of(bob_address, token_id);

    let amount_to_offset: u256 = amount.into();

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());

    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, offsetter_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    offsetter.set_merkle_root(root);

    start_cheat_caller_address(project_address, bob_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    let mut spy = spy_events();
    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintage(token_id, amount_to_offset);

    let expected_event = helper_expected_transfer_event(
        project_address,
        offsetter_address,
        bob_address,
        offsetter_address,
        array![token_id].span(),
        amount_to_offset
    );

    spy.assert_emitted(@array![(project_address, expected_event)]);

    let carbon_pending = offsetter.get_pending_retirement(bob_address, token_id);
    assert(carbon_pending == amount_to_offset, 'Carbon pending is wrong');
    let final_balance = project.balance_of(bob_address, token_id);
    assert(final_balance == initial_balance - amount_to_offset, 'Balance is wrong');

    let invalid_amount = 0;

    offsetter.confirm_offset(invalid_amount, timestamp, id, proof);
}

#[test]
fn test_alice_confirms_in_second_wave() {
    /// Test that Bob can confirm his offset from the first wave and Alice can confirm her offset
    /// from the second wave.
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();

    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, bob_address, minter_address, cc_to_mint);
    let initial_balance = project.balance_of(bob_address, token_id);

    let amount_to_offset: u256 = amount.into();

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());

    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, offsetter_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    offsetter.set_merkle_root(root);

    start_cheat_caller_address(project_address, bob_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    let mut spy = spy_events();
    start_cheat_caller_address(offsetter_address, bob_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintage(token_id, amount_to_offset);

    let expected_event = helper_expected_transfer_event(
        project_address,
        offsetter_address,
        bob_address,
        offsetter_address,
        array![token_id].span(),
        amount_to_offset
    );

    spy.assert_emitted(@array![(project_address, expected_event)]);

    let carbon_pending = offsetter.get_pending_retirement(bob_address, token_id);
    assert(carbon_pending == amount_to_offset, 'Carbon pending is wrong');
    let final_balance = project.balance_of(bob_address, token_id);
    assert(final_balance == initial_balance - amount_to_offset, 'Balance is wrong');

    let current_retirement = offsetter.get_retirement(token_id, bob_address);
    let new_retirement = current_retirement + amount.clone().into();

    assert!(!offsetter.check_claimed(bob_address, timestamp, amount, id));
    offsetter.confirm_offset(amount, timestamp, id, proof);
    assert!(offsetter.check_claimed(bob_address, timestamp, amount, id));

    assert!(offsetter.get_retirement(token_id, bob_address) == new_retirement);

    stop_cheat_caller_address(erc20_address);
    stop_cheat_caller_address(project_address);

    let (new_root, alice_address, amount, timestamp, id, proof) =
        get_alice_second_wave_allocation();

    start_cheat_caller_address(offsetter_address, alice_address);
    start_cheat_caller_address(project_address, owner_address);

    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, alice_address, minter_address, cc_to_mint);
    let initial_balance = project.balance_of(alice_address, token_id);

    let amount_to_offset: u256 = amount.into();

    start_cheat_caller_address(offsetter_address, alice_address);
    start_cheat_caller_address(project_address, offsetter_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    offsetter.set_merkle_root(new_root);

    start_cheat_caller_address(project_address, alice_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    let mut spy = spy_events();
    start_cheat_caller_address(offsetter_address, alice_address);
    start_cheat_caller_address(project_address, offsetter_address);
    offsetter.deposit_vintage(token_id, amount_to_offset);

    let expected_event = helper_expected_transfer_event(
        project_address,
        offsetter_address,
        alice_address,
        offsetter_address,
        array![token_id].span(),
        amount_to_offset
    );

    spy.assert_emitted(@array![(project_address, expected_event)]);

    let carbon_pending = offsetter.get_pending_retirement(alice_address, token_id);
    assert(carbon_pending == amount_to_offset, 'Carbon pending is wrong');
    let final_balance = project.balance_of(alice_address, token_id);
    assert(final_balance == initial_balance - amount_to_offset, 'Balance is wrong');

    let current_retirement = offsetter.get_retirement(token_id, alice_address);
    let new_retirement = current_retirement + amount.clone().into();

    assert!(!offsetter.check_claimed(alice_address, timestamp, amount, id));
    offsetter.confirm_offset(amount, timestamp, id, proof);
    assert!(offsetter.check_claimed(alice_address, timestamp, amount, id));

    assert!(offsetter.get_retirement(token_id, alice_address) == new_retirement);
}

#[test]
fn test_john_confirms_multiple_allocations() {
    /// Test that John can two of his three offset from the first allocations wave, and the
    /// remaining one from the second wave.
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    let (
        root,
        new_root,
        john_address,
        amount1,
        timestamp1,
        id_1,
        amount2,
        timestamp2,
        id_2,
        _,
        _,
        _,
        amount4,
        timestamp4,
        id_4,
        proof1,
        proof2,
        _,
        proof4
    ) =
        get_john_multiple_allocations();

    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(offsetter_address, john_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, john_address, minter_address, cc_to_mint);

    let amount1_to_offset: u256 = amount1.into();
    let amount2_to_offset: u256 = amount2.into();
    let amount4_to_offset: u256 = amount4.into();

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());

    start_cheat_caller_address(offsetter_address, john_address);
    start_cheat_caller_address(project_address, offsetter_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    offsetter.set_merkle_root(root);

    start_cheat_caller_address(project_address, john_address);
    project.set_approval_for_all(offsetter_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(offsetter_address, john_address);
    start_cheat_caller_address(project_address, offsetter_address);

    offsetter.deposit_vintage(token_id, amount1_to_offset);
    assert!(!offsetter.check_claimed(john_address, timestamp1, amount1, id_1));
    offsetter.confirm_offset(amount1, timestamp1, id_1, proof1);

    offsetter.deposit_vintage(token_id, amount2_to_offset);
    assert!(!offsetter.check_claimed(john_address, timestamp2, amount2, id_2));
    offsetter.confirm_offset(amount2, timestamp2, id_2, proof2);

    assert!(offsetter.check_claimed(john_address, timestamp1, amount1, id_1));
    assert!(offsetter.check_claimed(john_address, timestamp2, amount2, id_2));

    start_cheat_caller_address(offsetter_address, owner_address);
    offsetter.set_merkle_root(new_root);

    start_cheat_caller_address(offsetter_address, john_address);
    start_cheat_caller_address(project_address, offsetter_address);

    offsetter.deposit_vintage(token_id, amount4_to_offset);
    assert!(!offsetter.check_claimed(john_address, timestamp4, amount4, id_4));
    offsetter.confirm_offset(amount4, timestamp4, id_4, proof4);

    assert!(offsetter.check_claimed(john_address, timestamp4, amount4, id_4));
}
