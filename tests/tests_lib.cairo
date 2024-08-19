// Starknet deps

use starknet::{ContractAddress, contract_address_const};

// External deps

use openzeppelin::utils::serde::SerializedAppend;
use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, EventSpy, spy_events, EventSpyTrait, EventSpyAssertionsTrait,
    start_cheat_caller_address, stop_cheat_caller_address
};

// Models 

use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
use carbon_v3::models::constants::{CC_DECIMALS_MULTIPLIER, MULTIPLIER_TONS_TO_MGRAMS};

// Components

use carbon_v3::components::vintage::interface::{
    IVintage, IVintageDispatcher, IVintageDispatcherTrait
};
use carbon_v3::components::minter::interface::{IMint, IMintDispatcher, IMintDispatcherTrait};
use openzeppelin::token::erc1155::ERC1155Component;


// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};


///
/// Mock Data
///

const DEFAULT_REMAINING_MINTABLE_CC: u256 = 80000000000000;
const STARTING_YEAR: u32 = 2024;

fn get_mock_absorptions() -> Span<u256> {
    let absorptions: Span<u256> = array![
        0,
        100000000000,
        479914660000,
        888286050000,
        1184381400000,
        3709225070000,
        6234068740000,
        8758912410000,
        11283756080000,
        13808599760000,
        20761757210000,
        27714914660000,
        34668072120000,
        41621229570000,
        48574387030000,
        55527544480000,
        62480701930000,
        69433859390000,
        76387016840000,
        80000000000000,
        82500000000000,
    ]
        .span();

    let mut yearly_absorptions: Array<u256> = array![];
    let mut index: u32 = 0;
    loop {
        if index >= absorptions.len() - 1 {
            break;
        }
        let current_abs = *absorptions.at(index + 1) - *absorptions.at(index);
        yearly_absorptions.append(current_abs);
        index += 1;
    };

    let yearly_absorptions = yearly_absorptions.span();
    yearly_absorptions
}

fn get_mock_absorptions_times_2() -> Span<u256> {
    let yearly_absorptions: Span<u256> = get_mock_absorptions();
    let mut yearly_absorptions_times_2: Array<u256> = array![];
    let mut index = 0;
    loop {
        if index >= yearly_absorptions.len() {
            break;
        }
        yearly_absorptions_times_2.append(*yearly_absorptions.at(index) * 2);
        index += 1;
    };
    yearly_absorptions_times_2.span()
}


///
/// Math functions
/// 

fn equals_with_error(a: u256, b: u256, error: u256) -> bool {
    let diff = if a > b {
        a - b
    } else {
        b - a
    };
    diff <= error
}

///
/// Deploy and setup functions
/// 

fn deploy_project() -> ContractAddress {
    let contract = snf::declare("Project").expect('Declaration failed');
    let number_of_years: u64 = 20;
    let mut calldata: Array<felt252> = array![
        contract_address_const::<'OWNER'>().into(), STARTING_YEAR.into(), number_of_years.into()
    ];
    let (contract_address, _) = contract.deploy(@calldata).expect('Project deployment failed');

    contract_address
}

fn setup_project(contract_address: ContractAddress, yearly_absorptions: Span<u256>) {
    let vintages = IVintageDispatcher { contract_address };
    // Fake the owner to call set_vintages and set_project_carbon which can only be run by owner
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    start_cheat_caller_address(contract_address, owner_address);
    vintages.set_vintages(yearly_absorptions, STARTING_YEAR);
    stop_cheat_caller_address(contract_address);
}

fn default_setup_and_deploy() -> ContractAddress {
    let project_address = deploy_project();
    let yearly_absorptions: Span<u256> = get_mock_absorptions();
    setup_project(project_address, yearly_absorptions);
    project_address
}

/// Deploys the offsetter contract.
fn deploy_offsetter(project_address: ContractAddress) -> ContractAddress {
    let contract = snf::declare("Offsetter").expect('Declaration failed');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    let mut calldata: Array<felt252> = array![];
    calldata.append(project_address.into());
    calldata.append(owner.into());

    let (contract_address, _) = contract.deploy(@calldata).expect('Offsetter deployment failed');

    contract_address
}

