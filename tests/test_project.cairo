use snforge_std::cheatcodes::events::EventsFilterTrait;
use snforge_std::cheatcodes::events::EventSpyTrait;
use snforge_std::cheatcodes::events::EventSpyAssertionsTrait;
// TODO: use token_ids instead of years as vintage
// Starknet deps

use starknet::{ContractAddress, contract_address_const, get_caller_address, ClassHash};

// External deps

use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc1155::ERC1155Component;
use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, EventSpy, start_cheat_caller_address, stop_cheat_caller_address, spy_events
};

// Models 

use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
use carbon_v3::models::constants::{CC_DECIMALS_MULTIPLIER, MULTIPLIER_TONS_TO_MGRAMS};

// Components

use carbon_v3::components::vintage::interface::{
    IVintage, IVintageDispatcher, IVintageDispatcherTrait
};
use carbon_v3::components::minter::interface::{IMint, IMintDispatcher, IMintDispatcherTrait};
use carbon_v3::components::metadata::{IMetadataHandlerDispatcher, IMetadataHandlerDispatcherTrait};
use erc4906::erc4906_component::ERC4906Component::{Event, MetadataUpdate, BatchMetadataUpdate};

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

/// Utils for testing purposes
/// 
use super::tests_lib::{
    equals_with_error, deploy_project, setup_project, default_setup_and_deploy,
    perform_fuzzed_transfer, buy_utils, deploy_erc20, deploy_minter, deploy_offsetter,
    helper_sum_balance, helper_check_vintage_balances, helper_get_token_ids,
    helper_expected_transfer_event
};

// #[test]
// fn test_project_mint() {
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     let user_address: ContractAddress = contract_address_const::<'USER'>();
//     let project_address = default_setup_and_deploy();
//     let erc20_address = deploy_erc20();
//     let minter_address = deploy_minter(project_address, erc20_address);
//     let vintages = IVintageDispatcher { contract_address: project_address };

//     start_cheat_caller_address(project_address, owner_address);
//     let project_contract = IProjectDispatcher { contract_address: project_address };
//     project_contract.grant_minter_role(minter_address);
//     start_cheat_caller_address(project_address, minter_address);

//     let mut spy: EventSpy = spy_events();

//     let cc_to_mint = 1000*MULTIPLIER_TONS_TO_MGRAMS; // 10 CC
//     // println!("CC_MULTIPLIER: {}", CC_DECIMALS_MULTIPLIER);
//     let initial_project_supply = vintages.get_initial_project_cc_supply();
//     // println!("initial_project_supply: {}", initial_project_supply);

//     let token_id: u256 = 1;
//     project_contract.mint(user_address, token_id, cc_to_mint);
//     let balance = project_contract.balance_of(user_address, token_id);

//     // println!("balance: {}", balance);
//     // println!("cc_to_mint: {}", cc_to_mint);

//     assert(equals_with_error(balance, cc_to_mint, 10), 'Error of balance');
//     // let expected_event_1155_transfer_single = ERC1155Component::Event::TransferSingle(
//     //     ERC1155Component::TransferSingle {
//     //         operator: minter_address,
//     //         from: Zeroable::zero(),
//     //         to: user_address,
//     //         id: token_id,
//     //         value: share
//     //     }
//     // );
//     // spy.assert_emitted(@array![(project_address, expected_event_1155_transfer_single)]);
// }

// // #[test]
// // #[should_panic(expected: 'Only Minter can mint')]
// // fn test_project_mint_without_minter_role() {
// //     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
// //     let project_address = default_setup_and_deploy();
// //     let erc20_address = deploy_erc20();
// //     let minter_address = deploy_minter(project_address, erc20_address);

// //     start_cheat_caller_address(project_address, minter_address);
// //     let project_contract = IProjectDispatcher { contract_address: project_address };

// //     let initial_total_supply = vintages.get_initial_project_cc_supply();
// //     let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

