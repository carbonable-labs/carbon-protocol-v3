// Starknet deps

use starknet::{ContractAddress, contract_address_const};

// External deps

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::token::erc20::interface::ERC20ABIDispatcherTrait;
use openzeppelin::token::erc1155::ERC1155Component;

use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, test_address, spy_events, EventSpy, CheatSpan,
    start_cheat_caller_address, stop_cheat_caller_address, EventSpyAssertionsTrait
};

// Components

use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
use carbon_v3::components::vintage::VintageComponent;
use carbon_v3::components::minter::interface::{IMintDispatcher, IMintDispatcherTrait};
use carbon_v3::components::minter::MintComponent;

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};
use carbon_v3::contracts::minter::Minter;
use carbon_v3::mock::usdcarb::USDCarb;

// Utils for testing purposes

use super::tests_lib::{
    get_mock_absorptions, equals_with_error, deploy_project, setup_project,
    default_setup_and_deploy, deploy_offsetter, deploy_erc20, deploy_minter, buy_utils,
    helper_get_token_ids, helper_sum_balance, DEFAULT_REMAINING_MINTABLE_CC,
    helper_check_vintage_balances, get_mock_absorptions_times_2, helper_expected_transfer_event,
    helper_expected_transfer_single_events, helper_get_cc_amounts
};

// Constants

use carbon_v3::models::constants::{MULTIPLIER_TONS_TO_MGRAMS};
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

// is_public_sale_open

#[test]
fn test_is_public_sale_open_default_value() {
    let project_address = deploy_project();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let sale_open = minter.is_public_sale_open();
    assert(sale_open == true, 'public sale not open');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_public_sale_open_without_owner_role() {
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };

    minter.set_public_sale_open(true);
}

#[test]
fn test_set_public_sale_open_with_owner_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let mut spy = spy_events();

    start_cheat_caller_address(minter_address, owner_address);

    let minter = IMintDispatcher { contract_address: minter_address };

    minter.set_public_sale_open(true);
    let expected_event = MintComponent::Event::PublicSaleOpen(
        MintComponent::PublicSaleOpen { old_value: true, new_value: true }
    );
    spy.assert_emitted(@array![(minter_address, expected_event)]);
}

/// redeem_investment
#[test]
fn test_redeem_investment() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let mut spy = spy_events();

    start_cheat_caller_address(erc20_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    let vintage = IVintageDispatcher { contract_address: project_address };
    let minter = IMintDispatcher { contract_address: minter_address };
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    start_cheat_caller_address(project_address, owner_address);
    project.grant_minter_role(minter_address);

    start_cheat_caller_address(project_address, minter_address);
    let initial_project_supply = vintage.get_initial_project_cc_supply();
    let cc_amount_to_buy: u256 = initial_project_supply / 10; // 10% of the initial supply
    let money_to_buy = cc_amount_to_buy * minter.get_unit_price() / MULTIPLIER_TONS_TO_MGRAMS;
    buy_utils(owner_address, user_address, minter_address, cc_amount_to_buy);

    let remaining_mintable_cc = minter.get_remaining_mintable_cc();
    assert(
        remaining_mintable_cc == initial_project_supply - cc_amount_to_buy,
        'remaining cc wrong value'
    );

    let user_balance = erc20.balance_of(user_address);
    assert(user_balance == 0, 'user balance should be 0'); // used everything to buy cc

    start_cheat_caller_address(minter_address, owner_address);
    minter.cancel_mint();

    start_cheat_caller_address(project_address, user_address);
    // Approve the project to spend the user's carbon credits
    project.set_approval_for_all(minter_address, true);
    // Redeem the investment
    start_cheat_caller_address(minter_address, user_address);
    minter.redeem_investment();

    let remaining_mintable_cc = minter.get_remaining_mintable_cc();
    assert(remaining_mintable_cc == initial_project_supply, 'remaining cc wrong value');

    let user_balance_after = erc20.balance_of(user_address);
    assert(user_balance_after == money_to_buy, 'user balance error after redeem');
    let expected_event = MintComponent::Event::RedeemInvestment(
        MintComponent::RedeemInvestment { address: user_address, amount: money_to_buy }
    );
    spy.assert_emitted(@array![(minter_address, expected_event)]);
}

