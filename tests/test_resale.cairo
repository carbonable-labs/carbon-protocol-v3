// Starknet deps

use starknet::{ContractAddress, contract_address_const};

// External deps

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, test_address, spy_events, EventSpy, start_cheat_caller_address,
    stop_cheat_caller_address
};
use snforge_std::cheatcodes::events::{EventsFilterTrait, EventSpyTrait, EventSpyAssertionsTrait};
// Components

use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
use carbon_v3::components::vintage::vintage::VintageComponent::{Event};
use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
use carbon_v3::components::vintage::VintageComponent;
use carbon_v3::components::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
use carbon_v3::components::resale::interface::{
    IResaleHandlerDispatcher, IResaleHandlerDispatcherTrait
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
    default_setup_and_deploy, buy_utils, deploy_resale, deploy_erc20, deploy_minter,
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


//
// Tests
//

#[test]
fn test_resale__init() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let resale_address = deploy_resale(project_address, erc20_address);

    let resale = IResaleHandlerDispatcher { contract_address: resale_address };
    start_cheat_caller_address(resale_address, user_address);
    let token_id: u256 = 1;
    let carbon_pending = resale.get_pending_resale(user_address, token_id);
    assert(carbon_pending == 0, 'carbon pending should be 0');

    let carbon_sold = resale.get_carbon_sold(user_address, token_id);
    assert(carbon_sold == 0, 'carbon sold should be 0');
}

#[test]
fn test_resale__deposit_vintage() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let erc20_address = deploy_erc20();
    let project_address = default_setup_and_deploy();
    let resale_address = deploy_resale(project_address, erc20_address);
    let minter_address = deploy_minter(project_address, erc20_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(resale_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    let initial_balance = project.balance_of(user_address, token_id);

    let amount_resell = initial_balance / 2;

    start_cheat_caller_address(project_address, owner_address);
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, resale_address);
    let resale = IResaleHandlerDispatcher { contract_address: resale_address };

    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(resale_address, true);
    stop_cheat_caller_address(erc20_address);

    let mut spy = spy_events();
    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, resale_address);
    resale.deposit_vintage(token_id, amount_resell);

    let expected_event = helper_expected_transfer_event(
        project_address,
        resale_address,
        user_address,
        resale_address,
        array![token_id].span(),
        amount_resell
    );

    spy.assert_emitted(@array![(project_address, expected_event)]);

    let carbon_pending = resale.get_pending_resale(user_address, token_id);
    assert(carbon_pending == amount_resell, 'Carbon pending is wrong');
    let final_balance = project.balance_of(user_address, token_id);
    assert(final_balance == initial_balance - amount_resell, 'Balance is wrong');
}

#[test]
#[should_panic(expected: 'Resale: Not enough carbon')]
fn test_resale__deposit_insufficient_credits() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let resale_address = deploy_resale(project_address, erc20_address);
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    project_contract.grant_offsetter_role(resale_address);

    stop_cheat_caller_address(project_address);
    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);

    start_cheat_caller_address(project_address, owner_address);
    let token_id: u256 = 1;
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());
    stop_cheat_caller_address(project_address);

    let resale = IResaleHandlerDispatcher { contract_address: resale_address };
    let user_balance = project_contract.balance_of(user_address, token_id);
    resale.deposit_vintage(token_id, user_balance + 1);
}

#[test]
fn test_resale__deposit_exact_balance() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let resale_address = deploy_resale(project_address, erc20_address);
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    project_contract.grant_offsetter_role(resale_address);
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

    let resale = IResaleHandlerDispatcher { contract_address: resale_address };
    start_cheat_caller_address(project_address, user_address);
    project_contract.set_approval_for_all(resale_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, resale_address);
    resale.deposit_vintage(token_id, user_balance);

    let carbon_pending = resale.get_pending_resale(user_address, token_id);
    assert(carbon_pending == user_balance, 'Carbon pending is wrong');

    let user_balance_after = project_contract.balance_of(user_address, token_id);
    assert(user_balance_after == 0, 'Balance is wrong');
}

#[test]
fn test_resale__multiple_deposits() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let resale_address = deploy_resale(project_address, erc20_address);
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(resale_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    let token_id: u256 = 1;
    let balance_initial = project.balance_of(user_address, token_id);

    let resale = IResaleHandlerDispatcher { contract_address: resale_address };
    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(resale_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, resale_address);
    resale.deposit_vintage(token_id, 50000);
    resale.deposit_vintage(token_id, 50000);

    let carbon_pending = resale.get_pending_resale(user_address, token_id);
    assert(carbon_pending == 100000, 'Error pending carbon credits');

    let balance_final = project.balance_of(user_address, token_id);
    assert(balance_final == balance_initial - 100000, 'Error balance');
}