// //     let token_id: u256 = 1;
// //     project_contract.mint(owner_address, token_id, cc_to_mint);
// // }

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

        cc_values.append(cc_to_mint);
        tokens.append(index.into());
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
    let project_contract = IProjectDispatcher { contract_address: project_address };
    project_contract.grant_minter_role(minter_address);
    stop_cheat_caller_address(project_address);
    start_cheat_caller_address(project_address, minter_address);

    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let cc_to_mint = initial_total_supply / 10; // 10% of the total supply

    let num_vintages = vintages.get_num_vintages();
    let mut cc_values: Array<u256> = Default::default();
    let mut tokens: Array<u256> = Default::default();
    let mut index = 0; // todo replace this loop by instant init like in rust
    loop {
        if index >= num_vintages {
            break;
        };
        cc_values.append(cc_to_mint);
        tokens.append(index.into());
        index += 1;
    };
    let token_ids = tokens.span();

    let mut spy = spy_events();
    project_contract.batch_mint(user_address, token_ids, cc_values.span());

    let token_ids = helper_get_token_ids(project_address);
    let expected_event = helper_expected_transfer_event(
        project_address, minter_address, Zeroable::zero(), user_address, token_ids, cc_to_mint
    );
    spy.assert_emitted(@array![(project_address, expected_event)]);

    let total_cc_balance = helper_sum_balance(project_address, user_address);
    assert(equals_with_error(total_cc_balance, cc_to_mint, 10), 'Error of balance');

    helper_check_vintage_balances(project_address, user_address, cc_to_mint);
}

#[test]
fn test_project_offset_with_offsetter_role() {
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

    // let mut spy = spy_events();
    start_cheat_caller_address(project_address, offsetter_address);
    project.burn(user_address, token_id, balance);
// let expected_event_1155_transfer_single = ERC1155Component::Event::TransferSingle(
//     ERC1155Component::TransferSingle {
//         operator: offsetter_address,
//         from: user_address,
//         to: Zeroable::zero(),
//         id: token_id,
//         value: share_value
//     }
// );
// spy.assert_emitted(@array![(project_address, expected_event_1155_transfer_single)]);
}

#[test]
#[should_panic(expected: 'Only Offsetter can burn')]
fn test_project_offset_without_offsetter_role() {
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
fn test_project_batch_offset_with_offsetter_role() {
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

    let num_vintages = vintages.get_num_vintages();
    let mut cc_distribution: Array<u256> = Default::default();
    let mut tokens: Array<u256> = Default::default();
    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        };

        cc_distribution.append(cc_to_mint / num_vintages.into());
        tokens.append(index.into());
        index += 1;
    };
    let cc_distribution = cc_distribution.span();
    let token_ids = tokens.span();

    // let mut spy = spy_events();

    start_cheat_caller_address(project_address, offsetter_address);
    project.batch_burn(user_address, token_ids, cc_distribution);
// let expected_event_1155_transfer = ERC1155Component::Event::TransferBatch(
//     ERC1155Component::TransferBatch {
//         operator: offsetter_address,
//         from: user_address,
//         to: Zeroable::zero(),
//         ids: token_ids,
//         values: cc_distribution
//     }
// );
// spy.assert_emitted(@array![(project_address, expected_event_1155_transfer)]);
}