#[test]
#[should_panic(expected: 'Mint is not canceled')]
fn test_redeem_without_cancel() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    let project = IProjectDispatcher { contract_address: project_address };
    let vintage = IVintageDispatcher { contract_address: project_address };
    let minter = IMintDispatcher { contract_address: minter_address };
    start_cheat_caller_address(project_address, owner_address);
    project.grant_minter_role(minter_address);

    start_cheat_caller_address(project_address, minter_address);
    let initial_project_supply = vintage.get_initial_project_cc_supply();
    let cc_amount_to_buy: u256 = initial_project_supply / 10; // 10% of the initial supply
    buy_utils(owner_address, user_address, minter_address, cc_amount_to_buy);

    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(minter_address, true);
    // Redeem the investment
    start_cheat_caller_address(minter_address, user_address);
    minter.redeem_investment();
}

#[test]
fn test_redeem_no_investment() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    let project = IProjectDispatcher { contract_address: project_address };
    let minter = IMintDispatcher { contract_address: minter_address };
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    start_cheat_caller_address(project_address, owner_address);
    project.grant_minter_role(minter_address);

    start_cheat_caller_address(minter_address, owner_address);
    minter.cancel_mint();

    start_cheat_caller_address(project_address, user_address);
    project.set_approval_for_all(minter_address, true);
    // Redeem but no investment was made
    start_cheat_caller_address(minter_address, user_address);
    minter.redeem_investment();

    let user_balance_after = erc20.balance_of(user_address);
    assert(user_balance_after == 0, 'user balance error after redeem');
}

// public_buy

#[test]
fn test_public_buy() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);

    stop_cheat_caller_address(project_address);
    let minter = IMintDispatcher { contract_address: minter_address };

    let cc_to_buy: u256 = 10 * MULTIPLIER_TONS_TO_MGRAMS; // 10 CC
    let money_amount = cc_to_buy * minter.get_unit_price() / MULTIPLIER_TONS_TO_MGRAMS;

    start_cheat_caller_address(erc20_address, owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    let success = erc20.transfer(user_address, money_amount);
    assert(success, 'Transfer failed');

    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, money_amount);

    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);

    let mut spy = spy_events();
    minter.public_buy(cc_to_buy);

    let token_ids = helper_get_token_ids(project_address);
    // TODO: helper for amounts here?

    // let mut cc_amounts: Array<u256> = Default::default();
    // let mut index = 0;
    // loop {
    //     if index >= token_ids.len() {
    //         break ();
    //     }
    //     let token_id = *token_ids.at(index);
    //     let cc_value = project_contract.internal_to_cc(cc_to_buy, token_id);
    //     cc_amounts.append(cc_value);
    //     index += 1;
    // };

    let expected_events = helper_expected_transfer_single_events(
        project_address, minter_address, Zeroable::zero(), user_address, token_ids, cc_to_buy
    );
    spy.assert_emitted(@expected_events);

    let balance_user_after = helper_sum_balance(project_address, user_address);
    assert(equals_with_error(balance_user_after, cc_to_buy, 100), 'balance should be the same');
}


#[test]
fn test_minimal_buy() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);

    stop_cheat_caller_address(project_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    let cc_to_buy: u256 = MULTIPLIER_TONS_TO_MGRAMS / minter.get_unit_price() + 1;
    let money_amount = cc_to_buy * minter.get_unit_price() / MULTIPLIER_TONS_TO_MGRAMS;

    start_cheat_caller_address(erc20_address, owner_address);
    let success = erc20.transfer(user_address, money_amount);
    assert(success, 'Transfer failed');

    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, money_amount);

    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);

    let mut spy = spy_events();
    minter.public_buy(cc_to_buy);

    let balance = helper_sum_balance(project_address, user_address);
    assert(equals_with_error(balance, cc_to_buy, 100), 'balance should be the same');

    let token_ids = helper_get_token_ids(project_address);

    let expected_events = helper_expected_transfer_single_events(
        project_address, minter_address, Zeroable::zero(), user_address, token_ids, cc_to_buy
    );
    spy.assert_emitted(@expected_events);
}