/// Deploys a minter contract.
fn deploy_minter(
    project_address: ContractAddress, payment_address: ContractAddress
) -> ContractAddress {
    let contract = snf::declare("Minter").expect('Declaration failed');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    start_cheat_caller_address(project_address, owner);
    let public_sale: bool = true;
    let low: felt252 = DEFAULT_REMAINING_MINTABLE_CC.low.into();
    let high: felt252 = DEFAULT_REMAINING_MINTABLE_CC.high.into();
    let unit_price: felt252 = 11;
    let mut calldata: Array<felt252> = array![
        project_address.into(),
        payment_address.into(),
        public_sale.into(),
        low,
        high,
        unit_price,
        0,
        owner.into()
    ];

    let (contract_address, _) = contract.deploy(@calldata).expect('Minter deployment failed');
    contract_address
}

fn deploy_minter_specific_max_mintable(
    project_address: ContractAddress, payment_address: ContractAddress, max_mintable_cc: u256
) -> ContractAddress {
    let contract = snf::declare("Minter").expect('Declaration failed');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    let low: felt252 = max_mintable_cc.low.into();
    let high: felt252 = max_mintable_cc.high.into();
    start_cheat_caller_address(project_address, owner);
    let public_sale: bool = true;
    let unit_price: felt252 = 11;
    let mut calldata: Array<felt252> = array![
        project_address.into(),
        payment_address.into(),
        public_sale.into(),
        low,
        high,
        unit_price,
        0,
        owner.into()
    ];

    let (contract_address, _) = contract.deploy(@calldata).expect('Minter deployment failed');
    contract_address
}

/// Deploy erc20 contract.
fn deploy_erc20() -> ContractAddress {
    let contract = snf::declare("USDCarb").expect('Declaration failed');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    let mut calldata: Array<felt252> = array![];
    calldata.append(owner.into());
    calldata.append(owner.into());
    let (contract_address, _) = contract.deploy(@calldata).expect('Erc20 deployment failed');

    contract_address
}

fn fuzzing_setup(cc_supply: u256) -> (ContractAddress, ContractAddress, ContractAddress) {
    let project_address = deploy_project();
    let erc20_address = deploy_erc20();
    let minter_address = deploy_minter_specific_max_mintable(
        project_address, erc20_address, cc_supply
    );

    // Tests are done on a single vintage, thus the yearly supply are the same
    let mut total_absorption = 0;
    let mut index = 0;
    let num_vintages: usize = 20;
    let mut yearly_absorptions: Array<u256> = Default::default();
    let mock_absorptions = get_mock_absorptions();
    loop {
        if index >= num_vintages {
            break;
        }
        total_absorption += cc_supply;
        yearly_absorptions.append(cc_supply);
        index += 1;
    };
    setup_project(project_address, mock_absorptions);
    (project_address, minter_address, erc20_address)
}

/// Utility function to buy a share of the total supply.
/// The share is calculated as a percentage of the total supply. We use share instead of amount
/// to make it easier to determine the expected values, but in practice the amount is used.
fn buy_utils(
    owner_address: ContractAddress,
    caller_address: ContractAddress,
    minter_address: ContractAddress,
    total_cc_amount: u256
) {
    // [Prank] Use caller (usually user) as caller for the Minter contract
    start_cheat_caller_address(minter_address, caller_address);
    let minter = IMintDispatcher { contract_address: minter_address };
    let erc20_address: ContractAddress = minter.get_payment_token_address();
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };

    // If user wants to buy 1 carbon credit, the input should be 1*MULTIPLIER_TONS_TO_MGRAMS
    let money_to_buy = total_cc_amount * minter.get_unit_price() / MULTIPLIER_TONS_TO_MGRAMS;

    // [Prank] Use owner as caller for the ERC20 contract
    start_cheat_caller_address(erc20_address, owner_address); // Owner holds initial supply

    erc20.transfer(caller_address, money_to_buy);

    // [Prank] Use caller address (usually user) as caller for the ERC20 contract
    start_cheat_caller_address(erc20_address, caller_address);
    erc20.approve(minter_address, money_to_buy);

    // [Prank] Use Minter as caller for the ERC20 contract
    start_cheat_caller_address(erc20_address, minter_address);
    // [Prank] Use caller (usually user) as caller for the Minter contract
    start_cheat_caller_address(minter_address, caller_address);
    minter.public_buy(total_cc_amount);

    stop_cheat_caller_address(minter_address);
    stop_cheat_caller_address(erc20_address);
}


///
/// Tests functions to be called by the test runner
/// 