#[test]
#[should_panic(expected: 'Only Offsetter can batch burn')]
fn test_project_batch_offset_without_offsetter_role() {
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

        cc_distribution.append(share);
        index += 1;
        tokens.append(index.into())
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
fn fuzz_test_transfer_low_supply_low_amount(
    raw_supply: u256, raw_share: u256, raw_last_digits_share: u256
) {
    // // raw_supply: 40308303510568861685301840015848943638465596496433240935279427704959025456187, raw_share: 82052526374318839063375537267627101820709454184311168128196446873782799452311, raw_last_digits_share: 2802239975545803120466959565995984850023397563733207324335203449621603735810
    // let raw_supply: u256 = 40308303510568861685301840015848943638465596496433240935279427704959025456187;
    // let raw_share: u256 = 82052526374318839063375537267627101820709454184311168128196446873782799452311;
    // let raw_last_digits_share: u256 = 2802239975545803120466959565995984850023397563733207324335203449621603735810;
    // max supply of a vintage is 10 CC, so 10^9gm of CC
    let max_supply_for_vintage: u256 = 10 * MULTIPLIER_TONS_TO_MGRAMS;
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
    raw_supply: u256, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10 CC, so 10^9gm of CC
    let max_supply_for_vintage: u256 = 10 * MULTIPLIER_TONS_TO_MGRAMS;
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
    raw_supply: u256, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10 CC, so 10^9gm of CC
    let max_supply_for_vintage: u256 = 10 * MULTIPLIER_TONS_TO_MGRAMS;
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
    raw_supply: u256, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10k CC in mgrams
    let max_supply_for_vintage: u256 = 10_000 * MULTIPLIER_TONS_TO_MGRAMS;
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
fn fuzz_test_transfer_medium_supply_medium_amount() {
    // raw_supply: u256, raw_share: u256, raw_last_digits_share: u256
    let raw_supply: u256 =
        94365046484817720939114948484448518925066696628864318182885849195794093634788;
    let raw_share: u256 =
        4548283413067176522814831837630882751146624989433986105735746239485922369869;
    let raw_last_digits_share: u256 =
        36883864587092468979195546282466206646048056734594801592409364701103152608278;
    // max supply of a vintage is 10k CC in mgrams
    let max_supply_for_vintage: u256 = 10_000 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 300; // with 2 digits after the comma, so 3%
    // println!("raw_supply: {}, raw_share: {}, raw_last_digits_share: {}", raw_supply, raw_share, raw_last_digits_share);
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
    raw_supply: u256, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10k CC in mgrams
    let max_supply_for_vintage: u256 = 10_000 * MULTIPLIER_TONS_TO_MGRAMS;
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
fn fuzz_test_transfer_high_supply_low_amount( // raw_supply: u256, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10M CC in mgrams
    let max_supply_for_vintage: u256 = 10_000_000 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 1; // with 2 digits after the comma, so 0.01%

    let raw_supply = 110031889472511083670363002860459421466580476352140151480284168545104461300044;
    let raw_share = 8705161503140068071018661352234439726289024200679691002570881155635338172122;
    let raw_last_digits_share =
        105445079905597346800075221358915599979072479728537949409476616114042104613629;
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
    raw_supply: u256, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10M CC in mgrams
    let max_supply_for_vintage: u256 = 10_000_000 * MULTIPLIER_TONS_TO_MGRAMS;
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
    raw_supply: u256, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10M CC in mgrams
    let max_supply_for_vintage: u256 = 10_000_000 * MULTIPLIER_TONS_TO_MGRAMS;
    let percentage_of_balance_to_send = 10_000; // with 2 digits after the comma, so 100%
    perform_fuzzed_transfer(
        raw_supply,
        raw_share,
        raw_last_digits_share,
        percentage_of_balance_to_send,
        max_supply_for_vintage
    );
}

// #[test]
// fn test_project_metadata_update() {
//     let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
//     let project_address = default_setup_and_deploy();
//     let project_contract = IProjectDispatcher { contract_address: project_address };
//     let erc1155_meta = IERC1155MetadataURIDispatcher { contract_address: project_address };
//     let mut spy = spy_events();
//     let base_uri: ByteArray = format!("{}", 'uri');
//     let mut new_uri: ByteArray = format!("{}", 'new/uri');

//     start_cheat_caller_address(project_address, owner_address);

//     let vintage = 1;
//     assert(erc1155_meta.uri(vintage) == base_uri, 'Wrong base token URI');

//     project_contract.set_uri(new_uri.clone());
//     assert(erc1155_meta.uri(vintage) == new_uri.clone(), 'Wrong updated token URI');

//     let expected_batch_metadata_update = BatchMetadataUpdate {
//         from_token_id: 0,
//         to_token_id: 1
//     };
//     spy.assert_emitted(@array![(project_address, expected_batch_metadata_update)]);
// }

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

    assert(project_decimals == 8, 'Decimals should be 8');
}

#[test]
fn test_shares_of() {
    let project_address = default_setup_and_deploy();
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let token_id: u256 = 1;
    let share_balance = project_contract.shares_of(project_address, token_id);

    assert(share_balance == 0, 'Shares Balance is wrong');
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