#[test]
#[should_panic(expected: 'Value too low')]
fn test_minimal_buy_error() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);

    stop_cheat_caller_address(project_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    let cc_to_buy: u256 = MULTIPLIER_TONS_TO_MGRAMS / minter.get_unit_price();
    let money_amount = cc_to_buy * minter.get_unit_price() / MULTIPLIER_TONS_TO_MGRAMS;

    start_cheat_caller_address(erc20_address, owner_address);
    let success = erc20.transfer(user_address, money_amount);
    assert(success, 'Transfer failed');

    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, money_amount);

    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);

    let mut spy = spy_events();
    minter.public_buy(cc_to_buy);

    let balance = helper_sum_balance(project_address, user_address);
    assert(equals_with_error(balance, cc_to_buy, 100), 'balance should be the same');

    let token_ids = helper_get_token_ids(project_address);

    let expected_events = helper_expected_transfer_single_events(
        project_address, minter_address, Zeroable::zero(), user_address, token_ids, cc_to_buy
    );
    spy.assert_emitted(@expected_events);
}

// set_max_mintable_cc
#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_max_mintable_cc_without_owner_role() {
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    minter.set_max_mintable_cc(100 * MULTIPLIER_TONS_TO_MGRAMS);
}

#[test]
fn test_set_max_mintable_cc_with_owner_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let mut spy = spy_events();

    start_cheat_caller_address(minter_address, owner_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let new_max_mintable_cc: u256 = 100 * MULTIPLIER_TONS_TO_MGRAMS;
    minter.set_max_mintable_cc(new_max_mintable_cc);

    let max_mintable_cc = minter.get_max_mintable_cc();
    assert(max_mintable_cc == new_max_mintable_cc, 'max mintable cc wrong value');
    let remaining_mintable_cc = minter.get_remaining_mintable_cc();
    assert(remaining_mintable_cc == new_max_mintable_cc, 'remaining mintable cc wrong');

    let expected_event = MintComponent::Event::RemainingMintableCCUpdated(
        MintComponent::RemainingMintableCCUpdated {
            old_value: DEFAULT_REMAINING_MINTABLE_CC, new_value: new_max_mintable_cc
        }
    );
    let expected_event_max_mintable_cc = MintComponent::Event::MaxMintableCCUpdated(
        MintComponent::MaxMintableCCUpdated {
            old_value: DEFAULT_REMAINING_MINTABLE_CC, new_value: new_max_mintable_cc
        }
    );
    spy.assert_emitted(@array![(minter_address, expected_event)]);
    spy.assert_emitted(@array![(minter_address, expected_event_max_mintable_cc)]);
}

// get_remaining_mintable_cc

