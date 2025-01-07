// Starknet deps

use core::num::traits::Zero;
use starknet::{ContractAddress, contract_address_const, get_caller_address};

// External deps

use openzeppelin::token::erc1155::ERC1155Component;
use snforge_std as snf;
use snforge_std::{
    DeclareResultTrait, EventSpy, start_cheat_caller_address, stop_cheat_caller_address, spy_events,
    cheatcodes::events::{EventSpyAssertionsTrait}
};

// Models

use carbon_v3::models::CarbonVintageType;
use carbon_v3::constants::MULTIPLIER_TONS_TO_MGRAMS;

// Components

use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
use erc4906::erc4906_component::ERC4906Component;

// Contracts

use carbon_v3::contracts::project::{
    IExternalDispatcher as IProjectDispatcher, IExternalDispatcherTrait as IProjectDispatcherTrait
};


/// Utils for testing purposes
///
use super::tests_lib::{
    equals_with_error, default_setup_and_deploy, perform_fuzzed_transfer, buy_utils, deploy_erc20,
    deploy_minter, deploy_offsetter, helper_sum_balance, helper_check_vintage_balances,
    helper_get_token_ids, helper_expected_transfer_event, helper_expected_transfer_single_events
};

#[test]
fn test_project_mint() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let vintages = IVintageDispatcher { contract_address: project_address };

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    start_cheat_caller_address(project_address, minter_address);

    let mut spy: EventSpy = spy_events();

    let token_id: u256 = 1;
    let vintage_supply = vintages.get_carbon_vintage(token_id).supply;
    let cc_to_mint = vintage_supply / 10; // 10% of the vintage supply

    let internal_value = project_contract.cc_to_internal(cc_to_mint, token_id);
    project_contract.mint(user_address, token_id, internal_value);
    let balance = project_contract.balance_of(user_address, token_id);

    assert(equals_with_error(balance, cc_to_mint, 10), 'Error of balance');

    let expected_event_1155_transfer_single = helper_expected_transfer_event(
        project_address,
        minter_address,
        Zero::zero(),
        user_address,
        array![token_id].span(),
        cc_to_mint
    );
    spy.assert_emitted(@array![(project_address, expected_event_1155_transfer_single)]);
}

#[test]
#[should_panic(expected: 'Only Minter can mint')]
fn test_project_mint_without_minter_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, minter_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let vintages = IVintageDispatcher { contract_address: project_address };

    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    let token_id: u256 = 1;
    project_contract.mint(owner_address, token_id, cc_to_mint);
}

#[test]
#[should_panic(expected: 'Only Minter can batch mint')]
fn test_project_batch_mint_without_minter_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply
    let num_vintages = vintages.get_num_vintages();
    let mut cc_values: Array<u256> = Default::default();
    let mut tokens: Array<u256> = Default::default();
    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        };
        let token_id = (index + 1).into();
        cc_values.append(cc_to_mint);
        tokens.append(token_id);
        index += 1;
    };
    let token_ids = tokens.span();

    project_contract.batch_mint(owner_address, token_ids, cc_values.span());
}

#[test]
fn test_project_batch_mint_with_minter_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let vintages = IVintageDispatcher { contract_address: project_address };

    start_cheat_caller_address(project_address, owner_address);
    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);
    start_cheat_caller_address(project_address, minter_address);

    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    let token_ids = helper_get_token_ids(project_address);
    let mut values: Array<u256> = Default::default();
    let mut index = 0;
    loop {
        if index >= token_ids.len() {
            break;
        };
        values.append(cc_to_mint);
        index += 1;
    };

    let mut spy = spy_events();
    project.batch_mint(user_address, token_ids, values.span());

    let expected_events = helper_expected_transfer_single_events(
        project_address, minter_address, Zero::zero(), user_address, token_ids, cc_to_mint
    );
    spy.assert_emitted(@expected_events);

    let total_cc_balance = helper_sum_balance(project_address, user_address);
    assert(equals_with_error(total_cc_balance, cc_to_mint, 10), 'Error of balance');

    helper_check_vintage_balances(project_address, user_address, cc_to_mint);
}

