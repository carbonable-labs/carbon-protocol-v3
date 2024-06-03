use core::option::OptionTrait;
use core::traits::Into;
use core::array::SpanTrait;
// Starknet deps

use starknet::{ContractAddress, contract_address_const};

// External deps

use openzeppelin::tests::utils::constants as c;
use openzeppelin::utils::serde::SerializedAppend;
use snforge_std as snf;
use snforge_std::{CheatTarget, ContractClassTrait, EventSpy, SpyOn, start_prank, stop_prank};
use alexandria_storage::list::{List, ListTrait};

// Data 

use carbon_v3::data::carbon_vintage::{CarbonVintage, CarbonVintageType};

// Components

use carbon_v3::components::absorber::interface::{
    IAbsorber, IAbsorberDispatcher, IAbsorberDispatcherTrait, ICarbonCreditsHandler,
    ICarbonCreditsHandlerDispatcher, ICarbonCreditsHandlerDispatcherTrait
};
use carbon_v3::components::absorber::carbon_handler::AbsorberComponent::CC_DECIMALS_MULTIPLIER;
use carbon_v3::components::minter::interface::{IMint, IMintDispatcher, IMintDispatcherTrait};

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};

/// Utils for testing purposes
/// 
use carbon_v3::tests_lib::{
    get_mock_times, get_mock_absorptions, equals_with_error, deploy_project, setup_project,
    default_setup_and_deploy, fuzzing_setup, perform_fuzzed_transfer, buy_utils, deploy_erc20, deploy_minter
};

#[test]
fn test_constructor_ok() {
    let (_project_address, _spy) = deploy_project();
}

#[test]
fn test_is_setup() {
    let (project_address, _) = deploy_project();
    let project = IAbsorberDispatcher { contract_address: project_address };

    setup_project(
        project_address,
        1573000000,
        array![1706785200, 2306401200].span(),
        array![0, 1573000000].span(),
    );

    assert(project.is_setup(), 'Error during setup');
}

#[test]
fn test_project_batch_mint() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let decimal: u8 = project_contract.decimals();
    assert(decimal == 6, 'Error of decimal');

    let share: u256 = 125000;
    let cc_distribution: Span<u256> = absorber.compute_carbon_vintage_distribution(share);
    let cc_vintage_years: Span<u256> = carbon_credits.get_vintage_years();
    project_contract.batch_mint(owner_address, cc_vintage_years, cc_distribution);
}

#[test]
fn test_project_set_vintage_status() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    carbon_credits.update_vintage_status(2025, 3);
    let vintage: CarbonVintage = carbon_credits.get_carbon_vintage(2025);
    assert(vintage.status == CarbonVintageType::Audited, 'Error of status');
}

/// Test balance_of
#[test]
fn test_project_balance_of() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    let share = 33 * CC_DECIMALS_MULTIPLIER;
    buy_utils(minter_address, erc20_address, share);

    let supply_vintage_2025 = carbon_credits.get_specific_carbon_vintage(2025).cc_supply;
    let expected_balance = supply_vintage_2025.into() * share / CC_DECIMALS_MULTIPLIER / 100;
    let balance = project_contract.balance_of(owner_address, 2025);

    assert(equals_with_error(balance, expected_balance, 100), 'Error of balance');
}

#[test]
fn test_transfer_without_loss() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);

    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    let share = 33 * CC_DECIMALS_MULTIPLIER;
    buy_utils(minter_address, erc20_address, share);

    let supply_vintage_2025 = carbon_credits.get_specific_carbon_vintage(2025).cc_supply;
    let expected_balance = supply_vintage_2025.into() * share / CC_DECIMALS_MULTIPLIER / 100;
    let balance = project_contract.balance_of(owner_address, 2025);

    assert(equals_with_error(balance, expected_balance, 100), 'Error balance owner 1');

    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    let receiver_balance = project_contract.balance_of(receiver_address, 2025);
    assert(equals_with_error(receiver_balance, 0, 100), 'Error of receiver balance 1');

    project_contract
        .safe_transfer_from(owner_address, receiver_address, 2025, balance.into(), array![].span());

    let balance = project_contract.balance_of(owner_address, 2025);
    assert(equals_with_error(balance, 0, 100), 'Error balance owner 2');

    let receiver_balance = project_contract.balance_of(receiver_address, 2025);
    assert(
        equals_with_error(receiver_balance, expected_balance, 100), 'Error of receiver balance 2'
    );
}