#[test]
fn test_get_remaining_mintable_cc() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = deploy_project();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);

    let yearly_absorptions: Span<u256> = get_mock_absorptions();
    let default_max_mintable_cc: u256 = DEFAULT_REMAINING_MINTABLE_CC;
    setup_project(project_address, yearly_absorptions);
    stop_cheat_caller_address(project_address);

    let minter = IMintDispatcher { contract_address: minter_address };

    let remaining_mintable_cc = minter.get_remaining_mintable_cc();
    assert(remaining_mintable_cc == default_max_mintable_cc, 'remaining money wrong value 1');

    let amount_to_buy: u256 = 1000;

    start_cheat_caller_address(erc20_address, owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    let success = erc20.transfer(user_address, amount_to_buy);
    assert(success, 'Transfer failed');

    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, amount_to_buy);

    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);
    minter.public_buy(amount_to_buy);
    stop_cheat_caller_address(minter_address);
    stop_cheat_caller_address(erc20_address);

    let remaining_mintable_cc_after_buy = minter.get_remaining_mintable_cc();
    assert(
        remaining_mintable_cc_after_buy == default_max_mintable_cc - amount_to_buy,
        'remaining money wrong value 2'
    );

    // Mint all the remaining carbon credits
    let remaining_mintable_cc = minter.get_remaining_mintable_cc();
    start_cheat_caller_address(erc20_address, owner_address);
    let success = erc20.transfer(user_address, remaining_mintable_cc);
    assert(success, 'Transfer failed');

    let remaining_money_to_buy = remaining_mintable_cc
        * minter.get_unit_price()
        / MULTIPLIER_TONS_TO_MGRAMS;
    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, remaining_money_to_buy);
    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);
    minter.public_buy(remaining_mintable_cc);

    let remaining_mintable_cc_after_buying_all = minter.get_remaining_mintable_cc();
    assert(remaining_mintable_cc_after_buying_all == 0, 'remaining money wrong value');
}

// cancel_mint

#[test]
fn test_cancel_mint() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = deploy_project();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let mut spy = spy_events();

    let minter = IMintDispatcher { contract_address: minter_address };
    start_cheat_caller_address(minter_address, owner_address);

    // Ensure the mint is not canceled initially
    let is_canceled = minter.is_canceled();
    assert(!is_canceled, 'mint should not be canceled');

    // Cancel the mint
    minter.cancel_mint();
    let expected_event = MintComponent::Event::MintCanceled(
        MintComponent::MintCanceled { is_canceled: true }
    );
    spy.assert_emitted(@array![(minter_address, expected_event)]);

    // Verify that the mint is canceled
    let is_canceled_after = minter.is_canceled();
    assert(is_canceled_after, 'mint should be canceled');
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_cancel_mint_without_owner_role() {
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    minter.cancel_mint();
}

#[test]
#[should_panic(expected: 'Mint is canceled')]
fn test_reopen_sale_after_canceled_mint() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = deploy_project();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    start_cheat_caller_address(minter_address, owner_address);

    // Cancel the mint
    minter.cancel_mint();

    // Try to reopen the sale
    minter.set_public_sale_open(true);
}


#[test]
fn test_get_min_money_amount_per_tx() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    start_cheat_caller_address(project_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let initial_min_money_per_tx: u256 = 0; // default value
    let min_money_per_tx = minter.get_min_money_amount_per_tx();
    assert!(min_money_per_tx == initial_min_money_per_tx, "initial min money per tx is incorrect");

    let amount_to_buy: u256 = 1000;
    start_cheat_caller_address(erc20_address, owner_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    let success = erc20.transfer(user_address, amount_to_buy);
    assert(success, 'Transfer failed');

    start_cheat_caller_address(erc20_address, user_address);
    erc20.approve(minter_address, amount_to_buy);

    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(erc20_address, minter_address);

    minter.public_buy(amount_to_buy);

    // Verify the min money amount per transaction remains unchanged
    let min_money_per_tx_after_buy = minter.get_min_money_amount_per_tx();
    assert!(
        min_money_per_tx_after_buy == initial_min_money_per_tx,
        "min money per tx after buy is incorrect"
    );
}

#[test]
fn test_is_sold_out() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let mut spy = spy_events();

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let is_sold_out_initial = minter.is_sold_out();
    assert(!is_sold_out_initial, 'should not be sold out');

    let remaining_mintable_cc = minter.get_remaining_mintable_cc();
    buy_utils(owner_address, user_address, minter_address, remaining_mintable_cc);

    let remaining_cc_after_buying_all = minter.get_remaining_mintable_cc();
    assert(remaining_cc_after_buying_all == 0, 'remaining cc wrong value');

    let is_sold_out_after = minter.is_sold_out();
    assert(is_sold_out_after, 'should be sold out');

    let is_sale_open = minter.is_public_sale_open();
    assert(!is_sale_open, 'public sale should be closed');

    let expected_event_sale_close = MintComponent::Event::PublicSaleClose(
        MintComponent::PublicSaleClose { old_value: true, new_value: false }
    );
    let expected_event_sold_out = MintComponent::Event::SoldOut(
        MintComponent::SoldOut { sold_out: true }
    );
    spy.assert_emitted(@array![(minter_address, expected_event_sale_close)]);
    spy.assert_emitted(@array![(minter_address, expected_event_sold_out)]);
}