#[test]
fn test_project_burn_with_offsetter_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    start_cheat_caller_address(offsetter_address, user_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);
    start_cheat_caller_address(project_address, minter_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    stop_cheat_caller_address(project_address);

    start_cheat_caller_address(project_address, owner_address);
    let token_id: u256 = 1;
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());
    stop_cheat_caller_address(project_address);
    let balance = project.balance_of(user_address, token_id);

    let mut spy = spy_events();
    start_cheat_caller_address(project_address, offsetter_address);
    let internal_value = project.cc_to_internal(balance, token_id);
    project.burn(user_address, token_id, internal_value);

    let expected_event_1155_transfer_single = helper_expected_transfer_event(
        project_address,
        offsetter_address,
        user_address,
        Zero::zero(),
        array![token_id].span(),
        balance
    );
    spy.assert_emitted(@array![(project_address, expected_event_1155_transfer_single)]);
}

#[test]
#[should_panic(expected: 'Only Offsetter can burn')]
fn test_project_burn_without_offsetter_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    start_cheat_caller_address(offsetter_address, user_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);

    start_cheat_caller_address(project_address, owner_address);
    let token_id: u256 = 1;
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());
    stop_cheat_caller_address(project_address);

    start_cheat_caller_address(project_address, owner_address);
    project.burn(user_address, token_id, 100);
}

#[test]
fn test_project_batch_burn_with_offsetter_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    start_cheat_caller_address(offsetter_address, user_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    project.grant_offsetter_role(offsetter_address);
    stop_cheat_caller_address(project_address);
    start_cheat_caller_address(project_address, minter_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    stop_cheat_caller_address(project_address);

    start_cheat_caller_address(project_address, owner_address);
    let cc_to_burn = cc_to_mint; // burn all the minted CC
    let token_ids = helper_get_token_ids(project_address);
    let mut values: Array<u256> = Default::default();
    let mut index = 0;
    loop {
        if index >= token_ids.len() {
            break;
        };
        values.append(cc_to_burn);
        index += 1;
    };

    let mut spy = spy_events();
    start_cheat_caller_address(project_address, offsetter_address);
    project.batch_burn(user_address, token_ids, values.span());

    let expected_events = helper_expected_transfer_single_events(
        project_address, offsetter_address, user_address, Zero::zero(), token_ids, cc_to_burn
    );
    spy.assert_emitted(@expected_events);
}

#[test]
#[should_panic(expected: 'Only Offsetter can batch burn')]
fn test_project_batch_burn_without_offsetter_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    start_cheat_caller_address(offsetter_address, user_address);

    let project = IProjectDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);

    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    buy_utils(owner_address, user_address, minter_address, cc_to_mint);
    stop_cheat_caller_address(project_address);

    start_cheat_caller_address(project_address, owner_address);
    let token_id: u256 = 1;
    vintages.update_vintage_status(token_id, CarbonVintageType::Audited.into());
    stop_cheat_caller_address(project_address);

    let share = 100;
    let num_vintages = vintages.get_num_vintages();
    let mut cc_distribution: Array<u256> = Default::default();
    let mut tokens: Array<u256> = Default::default();
    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        };
        let token_id = (index + 1).into();
        cc_distribution.append(share);
        tokens.append(token_id);
        index += 1;
    };
    let cc_distribution = cc_distribution.span();
    let token_ids = tokens.span();

    start_cheat_caller_address(project_address, owner_address);
    project.batch_burn(user_address, token_ids, cc_distribution);
}

/// Test balance_of
#[test]
fn test_project_balance_of() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    project_contract.grant_minter_role(minter_address);

    let cc_to_buy = 100 * MULTIPLIER_TONS_TO_MGRAMS; // 100 CC
    stop_cheat_caller_address(project_address);
    buy_utils(owner_address, user_address, minter_address, cc_to_buy);

    let total_cc_balance = helper_sum_balance(project_address, user_address);
    assert(equals_with_error(total_cc_balance, cc_to_buy, 100), 'Error of balance');

    helper_check_vintage_balances(project_address, user_address, cc_to_buy);
}