fn perform_fuzzed_transfer(
    raw_supply: u256,
    raw_cc_amount: u256,
    raw_last_digits_share: u256,
    percentage_of_balance_to_send: u256,
    max_supply_for_vintage: u256
) {
    let supply = raw_supply % max_supply_for_vintage;
    if raw_cc_amount == 0 || supply == 0 {
        return;
    }

    let cc_amount_to_buy = raw_cc_amount % supply;
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let (project_address, minter_address, _) = fuzzing_setup(supply);
    let project = IProjectDispatcher { contract_address: project_address };
    // Setup Roles for the contracts
    start_cheat_caller_address(project_address, owner_address);
    project.grant_minter_role(minter_address);
    start_cheat_caller_address(project_address, minter_address);
    buy_utils(owner_address, user_address, minter_address, cc_amount_to_buy);
    let sum_balance = helper_sum_balance(project_address, user_address);
    assert(equals_with_error(sum_balance, cc_amount_to_buy, 100), 'Error sum balance');

    start_cheat_caller_address(project_address, user_address);

    // Check the balance of the user, total cc amount bought should be distributed proportionally
    helper_check_vintage_balances(project_address, user_address, cc_amount_to_buy);

    // Receiver should have 0 cc
    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    helper_check_vintage_balances(project_address, receiver_address, 0);

    let token_id = 1;
    let balance_vintage_user_before = project.balance_of(user_address, token_id);
    start_cheat_caller_address(project_address, user_address);
    project
        .safe_transfer_from(
            user_address, receiver_address, token_id, balance_vintage_user_before, array![].span()
        );

    let balance_vintage_user_after = project.balance_of(user_address, token_id);
    assert(equals_with_error(balance_vintage_user_after, 0, 100), 'Error balance vintage user');

    let balance_vintage_receiver = project.balance_of(receiver_address, token_id);
    assert(
        equals_with_error(balance_vintage_receiver, balance_vintage_user_before, 100),
        'Error balance vintage receiver'
    );

    start_cheat_caller_address(project_address, receiver_address);
    project
        .safe_transfer_from(
            receiver_address, user_address, token_id, balance_vintage_receiver, array![].span()
        );

    let balance_vintage_user_after = project.balance_of(user_address, token_id);
    assert(
        equals_with_error(balance_vintage_user_after, balance_vintage_user_before, 100),
        'Error balance vintage user'
    );

    let balance_vintage_receiver = project.balance_of(receiver_address, token_id);
    assert(equals_with_error(balance_vintage_receiver, 0, 100), 'Error balance vintage receiver');
}

fn helper_get_token_ids(project_address: ContractAddress) -> Span<u256> {
    let vintages = IVintageDispatcher { contract_address: project_address };
    let num_vintages: usize = vintages.get_num_vintages();
    let mut tokens: Array<u256> = Default::default();
    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        }
        tokens.append(index.into());
        index += 1;
    };
    tokens.span()
}

fn helper_sum_balance(project_address: ContractAddress, user_address: ContractAddress) -> u256 {
    let project = IProjectDispatcher { contract_address: project_address };
    let vintage = IVintageDispatcher { contract_address: project_address };
    let num_vintages: usize = vintage.get_num_vintages();
    let mut total_balance: u256 = 0;

    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        }
        let balance = project.balance_of(user_address, index.into());
        total_balance += balance;
        index += 1;
    };
    total_balance
}

fn helper_check_vintage_balances(
    project_address: ContractAddress, user_address: ContractAddress, total_cc_bought: u256
) {
    let project = IProjectDispatcher { contract_address: project_address };
    let vintages = IVintageDispatcher { contract_address: project_address };
    let num_vintages: usize = vintages.get_num_vintages();
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let token_ids = helper_get_token_ids(project_address);
    let mut index = 0;
    loop {
        if index >= num_vintages {
            break;
        }
        let token_id = *token_ids.at(index);
        let proportion_supply = vintages.get_carbon_vintage(token_id).supply
            * CC_DECIMALS_MULTIPLIER
            / initial_total_supply;
        let balance = project.balance_of(user_address, token_id);
        let expected_balance = total_cc_bought * proportion_supply / CC_DECIMALS_MULTIPLIER;
        assert(equals_with_error(balance, expected_balance, 10), 'Error vintage balance');
        index += 1;
    };
}