#[test]
#[should_panic(expected: 'Sale is closed')]
fn test_public_buy_when_sold_out() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let remaining_mintable_cc = minter.get_remaining_mintable_cc();
    buy_utils(owner_address, user_address, minter_address, remaining_mintable_cc);

    let remaining_cc_after_buying_all = minter.get_remaining_mintable_cc();
    assert(remaining_cc_after_buying_all == 0, 'remaining cc wrong value');

    start_cheat_caller_address(erc20_address, user_address);
    buy_utils(owner_address, user_address, minter_address, 1);
}

#[test]
#[should_panic(expected: 'Minting limit reached')]
fn test_public_buy_exceeds_mint_limit() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let remaining_mintable_cc = minter.get_remaining_mintable_cc();
    buy_utils(owner_address, user_address, minter_address, remaining_mintable_cc - 1);

    let remaining_cc_after_partial_buy = minter.get_remaining_mintable_cc();
    assert(remaining_cc_after_partial_buy == 1, 'remaining cc wrong value');

    start_cheat_caller_address(erc20_address, user_address);
    buy_utils(owner_address, user_address, minter_address, 200); // This should cause a panic
}

#[test]
fn test_set_min_money_amount_per_tx() {
    // Deploy required contracts
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let mut spy = spy_events();

    start_cheat_caller_address(project_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    // Verify that the min money amount per tx is 0 at the beginning
    let min_money_amount_per_tx = minter.get_min_money_amount_per_tx();
    assert(min_money_amount_per_tx == 0, 'Initial min per tx incorrect');

    let new_min_money_amount: u256 = 500;
    minter.set_min_money_amount_per_tx(new_min_money_amount);
    let updated_min_money_amount_per_tx = minter.get_min_money_amount_per_tx();
    assert(updated_min_money_amount_per_tx == new_min_money_amount, 'Updated min money incorrect');

    let expected_event = MintComponent::Event::MinMoneyAmountPerTxUpdated(
        MintComponent::MinMoneyAmountPerTxUpdated {
            old_amount: 0, new_amount: new_min_money_amount
        }
    );
    spy.assert_emitted(@array![(minter_address, expected_event)]);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_min_money_amount_per_tx_without_owner_role() {
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let amount: u256 = 100;
    minter.set_min_money_amount_per_tx(amount);
}

// get_carbonable_project_address

#[test]
fn test_get_carbonable_project_address() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(minter_address, user_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let carbonable_project_address = minter.get_carbonable_project_address();
    assert(carbonable_project_address == project_address, 'address does not match');
}

// get_payment_token_address

#[test]
fn test_get_payment_token_address() {
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(minter_address, user_address);
    let minter = IMintDispatcher { contract_address: minter_address };

    let payment_token_address = minter.get_payment_token_address();
    assert(payment_token_address == erc20_address, 'address does not match');
}

// set_unit_price

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_set_unit_price_without_owner_role() {
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let price: u256 = 100000000;
    minter.set_unit_price(price);
}

#[test]
fn test_set_unit_price_with_owner_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let mut spy = spy_events();

    start_cheat_caller_address(minter_address, owner_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let price: u256 = 100000000; // $100
    minter.set_unit_price(price);

    let expected_event = MintComponent::Event::UnitPriceUpdated(
        MintComponent::UnitPriceUpdated { old_price: 11000000, new_price: price }
    );
    spy.assert_emitted(@array![(minter_address, expected_event)]);
}

#[test]
#[should_panic(expected: 'Invalid unit price')]
fn test_set_unit_price_to_zero_panic() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(minter_address, owner_address);
    let minter = IMintDispatcher { contract_address: minter_address };

    // Ensure the unit price is not set initially
    let unit_price = minter.get_unit_price();
    assert(unit_price == 11000000, 'unit price should be 11000000');

    // Set the unit price to 0 and it should panic
    let new_unit_price: u256 = 0;
    minter.set_unit_price(new_unit_price);
}

// get_unit_price

#[test]
fn test_get_unit_price() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(minter_address, user_address);
    let minter = IMintDispatcher { contract_address: minter_address };

    let unit_price = minter.get_unit_price();
    assert(unit_price == 11000000, 'unit price should be 11000000');
    stop_cheat_caller_address(minter_address);

    start_cheat_caller_address(minter_address, owner_address);
    let new_unit_price: u256 = 100000000;
    start_cheat_caller_address(minter_address, owner_address);
    minter.set_unit_price(new_unit_price);
    stop_cheat_caller_address(minter_address);

    start_cheat_caller_address(minter_address, user_address);
    let unit_price_after = minter.get_unit_price();
    assert(unit_price_after == new_unit_price, 'unit price wrong value');
}

