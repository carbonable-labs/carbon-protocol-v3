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

/// Deploys the resale contract.
fn deploy_resale(
    project_address: ContractAddress, token_address: ContractAddress
) -> ContractAddress {
    let contract = snf::declare("Resale").expect('Declaration failed');
    let owner: ContractAddress = contract_address_const::<'OWNER'>();
    let mut calldata: Array<felt252> = array![];
    calldata.append(project_address.into());
    calldata.append(owner.into());
    calldata.append(token_address.into());
    calldata.append(owner.into());

    let (contract_address, _) = contract.deploy(@calldata).expect('Resale deployment failed');
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

/// Utility function to buy a certain amount of carbon credits
/// That amount is minted across all vintages
/// If Bob buys 100 carbon credits, and the vintage 2024 has 10% of the total supply,
/// Bob will have 10 carbon credits in 2024
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

    let success = erc20.transfer(caller_address, money_to_buy);
    assert(success, 'Transfer failed');

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
        let token_id = (index + 1).into();
        tokens.append(token_id);
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
        let token_id = (index + 1).into();
        let balance = project.balance_of(user_address, token_id);
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


fn helper_get_cc_amounts(
    project_address: ContractAddress, token_ids: Span<u256>, cc_to_buy: u256
) -> Span<u256> {
    let project = IProjectDispatcher { contract_address: project_address };
    let mut cc_amounts: Array<u256> = Default::default();
    let mut index = 0;
    loop {
        if index >= token_ids.len() {
            break ();
        }
        let token_id = *token_ids.at(index);
        let cc_value = project.internal_to_cc(cc_to_buy, token_id);
        cc_amounts.append(cc_value);
        index += 1;
    };
    cc_amounts.span()
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


fn helper_expected_transfer_single_events(
    project_address: ContractAddress,
    operator: ContractAddress,
    from: ContractAddress,
    to: ContractAddress,
    token_ids: Span<u256>,
    cc_to_buy: u256
) -> Array<(ContractAddress, ERC1155Component::Event)> {
    let project = IProjectDispatcher { contract_address: project_address };
    let mut events: Array<(ContractAddress, ERC1155Component::Event)> = Default::default();
    let mut index = 0;

    loop {
        if index >= token_ids.len() {
            break;
        }

        let value = project.internal_to_cc(cc_to_buy, *token_ids.at(index));
        let token_id = *token_ids.at(index);

        let event = ERC1155Component::Event::TransferSingle(
            ERC1155Component::TransferSingle { operator, from, to, id: token_id, value }
        );

        events.append((project_address, event));

        index += 1;
    };

    events
}


/// Mock data for merkle tree tests

pub const MERKLE_ROOT_FIRST_WAVE: felt252 =
    803781063426407299979325390167664109772842041387232186868510660774343066272;

pub const MERKLE_ROOT_SECOND_WAVE: felt252 =
    3023878233865233747692111000084174893656568287435392306059398425498163029420;

pub fn get_bob_first_wave_allocation() -> (
    felt252, ContractAddress, u128, u128, u128, Array<felt252>
) {
    let address: ContractAddress = contract_address_const::<
        0x1234567890abcdef1234567890abcdef12345678
    >();
    let amount: u128 = 150;
    let timestamp: u128 = 2;
    let id: u128 = 1;

    let proof: Array<felt252> = array![
        0x2fc0d4eecd4e047701f1a8295209d8a4d2b243836f5cf78df91bd073ce49084,
        0x5fed9820061cf127fb1689269a6d53d72c3d1f289aff4bac0afea2103b5f229,
        0x6ef44033073498cfd5dc97338ffe3afd139a87d56c1045ccefc3108a653b6f2,
        0x6b04f0ca9a85505cd6cae37c678dd899f200b92639474e6e594fcf02544ed42,
        0x1855303a4c287845b59acbe58e85df3618e6e3dbc27ffb7554e565ec3a606b0
    ];

    (MERKLE_ROOT_FIRST_WAVE, address, amount, timestamp, id, proof)
}

pub fn get_bob_second_wave_allocation() -> (
    felt252, ContractAddress, u128, u128, u128, Array<felt252>
) {
    let address: ContractAddress = contract_address_const::<
        0x1234567890abcdef1234567890abcdef12345678
    >();
    let amount: u128 = 150;
    let timestamp: u128 = 2;
    let id: u128 = 1;

    let proof: Array<felt252> = array![
        0x2fc0d4eecd4e047701f1a8295209d8a4d2b243836f5cf78df91bd073ce49084,
        0x5fed9820061cf127fb1689269a6d53d72c3d1f289aff4bac0afea2103b5f229,
        0x6ef44033073498cfd5dc97338ffe3afd139a87d56c1045ccefc3108a653b6f2,
        0x6b04f0ca9a85505cd6cae37c678dd899f200b92639474e6e594fcf02544ed42,
        0x1855303a4c287845b59acbe58e85df3618e6e3dbc27ffb7554e565ec3a606b0,
        0x545687bbf6429d9a0664d6892ce9fc45b98f9529229358e252302434d85976c
    ];

    (MERKLE_ROOT_SECOND_WAVE, address, amount, timestamp, id, proof)
}

pub fn get_alice_second_wave_allocation() -> (
    felt252, ContractAddress, u128, u128, u128, Array<felt252>
) {
    let address: ContractAddress = contract_address_const::<
        0xabcdefabcdefabcdefabcdefabcdefabcdefabc
    >();
    let amount: u128 = 800;
    let timestamp: u128 = 13;
    let id: u128 = 1;

    let proof: Array<felt252> = array![
        0x387e71c3fe5c7ed5e81814e57bbdd88c9cc249b9071d626a8669bb8e6fb38bc,
        0x3c1fa52fc063ceea9fdf3790b3d4b86698c7239ca857226957fee50f0ebc01d,
        0x13e92543d838d5c721017891f665092a2b5558f47ac544e5c0a3867c6ba5cbf,
        0x3b69ab80dcf08d633999db77d659e3bb7cb79270a1db1fdf5c432a950375cf7,
        0x45c532062ad92e4bf5e4fc2b755c6cca48b03ae8c89b7eba239a21a3253ac4f,
        0x1c6ec88a48638cc8c14e1c72767d58860a86cefbdd696d24e1253c0f6c1c2a0
    ];

    (MERKLE_ROOT_SECOND_WAVE, address, amount, timestamp, id, proof)
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
    let id_1: u128 = 1;
    let proof1: Array<felt252> = array![
        0x6ac1aae7e68c4e203c00d8eff310bbca90f90ae3badaa8b6f6bf637ee52eec,
        0x2c91a9511ef588d90f7f89f513595c75bc24ea19e18c0bb740dcda20027ca56,
        0x431297a4c5039b6198b4ea942e06c480aa662334f252fb2941c537f458c4ca8,
        0x6b04f0ca9a85505cd6cae37c678dd899f200b92639474e6e594fcf02544ed42,
        0x1855303a4c287845b59acbe58e85df3618e6e3dbc27ffb7554e565ec3a606b0
    ];

    // Allocation 2
    let amount2: u128 = 900;
    let timestamp2: u128 = 17;
    let id_2: u128 = 2;
    let proof2: Array<felt252> = array![
        0x2271d27a5469a12d5854af8d6dd19924b4ce389b347bad9660714d65d5ea849,
        0x2d4f077932acdce076172e418dedd99d369ab390e0ecaa4441346027b280287,
        0x11536a6a75883757f0e46fe84a6c0550c1d72f3a6e827e86c72a86bc200d73a,
        0x2e996dca1817edb8d42d2312b9dbc9ff2f79d5ec3c029b6fe3937f8ded5d01d,
        0x1855303a4c287845b59acbe58e85df3618e6e3dbc27ffb7554e565ec3a606b0
    ];

    // Allocation 3
    let amount3: u128 = 2500;
    let timestamp3: u128 = 0x18;
    let id_3: u128 = 3;
    let proof3: Array<felt252> = array![
        0x243eb22d79b86e04e2665bac9cf3a42465edba7bb8fe1630a821c4593ca781a,
        0x26a185f92c71cf586a662182d4f5dd5ac2812be84e44a0d463bd411b2c5805e,
        0x629b8d38174754785a8d32fee5d790a9aa644df167fc83263888fd70835295,
        0x4d2752b3411df566e417454f8533c2a8a21f61bf6e705d33b6dc3d903c91ca2,
        0x61bdd78c2e4b89f38ef7492670e4744a0885b7c776ffb254d1c9b73c850fdf5
    ];

    // Allocation 4 of the second wave
    let amount4: u128 = 287;
    let timestamp4: u128 = 0xE;
    let id_4: u128 = 4;
    let proof4: Array<felt252> = array![
        0x49118c782a2a6c1ceb9890535f1d2fcca16a8b1d916ca1af4f8eadb7f8b8e0a,
        0x74c176d79348e16a11489735a3fb593c6bc855abed8efbfaa81a29fd9e0a893,
        0x13e92543d838d5c721017891f665092a2b5558f47ac544e5c0a3867c6ba5cbf,
        0x3b69ab80dcf08d633999db77d659e3bb7cb79270a1db1fdf5c432a950375cf7,
        0x45c532062ad92e4bf5e4fc2b755c6cca48b03ae8c89b7eba239a21a3253ac4f,
        0x1c6ec88a48638cc8c14e1c72767d58860a86cefbdd696d24e1253c0f6c1c2a0
    ];

    (
        MERKLE_ROOT_FIRST_WAVE,
        MERKLE_ROOT_SECOND_WAVE,
        address,
        amount1,
        timestamp1,
        id_1,
        amount2,
        timestamp2,
        id_2,
        amount3,
        timestamp3,
        id_3,
        amount4,
        timestamp4,
        id_4,
        proof1,
        proof2,
        proof3,
        proof4
    )
}