#[test]
fn test_transfer_rebase_transfer(first_percentage_rebase: u256, second_percentage_rebase: u256) {
    // fn test_transfer_rebase_transfer() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let (erc20_address, _) = deploy_erc20();
    let (minter_address, _) = deploy_minter(project_address, erc20_address);
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(minter_address), owner_address);
    start_prank(CheatTarget::One(erc20_address), owner_address);
    assert(absorber.is_setup(), 'Error during setup');

    // Format fuzzing parameters, percentages with 6 digits after the comma, max 299.999999%
    let DECIMALS_FACTORS = 100_000;
    let first_percentage_rebase = first_percentage_rebase % 3 * DECIMALS_FACTORS;
    let second_percentage_rebase = second_percentage_rebase % 3 * DECIMALS_FACTORS;

    if first_percentage_rebase == 0 || second_percentage_rebase == 0 {
        return;
    }

    let undo_first_percentage_rebase = (DECIMALS_FACTORS * DECIMALS_FACTORS)
        / first_percentage_rebase;
    let undo_second_percentage_rebase = (DECIMALS_FACTORS * DECIMALS_FACTORS)
        / second_percentage_rebase;
    let share = 33 * CC_DECIMALS_MULTIPLIER;

    buy_utils(minter_address, erc20_address, share);
    let initial_balance = project_contract.balance_of(owner_address, 2025);

    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    project_contract
        .safe_transfer_from(
            owner_address, receiver_address, 2025, initial_balance.into(), array![].span()
        );

    let initial_vintage_supply = cc_handler.get_carbon_vintage(2025).supply;
    let new_vintage_supply_1 = initial_vintage_supply
        * first_percentage_rebase.try_into().unwrap()
        / 100_000;
    absorber.rebase_vintage(2025, new_vintage_supply_1);

    let balance_receiver = project_contract.balance_of(receiver_address, 2025);
    start_prank(CheatTarget::One(project_address), receiver_address);
    project_contract
        .safe_transfer_from(
            receiver_address, owner_address, 2025, balance_receiver.into(), array![].span()
        );

    let new_vintage_supply_2 = new_vintage_supply_1
        * second_percentage_rebase.try_into().unwrap()
        / 100_000;
    absorber.rebase_vintage(2025, new_vintage_supply_2);

    // revert first rebase with the opposite percentage
    let new_vintage_supply_3 = new_vintage_supply_2
        * undo_first_percentage_rebase.try_into().unwrap()
        / 100_000;
    absorber.rebase_vintage(2025, new_vintage_supply_3);

    // revert second rebase with the opposite percentage
    let new_vintage_supply_4 = new_vintage_supply_3
        * undo_second_percentage_rebase.try_into().unwrap()
        / 100_000;
    absorber.rebase_vintage(2025, new_vintage_supply_4);

    let balance_owner = project_contract.balance_of(owner_address, 2025);
    assert(equals_with_error(balance_owner, initial_balance, 100), 'Error final balance owner');
    let balance_receiver = project_contract.balance_of(receiver_address, 2025);
    assert(equals_with_error(balance_receiver, 0, 100), 'Error final balance receiver');
}

#[test]
fn fuzz_test_transfer_low_supply_low_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 1 CC, so 10^6g of CC + 2 digits after the comma for precision => 10^8
    let max_supply_for_vintage: u64 = 100_000_000;
    let percentage_of_balance_to_send = 1; // with 2 digits after the comma, so 0.01%
    perform_fuzzed_transfer(
        raw_supply,
        raw_share,
        raw_last_digits_share,
        percentage_of_balance_to_send,
        max_supply_for_vintage
    );
}