#[test]
fn test_withdraw() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);
    let mut spy = spy_events();

    start_cheat_caller_address(erc20_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);

    let project = IProjectDispatcher { contract_address: project_address };
    let minter = IMintDispatcher { contract_address: minter_address };
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    start_cheat_caller_address(project_address, owner_address);
    project.grant_minter_role(minter_address);

    start_cheat_caller_address(project_address, minter_address);
    let cc_amount_to_buy: u256 = 10 * MULTIPLIER_TONS_TO_MGRAMS; // 10 CC
    buy_utils(owner_address, owner_address, minter_address, cc_amount_to_buy);
    start_cheat_caller_address(erc20_address, user_address);
    buy_utils(owner_address, user_address, minter_address, cc_amount_to_buy);

    let balance_owner_before_withdraw = erc20.balance_of(owner_address);

    let balance_to_withdraw = erc20.balance_of(minter_address);
    start_cheat_caller_address(minter_address, owner_address);
    minter.withdraw();

    let balance_owner_after = erc20.balance_of(owner_address);
    assert(
        balance_owner_after == balance_owner_before_withdraw + balance_to_withdraw,
        'balance should be the same'
    );

    let expected_event = MintComponent::Event::Withdraw(
        MintComponent::Withdraw { recipient: owner_address, amount: balance_to_withdraw }
    );
    spy.assert_emitted(@array![(minter_address, expected_event)]);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_withdraw_without_owner_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(erc20_address, owner_address);
    start_cheat_caller_address(minter_address, owner_address);
    start_cheat_caller_address(project_address, owner_address);
    let project = IProjectDispatcher { contract_address: project_address };
    let minter = IMintDispatcher { contract_address: minter_address };
    let vintage = IVintageDispatcher { contract_address: project_address };
    project.grant_minter_role(minter_address);

    start_cheat_caller_address(project_address, minter_address);
    let initial_project_supply = vintage.get_initial_project_cc_supply();
    let cc_to_mint: u256 = initial_project_supply / 10; // 10% of the initial supply
    buy_utils(owner_address, owner_address, minter_address, cc_to_mint);
    start_cheat_caller_address(erc20_address, user_address);
    buy_utils(owner_address, user_address, minter_address, cc_to_mint);

    start_cheat_caller_address(minter_address, user_address);
    minter.withdraw();
}