/// Test get_balances
#[test]
fn test_project_get_balances() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    project_contract.grant_minter_role(minter_address);

    let cc_to_buy = 100 * MULTIPLIER_TONS_TO_MGRAMS; // 100 CC
    stop_cheat_caller_address(project_address);
    buy_utils(owner_address, user_address, minter_address, cc_to_buy);

    let bals = project_contract.get_balances(user_address);
    let mut sum = 0_u256;
    for i in 0..bals.len() {
        sum += *bals[i];
    };

    assert(equals_with_error(sum, cc_to_buy, 100), 'Error of balance');
}

#[test]
fn test_transfer_without_loss() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    let project_address = default_setup_and_deploy();
    let vintages = IVintageDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    project_contract.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);

    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let amount_to_mint = initial_total_supply / 10; // 10% of the total supply
    buy_utils(owner_address, user_address, minter_address, amount_to_mint);
    let total_supply_balance = helper_sum_balance(project_address, user_address);
    assert(
        equals_with_error(amount_to_mint, total_supply_balance, 100),
        'Error of total supply balance'
    );
    helper_check_vintage_balances(project_address, user_address, amount_to_mint);

    let token_id: u256 = 1;
    let receiver_balance = project_contract.balance_of(receiver_address, token_id);
    assert(equals_with_error(receiver_balance, 0, 10), 'Error of receiver balance 1');

    let balance_user_before = project_contract.balance_of(user_address, token_id);

    let mut spy = spy_events();

    start_cheat_caller_address(project_address, user_address);
    project_contract
        .safe_transfer_from(
            user_address, receiver_address, token_id, balance_user_before, array![].span()
        );

    let expected_event = helper_expected_transfer_event(
        project_address,
        user_address,
        user_address,
        receiver_address,
        array![token_id].span(),
        balance_user_before
    );
    spy.assert_emitted(@array![(project_address, expected_event)]);

    let balance_user_after = project_contract.balance_of(user_address, token_id);

    assert(equals_with_error(balance_user_after, 0, 10), 'Error balance user 2');

    let receiver_balance = project_contract.balance_of(receiver_address, token_id);
    let expected_balance = balance_user_before;
    assert(
        equals_with_error(receiver_balance, expected_balance, 10), 'Error of receiver balance 2'
    );
}

#[test]
fn test_consecutive_transfers_and_rebases(
    first_percentage_rebase: u256, second_percentage_rebase: u256
) {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();

    let project_contract = IProjectDispatcher { contract_address: project_address };
    let vintages = IVintageDispatcher { contract_address: project_address };
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    start_cheat_caller_address(project_address, owner_address);
    project_contract.grant_minter_role(minter_address);

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

    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_buy = initial_total_supply / 10; // 10% of the total supply

    stop_cheat_caller_address(project_address);
    buy_utils(owner_address, user_address, minter_address, cc_to_buy);
    let token_id: u256 = 1;
    let initial_balance = project_contract.balance_of(user_address, token_id);
    stop_cheat_caller_address(project_address);
    // [Prank] Simulate production flow, owner calls Project contract
    start_cheat_caller_address(project_address, user_address);

    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    project_contract
        .safe_transfer_from(
            user_address, receiver_address, token_id, initial_balance.into(), array![].span()
        );

    let initial_vintage_supply = vintages.get_carbon_vintage(token_id).supply;
    let new_vintage_supply_1 = initial_vintage_supply
        * first_percentage_rebase.try_into().unwrap()
        / 100_000;
    stop_cheat_caller_address(project_address);

    start_cheat_caller_address(project_address, owner_address);
    vintages.rebase_vintage(token_id, new_vintage_supply_1);
    stop_cheat_caller_address(project_address);

    let balance_receiver = project_contract.balance_of(receiver_address, token_id);
    start_cheat_caller_address(project_address, receiver_address);
    project_contract
        .safe_transfer_from(
            receiver_address, user_address, token_id, balance_receiver.into(), array![].span()
        );
    stop_cheat_caller_address(project_address);

    let new_vintage_supply_2 = new_vintage_supply_1
        * second_percentage_rebase.try_into().unwrap()
        / 100_000;
    start_cheat_caller_address(project_address, owner_address);
    vintages.rebase_vintage(token_id, new_vintage_supply_2);

    // revert first rebase with the opposite percentage
    let new_vintage_supply_3 = new_vintage_supply_2
        * undo_first_percentage_rebase.try_into().unwrap()
        / 100_000;
    vintages.rebase_vintage(token_id, new_vintage_supply_3);

    // revert second rebase with the opposite percentage
    let new_vintage_supply_4 = new_vintage_supply_3
        * undo_second_percentage_rebase.try_into().unwrap()
        / 100_000;
    vintages.rebase_vintage(token_id, new_vintage_supply_4);

    stop_cheat_caller_address(project_address);

    start_cheat_caller_address(project_address, user_address);

    helper_check_vintage_balances(project_address, user_address, cc_to_buy);
    let balance_receiver = project_contract.balance_of(receiver_address, token_id);
    assert(equals_with_error(balance_receiver, 0, 10), 'Error final balance receiver');
}