#[test]
fn fuzz_test_transfer_low_supply_medium_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 1 CC, so 10^6g of CC + 2 digits after the comma for precision => 10^8
    let max_supply_for_vintage: u64 = 100_000_000;
    let percentage_of_balance_to_send = 300; // with 2 digits after the comma, so 3%
    perform_fuzzed_transfer(
        raw_supply,
        raw_share,
        raw_last_digits_share,
        percentage_of_balance_to_send,
        max_supply_for_vintage
    );
}

#[test]
fn fuzz_test_transfer_low_supply_high_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 1 CC, so 10^6g of CC + 2 digits after the comma for precision => 10^8
    let max_supply_for_vintage: u64 = 100_000_000;
    let percentage_of_balance_to_send = 10_000; // with 2 digits after the comma, so 100%
    perform_fuzzed_transfer(
        raw_supply,
        raw_share,
        raw_last_digits_share,
        percentage_of_balance_to_send,
        max_supply_for_vintage
    );
}

#[test]
fn fuzz_test_transfer_medium_supply_low_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10k CC, so 10^10g of CC + 2 digits after the comma for precision => 10^12
    let max_supply_for_vintage: u64 = 1_000_000_000_000;
    let percentage_of_balance_to_send = 1; // with 2 digits after the comma, so 0.01%
    perform_fuzzed_transfer(
        raw_supply,
        raw_share,
        raw_last_digits_share,
        percentage_of_balance_to_send,
        max_supply_for_vintage
    );
}

#[test]
fn fuzz_test_transfer_medium_supply_medium_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10k CC, so 10^10g of CC + 2 digits after the comma for precision => 10^12
    let max_supply_for_vintage: u64 = 1_000_000_000_000;
    let percentage_of_balance_to_send = 300; // with 2 digits after the comma, so 3%
    perform_fuzzed_transfer(
        raw_supply,
        raw_share,
        raw_last_digits_share,
        percentage_of_balance_to_send,
        max_supply_for_vintage
    );
}

#[test]
fn fuzz_test_transfer_medium_supply_high_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10k CC, so 10^10g of CC + 2 digits after the comma for precision => 10^12
    let max_supply_for_vintage: u64 = 1_000_000_000_000;
    let percentage_of_balance_to_send = 10_000; // with 2 digits after the comma, so 100%
    perform_fuzzed_transfer(
        raw_supply,
        raw_share,
        raw_last_digits_share,
        percentage_of_balance_to_send,
        max_supply_for_vintage
    );
}

#[test]
fn fuzz_test_transfer_high_supply_low_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10M CC, so 10^13g of CC + 2 digits after the comma for precision => 10^15
    let max_supply_for_vintage: u64 = 1_000_000_000_000_000;
    let percentage_of_balance_to_send = 1; // with 2 digits after the comma, so 0.01%
    perform_fuzzed_transfer(
        raw_supply,
        raw_share,
        raw_last_digits_share,
        percentage_of_balance_to_send,
        max_supply_for_vintage
    );
}

#[test]
fn fuzz_test_transfer_high_supply_medium_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10M CC, so 10^13g of CC + 2 digits after the comma for precision => 10^15
    let max_supply_for_vintage: u64 = 1_000_000_000_000_000;
    let percentage_of_balance_to_send = 300; // with 2 digits after the comma, so 3%
    perform_fuzzed_transfer(
        raw_supply,
        raw_share,
        raw_last_digits_share,
        percentage_of_balance_to_send,
        max_supply_for_vintage
    );
}

#[test]
fn fuzz_test_transfer_high_supply_high_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10M CC, so 10^13g of CC + 2 digits after the comma for precision => 10^15
    let max_supply_for_vintage: u64 = 1_000_000_000_000_000;
    let percentage_of_balance_to_send = 10_000; // with 2 digits after the comma, so 100%
    perform_fuzzed_transfer(
        raw_supply,
        raw_share,
        raw_last_digits_share,
        percentage_of_balance_to_send,
        max_supply_for_vintage
    );
}