fn helper_check_vintage_balance(
    project_address: ContractAddress,
    user_address: ContractAddress,
    token_id: u256,
    total_cc_bought: u256
) {
    let project = IProjectDispatcher { contract_address: project_address };
    let vintages = IVintageDispatcher { contract_address: project_address };
    let initial_total_supply = vintages.get_initial_project_cc_supply();
    let proportion_supply = vintages.get_carbon_vintage(token_id).supply
        * CC_DECIMALS_MULTIPLIER
        / initial_total_supply;
    let balance = project.balance_of(user_address, token_id);
    let expected_balance = total_cc_bought * proportion_supply / CC_DECIMALS_MULTIPLIER;
    assert(equals_with_error(balance, expected_balance, 10), 'Error vintage balance');
}

fn helper_expected_transfer_event(
    project_address: ContractAddress,
    operator: ContractAddress,
    from: ContractAddress,
    to: ContractAddress,
    token_ids: Span<u256>,
    total_cc_amount: u256
) -> ERC1155Component::Event {
    let project = IProjectDispatcher { contract_address: project_address };
    if token_ids.len() == 1 {
        ERC1155Component::Event::TransferSingle(
            ERC1155Component::TransferSingle {
                operator, from, to, id: *token_ids.at(0), value: total_cc_amount
            }
        )
    } else {
        let mut values: Array<u256> = Default::default();
        let mut index = 0;
        loop {
            if index >= token_ids.len() {
                break;
            }
            let value = project.internal_to_cc(total_cc_amount, *token_ids.at(index));
            values.append(value);
            index += 1;
        };
        let values = values.span();
        ERC1155Component::Event::TransferBatch(
            ERC1155Component::TransferBatch { operator, from, to, ids: token_ids, values }
        )
    }
}


/// Mock data for merkle tree tests
pub const MERKLE_ROOT_FIRST_WAVE: felt252 =
    1586727653310658130441223142145636802822549738865763467559937699735593529518;

pub const MERKLE_ROOT_SECOND_WAVE: felt252 =
    1254903502166521005693176785783698867375816882648399305753662436577997689730;

pub fn get_bob_first_wave_allocation() -> (felt252, ContractAddress, u128, u128, Array<felt252>) {
    let address: ContractAddress = contract_address_const::<
        0x1234567890abcdef1234567890abcdef12345678
    >();
    let amount: u128 = 150;
    let timestamp: u128 = 2;

    let proof: Array<felt252> = array![
        0xb93b7d65a7e5c7a15def73a61485111e2f630cc8e6683fb98f4d6ca2c7ec96,
        0x91ca2d84afc873630898de633b3041683eea2a5d1d59ae4f3bed3551bb4294,
        0x61c8f928bb4f7b5a3ae252cc4c78f3bdb3442733951a1de12ec01e7a4812a50,
        0x6f0149c2ccc9a95bb64deda90572a912f85139505ea9bcd233f6d16e751af9e,
        0x58e3b614e77af3c7256a74654907b4fe2182daf47da635a81c94629a89595b3
    ];

    (MERKLE_ROOT_FIRST_WAVE, address, amount, timestamp, proof)
}

pub fn get_bob_combined_wave_allocation() -> (
    felt252, ContractAddress, u128, u128, Array<felt252>
) {
    let address: ContractAddress = contract_address_const::<
        0x1234567890abcdef1234567890abcdef12345678
    >();
    let amount: u128 = 150;
    let timestamp: u128 = 2;

    let proof: Array<felt252> = array![
        0xb93b7d65a7e5c7a15def73a61485111e2f630cc8e6683fb98f4d6ca2c7ec96,
        0x91ca2d84afc873630898de633b3041683eea2a5d1d59ae4f3bed3551bb4294,
        0x61c8f928bb4f7b5a3ae252cc4c78f3bdb3442733951a1de12ec01e7a4812a50,
        0x6f0149c2ccc9a95bb64deda90572a912f85139505ea9bcd233f6d16e751af9e,
        0x58e3b614e77af3c7256a74654907b4fe2182daf47da635a81c94629a89595b3,
        0x57e12be54078fb13aef7df28595941bab33c77cc04b5c74069221be888b182e
    ];

    (MERKLE_ROOT_SECOND_WAVE, address, amount, timestamp, proof)
}

