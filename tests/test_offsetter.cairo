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
use carbon_v3::components::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
use carbon_v3::components::offsetter::interface::{IOffsetHandlerDispatcher, IOffsetHandlerDispatcherTrait};

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
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    // [Assert] contract is empty
    start_prank(CheatTarget::One(offsetter_address), owner_address);
    let carbon_pending = offsetter.get_carbon_retired(2025);
    assert(carbon_pending == 0, 'carbon pending should be 0');

    let carbon_retired = offsetter.get_carbon_retired(2025);
    assert(carbon_retired == 0, 'carbon retired should be 0');
}

// test_offsetter_retire_carbon_credits

#[test]
fn test_offsetter_retire_carbon_credits() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(offsetter_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let project = IProjectDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    let share: u256 = 10 * CC_DECIMALS_MULTIPLIER / 100; // 10%
    buy_utils(minter_address, erc20_address, share);
    let initial_balance = project.balance_of(owner_address, 2025);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());

    // [Effect] try to retire carbon credits
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_carbon_credits(2025, 100000);

    let carbon_retired = offsetter.get_carbon_retired(2025);
    assert(carbon_retired == 100000, 'Carbon retired is wrong');

    let final_balance = project.balance_of(owner_address, 2025);
    assert(final_balance == initial_balance - 100000, 'Balance is wrong');
}

#[test]
#[should_panic(expected: 'Vintage status is not audited')]
fn test_offsetter_wrong_status() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(offsetter_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let share = 33 * CC_DECIMALS_MULTIPLIER / 100; // 33%
    buy_utils(minter_address, erc20_address, share);

    // [Check] Vintage status is not audited
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let status = cc_handler.get_carbon_vintage(2025).status;
    assert(status != CarbonVintageType::Audited.into(), 'Vintage status error');

    // [Effect] try to retire carbon credits
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_carbon_credits(2025, 1000000);
}

#[test]
#[should_panic(expected: 'Not own enough carbon credits')]
fn test_retire_carbon_credits_insufficient_credits() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(offsetter_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let share = 33 * CC_DECIMALS_MULTIPLIER / 100;
    buy_utils(minter_address, erc20_address, share);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());

    // [Effect] try to retire carbon credits
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    let balance_owner = project_contract.balance_of(owner_address, 2025);
    offsetter.retire_carbon_credits(2025, balance_owner + 1);
}

#[test]
fn test_retire_carbon_credits_exact_balance() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(offsetter_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let share = 33 * CC_DECIMALS_MULTIPLIER / 100;
    buy_utils(minter_address, erc20_address, share);
    let balance_owner = project_contract.balance_of(owner_address, 2025);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());

    // [Effect] try to retire carbon credits
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_carbon_credits(2025, balance_owner);

    let carbon_retired = offsetter.get_carbon_retired(2025);
    assert(carbon_retired == balance_owner, 'Carbon retired is wrong');

    let balance_owner_after = project_contract.balance_of(owner_address, 2025);
    assert(balance_owner_after == 0, 'Balance is wrong');
}

#[test]
fn test_retire_carbon_credits_multiple_retirements() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(offsetter_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project = IProjectDispatcher { contract_address: project_address };

    let share: u256 = 10 * CC_DECIMALS_MULTIPLIER / 100; // 10%
    buy_utils(minter_address, erc20_address, share);
    let balance_initial = project.balance_of(owner_address, 2025);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());

    // [Effect] retire carbon credits multiple times
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_carbon_credits(2025, 50000);
    offsetter.retire_carbon_credits(2025, 50000);

    // [Assert] check retired carbon credits
    let carbon_retired = offsetter.get_carbon_retired(2025);
    assert(carbon_retired == 100000, 'Error retired carbon credits');

    let balance_final = project.balance_of(owner_address, 2025);
    assert(balance_final == balance_initial - 100000, 'Error balance');
}

/// retire_list_carbon_credits