#[test]
fn test_resale__deposit_vintages_valid_inputs() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let resale_address = deploy_resale(project_address, erc20_address);
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(resale_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    let vintage_2024_id: u256 = 1;
    let vintage_2026_id: u256 = 3;
    let balance_initial_token_id = project.balance_of(user_address, vintage_2024_id);
    let balance_initial_2026 = project.balance_of(user_address, vintage_2026_id);

    let vintages: Span<u256> = array![vintage_2024_id, vintage_2026_id].span();
    let carbon_values: Span<u256> = array![50000.into(), 50000.into()].span();
    let resale = IResaleHandlerDispatcher { contract_address: resale_address };
    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(resale_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, resale_address);
    resale.deposit_vintages(vintages, carbon_values);

    let carbon_pending_token_id = resale.get_pending_resale(user_address, vintage_2024_id);
    let carbon_pending_2026 = resale.get_pending_resale(user_address, vintage_2026_id);
    assert(carbon_pending_token_id == 50000, 'Carbon pending value error');
    assert(carbon_pending_2026 == 50000, 'Carbon pending value error');

    let balance_final_token_id = project.balance_of(user_address, vintage_2024_id);
    let balance_final_2026 = project.balance_of(user_address, vintage_2026_id);
    assert(balance_final_token_id == balance_initial_token_id - 50000, 'Balance error');
    assert(balance_final_2026 == balance_initial_2026 - 50000, 'Balance error');
}

#[test]
#[should_panic(expected: 'Resale: Inputs cannot be empty')]
fn test_resale__deposit_vintages_empty_inputs() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let resale_address = deploy_resale(project_address, erc20_address);

    start_cheat_caller_address(resale_address, user_address);

    let resale = IResaleHandlerDispatcher { contract_address: resale_address };
    resale.deposit_vintages(array![].span(), array![].span());
}

#[test]
#[should_panic(expected: 'Resale: Array lengths mismatch')]
fn test_resale__deposit_vintages_mismatched_lengths() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let resale_address = deploy_resale(project_address, erc20_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(resale_address, user_address);

    let vintages: Span<u256> = array![token_id, token_id + 1].span();
    let carbon_values: Span<u256> = array![100000].span();
    let resale = IResaleHandlerDispatcher { contract_address: resale_address };
    resale.deposit_vintages(vintages, carbon_values);
}

#[test]
fn test_resale__deposit_multiple_same_vintage() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let resale_address = deploy_resale(project_address, erc20_address);
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(resale_address);
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
    let resale = IResaleHandlerDispatcher { contract_address: resale_address };
    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(resale_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    start_cheat_caller_address(project_address, resale_address);
    resale.deposit_vintages(vintages, carbon_values);

    let carbon_pending = resale.get_pending_resale(user_address, token_id);
    assert(carbon_pending == 100000, 'Error Carbon pending');

    let balance_final = project.balance_of(user_address, token_id);
    assert(balance_final == initial_balance - 100000, 'Error balance');
}
/// get_pending_resale

#[test]
fn test_resale__get_pending_resale_no_pending() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let resale_address = deploy_resale(project_address, erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    let resale = IResaleHandlerDispatcher { contract_address: resale_address };
    let token_id: u256 = 1;

    // [Assert] No pending retirement should be zero
    let pending_resale = resale.get_pending_resale(user_address, token_id);
    assert(pending_resale == 0.into(), 'Error pending resale');
}

/// get_carbon_retired

#[test]
fn test_resale__get_carbon_sold__when__none_sold() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let resale_address = deploy_resale(project_address, erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    let resale = IResaleHandlerDispatcher { contract_address: resale_address };
    let token_id: u256 = 1;

    let carbon_retired = resale.get_carbon_sold(user_address, token_id);
    assert(carbon_retired == 0.into(), 'Error about carbon sold');
}

#[test]
fn test_resale__sell_carbon_nominal_case() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let erc20_address = deploy_erc20();
    let project_address = default_setup_and_deploy();
    let resale_address = deploy_resale(project_address, erc20_address);
    let minter_address = deploy_minter(project_address, erc20_address);
    let token_id: u256 = 1;

    start_cheat_caller_address(project_address, owner_address);
    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(resale_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    let initial_balance = project.balance_of(user_address, token_id);

    let amount_resell = initial_balance / 2;

    // start_cheat_caller_address(resale_address, user_address);
    // start_cheat_caller_address(project_address, resale_address);
    let resale = IResaleHandlerDispatcher { contract_address: resale_address };

    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(resale_address, true);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(resale_address, user_address);
    //start_cheat_caller_address(project_address, resale_address);
    resale.deposit_vintage(token_id, amount_resell);
    stop_cheat_caller_address(resale_address);

    let carbon_pending = resale.get_pending_resale(user_address, token_id);
    assert(carbon_pending == amount_resell, 'Carbon pending is wrong');
    let final_balance = project.balance_of(user_address, token_id);
    assert(final_balance == initial_balance - amount_resell, 'Balance is wrong');

    let erc20_token = IERC20Dispatcher { contract_address: erc20_address };
    start_cheat_caller_address(erc20_address, owner_address);
    let unit_price: u256 = 20_000_000;
    let token_amount: u256 = amount_resell * unit_price / 1_000_000;

    let owner_balance = erc20_token.balance_of(owner_address);
    assert(owner_balance > 0, 'Owner balance should be >0');
    erc20_token.approve(resale_address, token_amount);
    let allowance = erc20_token.allowance(owner_address, resale_address);
    stop_cheat_caller_address(erc20_address);

    start_cheat_caller_address(resale_address, owner_address);
    resale.sell_carbon_credits(token_id, amount_resell, unit_price, 0);
}