pub fn get_alice_combined_wave_allocation() -> (
    felt252, ContractAddress, u128, u128, Array<felt252>
) {
    let address: ContractAddress = contract_address_const::<
        0xabcdefabcdefabcdefabcdefabcdefabcdefabc
    >();
    let amount: u128 = 800;
    let timestamp: u128 = 13;

    let proof: Array<felt252> = array![
        0x67325b9f9f8c14bc7f6e5e61e18beb7e2e413c8045b3e66474b1a9da48675ff,
        0x22cb6a40bcd35b2f143d4fa3556ab6d161bd2d8476fd9113ff12d217a4453d3,
        0x2e355a04aa50c953c458afd1716299e77d8df356f2a3f47a59668a13075f22a,
        0x345b1e11be2309ccf90b7ec5b05b5987a1c4fd9ba232c17918b24144f022666,
        0x427e1a5312507023d5cccfca1919876d1cba3c19278bed6b380722b7c86307c,
        0x3820e57b614f240d6fd07351258ad6f626c5326cf78b8fa6dd54d59e243b0ae
    ];

    (MERKLE_ROOT_SECOND_WAVE, address, amount, timestamp, proof)
}

pub fn get_john_multiple_allocations() -> (
    felt252,
    felt252,
    ContractAddress,
    u128,
    u128,
    u128,
    u128,
    u128,
    u128,
    u128,
    u128,
    Array<felt252>,
    Array<felt252>,
    Array<felt252>,
    Array<felt252>
) {
    let address: ContractAddress = contract_address_const::<
        0xabcdefabcdef1234567890abcdef1234567890ab
    >();

    // Allocation 1
    let amount1: u128 = 700;
    let timestamp1: u128 = 0x6;
    let proof1: Array<felt252> = array![
        0x46d60ec37dc40ed4b156d95958274dbfb7fce273065825eb65c32d4979eb9c1,
        0x53b3b627301bebe2ba22317925fa58814e752a9c2af25f7508a6c2546afb4af,
        0x5c317f3f86b325fe1aed8103dafccaaafbc0f49ddaeb163b72c574abdcd43ec,
        0x6f0149c2ccc9a95bb64deda90572a912f85139505ea9bcd233f6d16e751af9e,
        0x58e3b614e77af3c7256a74654907b4fe2182daf47da635a81c94629a89595b3
    ];

    // Allocation 2
    let amount2: u128 = 900;
    let timestamp2: u128 = 17;
    let proof2: Array<felt252> = array![
        0x1a6e2d03ba7596b143278be0ad0a83e1a2523ee888c75c8b19343509f07e821,
        0x17105708ca2b9efbf1a463b90528c603ed7a23a9493cf65686e36675f05f2f3,
        0x193077a554a313efa6387d3edc11c60a34be8181b69d599e064b26f099b4949,
        0x21ff61c9c9e525d2039631f6fa2e0a34b9de20db17438d049bd369804abb59,
        0x58e3b614e77af3c7256a74654907b4fe2182daf47da635a81c94629a89595b3
    ];

    // Allocation 3
    let amount3: u128 = 2500;
    let timestamp3: u128 = 0x18;
    let proof3: Array<felt252> = array![
        0x441810f7802690cd80d39973ba93d97a5326446ebfc01cb6e0eefb4c08e8247,
        0x39f4c300dccca2d76be4ea9951a27045a19c2e647960625755e2b1dd8857658,
        0x59ceaf2eada3198f6fd5ab51d9c374d5a8f0f0d057bba27ca7fb84d319413cb,
        0x130aafa443c502bee0cae358d7d11bef44bf93e8d87df7f3958c11357d989df,
        0x4da2c390813b19356e461046c235956b07a8cd8e914d64811d1c2293a718299
    ];

    // Allocation 4 of the second wave
    let amount4: u128 = 287;
    let timestamp4: u128 = 0xE;
    let proof4: Array<felt252> = array![
        0x47ea9d24e7603c67574fc78a104fa2cc5cb7f4511f343b601b640c0ea6ef565,
        0x3b832e149066bee8ec296d905fab1d1200714894a80216e5de233435066f09c,
        0x2e355a04aa50c953c458afd1716299e77d8df356f2a3f47a59668a13075f22a,
        0x345b1e11be2309ccf90b7ec5b05b5987a1c4fd9ba232c17918b24144f022666,
        0x427e1a5312507023d5cccfca1919876d1cba3c19278bed6b380722b7c86307c,
        0x3820e57b614f240d6fd07351258ad6f626c5326cf78b8fa6dd54d59e243b0ae
    ];

    (
        MERKLE_ROOT_FIRST_WAVE,
        MERKLE_ROOT_SECOND_WAVE,
        address,
        amount1,
        timestamp1,
        amount2,
        timestamp2,
        amount3,
        timestamp3,
        amount4,
        timestamp4,
        proof1,
        proof2,
        proof3,
        proof4
    )
}