#[test]
#[ignore]
fn fuzz_test_transfer_low_supply_low_amount(raw_supply: u256, raw_cc_amount: u256) {
    // max supply of a vintage is 10 CC, so 10^9gm of CC
    let max_supply_for_vintage: u256 = 10 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 1; // with 2 digits after the comma, so 0.01%
    perform_fuzzed_transfer(
        raw_supply, raw_cc_amount, percentage_of_balance_to_send, max_supply_for_vintage
    );
}

#[test]
#[ignore]
fn fuzz_test_transfer_low_supply_medium_amount(raw_supply: u256, raw_cc_amount: u256) {
    // max supply of a vintage is 10 CC, so 10^9gm of CC
    let max_supply_for_vintage: u256 = 10 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 300; // with 2 digits after the comma, so 3%
    perform_fuzzed_transfer(
        raw_supply, raw_cc_amount, percentage_of_balance_to_send, max_supply_for_vintage
    );
}

#[test]
#[ignore]
fn fuzz_test_transfer_low_supply_high_amount(raw_supply: u256, raw_cc_amount: u256) {
    // max supply of a vintage is 10 CC, so 10^9gm of CC
    let max_supply_for_vintage: u256 = 10 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 10_000; // with 2 digits after the comma, so 100%
    perform_fuzzed_transfer(
        raw_supply, raw_cc_amount, percentage_of_balance_to_send, max_supply_for_vintage
    );
}

#[test]
#[ignore]
fn fuzz_test_transfer_medium_supply_low_amount(raw_supply: u256, raw_cc_amount: u256) {
    // max supply of a vintage is 10k CC in mgrams
    let max_supply_for_vintage: u256 = 10_000 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 1; // with 2 digits after the comma, so 0.01%
    perform_fuzzed_transfer(
        raw_supply, raw_cc_amount, percentage_of_balance_to_send, max_supply_for_vintage
    );
}

#[test]
#[ignore]
fn fuzz_test_transfer_medium_supply_medium_amount(raw_supply: u256, raw_cc_amount: u256) {
    // max supply of a vintage is 10k CC in mgrams
    let max_supply_for_vintage: u256 = 10_000 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 300; // with 2 digits after the comma, so 3%
    perform_fuzzed_transfer(
        raw_supply, raw_cc_amount, percentage_of_balance_to_send, max_supply_for_vintage
    );
}

#[test]
#[ignore]
fn fuzz_test_transfer_medium_supply_high_amount(raw_supply: u256, raw_cc_amount: u256) {
    // max supply of a vintage is 10k CC in mgrams
    let max_supply_for_vintage: u256 = 10_000 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 10_000; // with 2 digits after the comma, so 100%
    perform_fuzzed_transfer(
        raw_supply, raw_cc_amount, percentage_of_balance_to_send, max_supply_for_vintage
    );
}