#[test]
fn test_retrieve_amount() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = deploy_project();

    // Deploy erc20 used for the minter, and a second erc20 that isn't used
    let contract = snf::declare("USDCarb").expect('Failed to declare contract').contract_class();
    let mut calldata: Array<felt252> = array![user_address.into(), user_address.into()];
    let (erc20_address, _) = contract.deploy(@calldata).expect('Failed to deploy contract');
    calldata = array![user_address.into(), user_address.into()];
    let (second_erc20_address, _) = contract.deploy(@calldata).expect('Failed to deploy contract');
    let minter_address = deploy_minter(project_address, erc20_address);

    let mut spy = spy_events();

    start_cheat_caller_address(second_erc20_address, user_address);
    start_cheat_caller_address(minter_address, owner_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let second_er20 = IERC20Dispatcher { contract_address: second_erc20_address };

    // Transferring incorrect token to minter
    let success = second_er20.transfer(minter_address, 1000);
    assert(success, 'Transfer failed');

    start_cheat_caller_address(second_erc20_address, minter_address);
    minter.retrieve_amount(second_erc20_address, owner_address, 1000);
    let balance_after = second_er20.balance_of(owner_address);
    assert(balance_after == 1000, 'balance should be the same');

    let expected_event = MintComponent::Event::AmountRetrieved(
        MintComponent::AmountRetrieved {
            token_address: second_erc20_address, recipient: owner_address, amount: 1000
        }
    );
    spy.assert_emitted(@array![(minter_address, expected_event)]);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_retrieve_amount_without_owner_role() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = deploy_project();
    // Deploy erc20 used for the minter, and a second erc20 that isn't used
    let contract = snf::declare("USDCarb").expect('Failed to declare contract').contract_class();
    let mut calldata: Array<felt252> = array![user_address.into(), user_address.into()];
    let (erc20_address, _) = contract.deploy(@calldata).expect('Failed to deploy contract');
    calldata = array![user_address.into(), user_address.into()];
    let (second_erc20_address, _) = contract.deploy(@calldata).expect('Failed to deploy contract');
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(second_erc20_address, user_address);
    start_cheat_caller_address(minter_address, owner_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let second_er20 = IERC20Dispatcher { contract_address: second_erc20_address };

    // Transferring incorrect token to minter
    let success = second_er20.transfer(minter_address, 1000);
    assert(success, 'Transfer failed');

    start_cheat_caller_address(minter_address, user_address);
    start_cheat_caller_address(second_erc20_address, minter_address);
    minter.retrieve_amount(second_erc20_address, user_address, 1000);
}

// Integration tests

// 1. Contracts are deployed. Yearly absorptions (vintage supplies) are not set yet. Sale is open.
// 2. Users buy all the available carbon credits. The mint is sold out.
// 3. The maximum amount of carbon mintable is raised and the mint reopened.
// 4. Users buy all the available carbon credits. The mint is closed again.
// 5. Set vintage supplies. Check correct values of the mint.
// 6. Some users transfers some of their tokens to others. Check correct values of transfers.

#[test]
fn integration_test_mint() {
    // [Step 1]
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let alice_address: ContractAddress = contract_address_const::<'ALICE'>();
    let bob_address: ContractAddress = contract_address_const::<'BOB'>();
    let john_address: ContractAddress = contract_address_const::<'JOHN'>();
    let project_address = deploy_project();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter(project_address, erc20_address);

    start_cheat_caller_address(project_address, owner_address);
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    let yearly_absorptions: Span<u256> = get_mock_absorptions();
    setup_project(project_address, yearly_absorptions); // Set vintage supplies
    stop_cheat_caller_address(project_address);

    let minter = IMintDispatcher { contract_address: minter_address };
    let default_max_mintable_cc: u256 = DEFAULT_REMAINING_MINTABLE_CC;

    let remaining_mintable_cc = minter.get_remaining_mintable_cc();
    assert(remaining_mintable_cc == default_max_mintable_cc, 'default remaining value wrong');
    // [Step 2]
    let amount_to_buy: u256 = remaining_mintable_cc / 2;
    buy_utils(owner_address, alice_address, minter_address, amount_to_buy);
    let remaining_mintable_cc_after_buy = minter.get_remaining_mintable_cc();
    assert(
        remaining_mintable_cc_after_buy == default_max_mintable_cc - amount_to_buy,
        'remaining money wrong value 2'
    );

    // store vintage balances of alice
    let mut vintage_balances_alice: Array<u256> = Default::default();
    let vintage = IVintageDispatcher { contract_address: project_address };
    let num_vintages = vintage.get_num_vintages();
    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        }
        let token_id: u256 = (index + 1).into();
        let vintage_balance = project_contract.balance_of(alice_address, token_id);
        vintage_balances_alice.append(vintage_balance);
        index += 1;
    };

    buy_utils(owner_address, bob_address, minter_address, remaining_mintable_cc_after_buy);
    let remaining_cc_after_buying_all = minter.get_remaining_mintable_cc();
    assert(remaining_cc_after_buying_all == 0, 'remaining money wrong value');

    let is_sold_out = minter.is_sold_out();
    assert(is_sold_out, 'should be sold out');
    let is_sale_open = minter.is_public_sale_open();
    assert(!is_sale_open, 'public sale should be closed');

    // [Step 3]
    start_cheat_caller_address(minter_address, owner_address);
    minter.set_public_sale_open(true);
    let is_sale_open = minter.is_public_sale_open();
    assert(is_sale_open, 'public sale should be opened');

    minter.set_max_mintable_cc(default_max_mintable_cc * 2);
    let updated_yearly_absorptions: Span<u256> = get_mock_absorptions_times_2();
    setup_project(
        project_address, updated_yearly_absorptions
    ); // Update vintage supplies to double the amount

    let remaining_mintable_cc_after_reopen = minter.get_remaining_mintable_cc();
    assert(
        remaining_mintable_cc_after_reopen == default_max_mintable_cc, 'remaining money wrong value'
    );

    start_cheat_caller_address(project_address, minter_address);
    buy_utils(owner_address, bob_address, minter_address, remaining_mintable_cc_after_reopen / 2);
    buy_utils(owner_address, john_address, minter_address, remaining_mintable_cc_after_reopen / 2);

    let is_sold_out_after_reopen = minter.is_sold_out();
    assert(is_sold_out_after_reopen, 'should be sold out');
    let is_sale_open_after_reopen = minter.is_public_sale_open();
    assert(!is_sale_open_after_reopen, 'public sale should be closed');

    // check erc20 raised
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    let balance_owner_before = erc20.balance_of(owner_address);
    start_cheat_caller_address(minter_address, owner_address);
    minter.withdraw();
    let balance_owner_after = erc20.balance_of(owner_address);
    let expected_raised_money = minter.get_max_mintable_cc()
        * minter.get_unit_price()
        / MULTIPLIER_TONS_TO_MGRAMS;
    assert(
        equals_with_error(balance_owner_after, balance_owner_before + expected_raised_money, 100),
        'erc20 raised wrong value'
    );

    // [Step 4]
    start_cheat_caller_address(minter_address, owner_address);

    // Alice didn't buy after the max mintable cc was raised, so she should still have the same
    // balance for each vintage
    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        }
        let token_id: u256 = (index + 1).into();
        let vintage_balance = project_contract.balance_of(alice_address, token_id);
        assert(vintage_balance == *vintage_balances_alice.at(index), 'balance should be the same');
        index += 1;
    };

    let total_balance_alice = helper_sum_balance(project_address, alice_address);
    assert(
        equals_with_error(total_balance_alice, default_max_mintable_cc / 2, 100),
        'balance should be the same'
    );

    let total_balance_bob = helper_sum_balance(project_address, bob_address);
    assert(
        equals_with_error(total_balance_bob, default_max_mintable_cc, 100),
        'balance should be the same'
    );
    helper_check_vintage_balances(project_address, alice_address, default_max_mintable_cc / 2);
    let total_balance_john = helper_sum_balance(project_address, john_address);
    assert(
        equals_with_error(total_balance_john, default_max_mintable_cc / 2, 100),
        'balance should be the same'
    );
    helper_check_vintage_balances(project_address, bob_address, default_max_mintable_cc);
    helper_check_vintage_balances(project_address, john_address, default_max_mintable_cc / 2);
}