#[test]
fn test_retire_list_carbon_credits_valid_inputs() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(offsetter_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project = IProjectDispatcher { contract_address: project_address };

    let share: u256 = 10 * CC_DECIMALS_MULTIPLIER / 100; // 10%
    buy_utils(minter_address, erc20_address, share);
    let balance_initial_2025 = project.balance_of(owner_address, 2025);
    let balance_initial_2026 = project.balance_of(owner_address, 2026);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());
    carbon_credits.update_vintage_status(2026, CarbonVintageType::Audited.into());

    // [Effect] retire list of carbon credits
    let vintages: Span<u256> = array![2025.into(), 2026.into()].span();
    let carbon_values: Span<u256> = array![50000.into(), 50000.into()].span();
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_list_carbon_credits(vintages, carbon_values);

    // [Assert] check retired carbon credits
    let carbon_retired_2025 = offsetter.get_carbon_retired(2025.into());
    let carbon_retired_2026 = offsetter.get_carbon_retired(2026.into());
    assert(carbon_retired_2025 == 50000, 'Carbon retired value error');
    assert(carbon_retired_2026 == 50000, 'Carbon retired value error');

    let balance_final_2025 = project.balance_of(owner_address, 2025);
    let balance_final_2026 = project.balance_of(owner_address, 2026);
    assert(balance_final_2025 == balance_initial_2025 - 50000, 'Balance error');
    assert(balance_final_2026 == balance_initial_2026 - 50000, 'Balance error');
}

#[test]
#[should_panic(expected: ('Inputs cannot be empty',))]
fn test_retire_list_carbon_credits_empty_inputs() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(offsetter_address), owner_address);

    // [Effect] try to retire with empty inputs
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_list_carbon_credits(array![].span(), array![].span());
}

#[test]
#[should_panic(expected: 'Vintages and Values mismatch')]
fn test_retire_list_carbon_credits_mismatched_lengths() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(offsetter_address), owner_address);

    // [Effect] try to retire with mismatched lengths
    let vintages: Span<u256> = array![2025, 2026].span();
    let carbon_values: Span<u256> = array![100000].span();
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_list_carbon_credits(vintages, carbon_values);
}

#[test]
#[should_panic(expected: ('Vintage status is not audited',))]
fn test_retire_list_carbon_credits_partial_valid_inputs() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(offsetter_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let share: u256 = 10 * CC_DECIMALS_MULTIPLIER / 100; // 10%
    buy_utils(minter_address, erc20_address, share);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());
    // Do not update 2026 to keep it invalid

    // [Effect] retire list of carbon credits
    let vintages: Span<u256> = array![2025.into(), 2026.into()].span();
    let carbon_values: Span<u256> = array![50000.into(), 50000.into()].span();
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_list_carbon_credits(vintages, carbon_values);
}

#[test]
fn test_retire_list_carbon_credits_multiple_same_vintage() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(offsetter_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project = IProjectDispatcher { contract_address: project_address };

    let share: u256 = 10 * CC_DECIMALS_MULTIPLIER / 100; // 10%
    buy_utils(minter_address, erc20_address, share);
    let initial_balance = project.balance_of(owner_address, 2025);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());

    // [Effect] retire list of carbon credits with multiple same vintage
    let vintages: Span<u256> = array![2025.into(), 2025.into()].span();
    let carbon_values: Span<u256> = array![50000.into(), 50000.into()].span();
    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    offsetter.retire_list_carbon_credits(vintages, carbon_values);

    // [Assert] check retired carbon credits
    let carbon_retired = offsetter.get_carbon_retired(2025.into());
    assert(carbon_retired == 100000, 'Error Carbon retired');

    let balance_final = project.balance_of(owner_address, 2025);
    assert(balance_final == initial_balance - 100000, 'Error balance');
}
/// get_pending_retirement

#[test]
fn test_get_pending_retirement_no_pending() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(offsetter_address), owner_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    let vintage: u256 = 2025.into();

    // [Assert] No pending retirement should be zero
    let pending_retirement = offsetter.get_pending_retirement(vintage);
    assert(pending_retirement == 0.into(), 'Error pending retirement');
}

/// get_carbon_retired

#[test]
fn test_get_carbon_retired_no_retired() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (offsetter_address, _) = deploy_offsetter(project_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(offsetter_address), owner_address);

    let offsetter = IOffsetHandlerDispatcher { contract_address: offsetter_address };
    let vintage: u256 = 2025.into();

    let carbon_retired = offsetter.get_carbon_retired(vintage);
    assert(carbon_retired == 0.into(), 'Error about carbon retired');
}