#[test]
#[ignore]
fn fuzz_test_transfer_high_supply_low_amount(raw_supply: u256, raw_cc_amount: u256) {
    // max supply of a vintage is 10M CC in mgrams
    let max_supply_for_vintage: u256 = 10_000_000 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 1; // with 2 digits after the comma, so 0.01%
    perform_fuzzed_transfer(
        raw_supply, raw_cc_amount, percentage_of_balance_to_send, max_supply_for_vintage
    );
}

#[test]
#[ignore]
fn fuzz_test_transfer_high_supply_medium_amount(raw_supply: u256, raw_cc_amount: u256) {
    // max supply of a vintage is 10M CC in mgrams
    let max_supply_for_vintage: u256 = 10_000_000 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 300; // with 2 digits after the comma, so 3%
    perform_fuzzed_transfer(
        raw_supply, raw_cc_amount, percentage_of_balance_to_send, max_supply_for_vintage
    );
}

#[test]
#[ignore]
fn fuzz_test_transfer_high_supply_high_amount(raw_supply: u256, raw_cc_amount: u256) {
    // max supply of a vintage is 10M CC in mgrams
    let max_supply_for_vintage: u256 = 10_000_000 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 10_000; // with 2 digits after the comma, so 100%
    perform_fuzzed_transfer(
        raw_supply, raw_cc_amount, percentage_of_balance_to_send, max_supply_for_vintage
    );
}

fn test_set_uri() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let project_contract = IProjectDispatcher { contract_address: project_address };

    start_cheat_caller_address(project_address, owner_address);
    project_contract.set_uri('test_uri'.try_into().unwrap());
    let uri = project_contract.get_uri();
    assert_eq!(uri, 'test_uri'.try_into().unwrap());
}

#[test]
fn test_decimals() {
    let project_address = default_setup_and_deploy();
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let project_decimals = project_contract.decimals();

    assert(project_decimals == 9, 'Decimals should be 9');
}

#[test]
fn test_is_approved_for_all() {
    let project_address = default_setup_and_deploy();
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let owner = get_caller_address();

    let status = project_contract.is_approved_for_all(owner, project_address);
    // Check if status of approval is a boolean
    assert!(status == true || status == false, "Expected a boolean value");
}

#[test]
fn test_set_approval_for_all() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let mut spy = spy_events();

    start_cheat_caller_address(project_address, owner_address);
    let approval: bool = false;

    project_contract.set_approval_for_all(project_address, approval);

    let status_now = project_contract.is_approved_for_all(owner_address, project_address);
    assert_eq!(status_now, false);

    let expected_event = ERC1155Component::Event::ApprovalForAll(
        ERC1155Component::ApprovalForAll {
            owner: owner_address, operator: project_address, approved: approval
        }
    );
    spy.assert_emitted(@array![(project_address, expected_event)]);
}

#[test]
fn test_project_metadata_update() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let metadata_class = snf::declare("TestMetadata").expect('Declaration failed').contract_class();
    let project = IProjectDispatcher { contract_address: project_address };
    let vintages = IVintageDispatcher { contract_address: project_address };
    let num_vintages = vintages.get_num_vintages();

    let mut spy = spy_events();

    start_cheat_caller_address(project_address, owner_address);
    project.set_uri(*metadata_class.class_hash);
    let uri_result = project.uri(token_id: 1);
    assert!(uri_result.at(0) == @'http://imgur.com/', "Cannot get the URI");
    assert!(uri_result.at(1) == @'01', "Cannot get the URI");
    assert!(uri_result.at(2) == @'.png', "Cannot get the URI");
    let expected_batch_metadata_update = ERC4906Component::Event::BatchMetadataUpdate(
        ERC4906Component::BatchMetadataUpdate { from_token_id: 1, to_token_id: num_vintages.into() }
    );
    spy.assert_emitted(@array![(project_address, expected_batch_metadata_update)]);
}
