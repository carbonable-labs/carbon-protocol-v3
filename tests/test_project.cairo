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

/// Deploys a project contract.
fn deploy_project() -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Project');
    let uri = 'uri';
    let starting_year: u64 = 2024;
    let number_of_years: u64 = 20;
    let mut calldata: Array<felt252> = array![];
    calldata.append(uri);
    calldata.append(c::OWNER().into());
    calldata.append(starting_year.into());
    calldata.append(number_of_years.into());
    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

/// Sets up the project contract.
fn setup_project(
    contract_address: ContractAddress,
    project_carbon: u256,
    times: Span<u64>,
    absorptions: Span<u64>
) {
    let project = IAbsorberDispatcher { contract_address };

    project.set_absorptions(times, absorptions);
    project.set_project_carbon(project_carbon);
}

fn default_setup() -> (ContractAddress, EventSpy) {
    let (project_address, spy) = deploy_project();

    let times: Span<u64> = array![
        1674579600,
        1706115600,
        1737738000,
        1769274000,
        1800810000,
        1832346000,
        1863968400,
        1895504400,
        1927040400,
        1958576400,
        1990198800,
        2021734800,
        2053270800,
        2084806800,
        2116429200,
        2147965200,
        2179501200,
        2211037200,
        2242659600,
        2274195600
    ]
        .span();

    let absorptions: Span<u64> = array![
        0,
        1000000000,
        4799146600,
        8882860500,
        11843814000,
        37092250700,
        62340687400,
        87589124100,
        112837560800,
        138085997600,
        207617572100,
        277149146600,
        346680721200,
        416212295700,
        485743870300,
        555275444800,
        624807019300,
        694338593900,
        763870168400,
        800000000000
    ]
        .span();

    setup_project(project_address, 8000000000, times, absorptions,);

    (project_address, spy)
}

fn fuzzing_setup(cc_supply: u64) -> (ContractAddress, EventSpy) {
    let (project_address, spy) = deploy_project();

    let times: Span<u64> = array![
        1674579600,
        1706115600,
        1737738000,
        1769274000,
        1800810000,
        1832346000,
        1863968400,
        1895504400,
        1927040400,
        1958576400,
        1990198800,
        2021734800,
        2053270800,
        2084806800,
        2116429200,
        2147965200,
        2179501200,
        2211037200,
        2242659600,
        2274195600
    ]
        .span();

    let absorptions: Span<u64> = array![
        0,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply,
        cc_supply
    ]
        .span();

    setup_project(project_address, 8000000000, times, absorptions,);

    (project_address, spy)
}

/// Mint shares without the minter contract. Testing purposes only.
fn mint_utils(project_address: ContractAddress, owner_address: ContractAddress, share: u256) {
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let cc_vintage_years: Span<u256> = cc_handler.get_vintage_years();
    let n = cc_vintage_years.len();

    let mut cc_shares: Array<u256> = ArrayTrait::<u256>::new();
    let mut index = 0;
    loop {
        if index == n {
            break;
        }
        cc_shares.append(share);
        index += 1;
    };
    let cc_shares = cc_shares.span();

    let project = IProjectDispatcher { contract_address: project_address };
    project.batch_mint(owner_address, cc_vintage_years, cc_shares);
}

fn equals_with_error(a: u256, b: u256, error: u256) -> bool {

    let diff = if a > b {
        a - b
    } else {
        b - a
    };
    diff <= error
}

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
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup();
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
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    carbon_credits.update_vintage_status(2025, 3);
    let vinatge: CarbonVintage = carbon_credits.get_carbon_vintage(2025);
    assert(vinatge.status == CarbonVintageType::Audited, 'Error of status');
}

/// Test balance_of
#[test]
fn test_project_balance_of() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    let share = 33 * CC_DECIMALS_MULTIPLIER;    
    mint_utils(project_address, owner_address, share);

    let supply_vintage_2025 = carbon_credits.get_specific_carbon_vintage(2025).cc_supply;
    let expected_balance = supply_vintage_2025.into() * share / CC_DECIMALS_MULTIPLIER /100;
    let balance = project_contract.balance_of(owner_address, 2025);
    assert(equals_with_error(balance, expected_balance, 100), 'Error of balance');
}

#[test]
fn test_transfer_without_loss() {
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };

    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    let share = 33 * CC_DECIMALS_MULTIPLIER;
    mint_utils(project_address, owner_address, share);

    let supply_vintage_2025 = carbon_credits.get_specific_carbon_vintage(2025).cc_supply;
    let expected_balance = supply_vintage_2025.into() * share / CC_DECIMALS_MULTIPLIER /100;
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
    assert(equals_with_error(receiver_balance, expected_balance, 100), 'Error of receiver balance 2');
}

#[test]
fn test_transfer_rebase_transfer(first_percentage_rebase: u256, second_percentage_rebase: u256) {
// fn test_transfer_rebase_transfer() {
        let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let (project_address, _) = default_setup();
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };
    let cc_handler = ICarbonCreditsHandlerDispatcher { contract_address: project_address };
    start_prank(CheatTarget::One(project_address), owner_address);
    assert(absorber.is_setup(), 'Error during setup');

    // Format fuzzing parameters, percentages with 6 digits after the comma, max 299.999999%
    let DECIMALS_FACTORS = 100_000;
    let first_percentage_rebase = first_percentage_rebase % 3*DECIMALS_FACTORS;
    let second_percentage_rebase = second_percentage_rebase % 3*DECIMALS_FACTORS;
    
    if first_percentage_rebase == 0 || second_percentage_rebase == 0 {
        return;
    }

    let undo_first_percentage_rebase = (DECIMALS_FACTORS * DECIMALS_FACTORS) / first_percentage_rebase;
    let undo_second_percentage_rebase = (DECIMALS_FACTORS * DECIMALS_FACTORS) / second_percentage_rebase;
    let share = 33 * CC_DECIMALS_MULTIPLIER;

    mint_utils(project_address, owner_address, share);
    let initial_balance = project_contract.balance_of(owner_address, 2025);

    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    project_contract
        .safe_transfer_from(
            owner_address, receiver_address, 2025, initial_balance.into(), array![].span()
        );
    let initial_vintage_supply = cc_handler.get_vintage_supply(2025);
    let new_vintage_supply_1 = initial_vintage_supply * first_percentage_rebase.try_into().unwrap() / 100_000;
    absorber.rebase_vintage(2025, new_vintage_supply_1);


    let balance_receiver = project_contract.balance_of(receiver_address, 2025);
    start_prank(CheatTarget::One(project_address), receiver_address);
    project_contract
        .safe_transfer_from(
            receiver_address, owner_address, 2025, balance_receiver.into(), array![].span()
        );

    let new_vintage_supply_2 = new_vintage_supply_1 * second_percentage_rebase.try_into().unwrap() / 100_000;
    absorber.rebase_vintage(2025, new_vintage_supply_2);

    // revert first rebase with the opposite percentage
    let new_vintage_supply_3 = new_vintage_supply_2 * undo_first_percentage_rebase.try_into().unwrap() / 100_000;
    absorber.rebase_vintage(2025, new_vintage_supply_3);

    // revert second rebase with the opposite percentage
    let new_vintage_supply_4 = new_vintage_supply_3 * undo_second_percentage_rebase.try_into().unwrap() / 100_000;
    absorber.rebase_vintage(2025, new_vintage_supply_4);

    let balance_owner = project_contract.balance_of(owner_address, 2025);
    let ok = equals_with_error(balance_owner, initial_balance, 100);
    assert(
        equals_with_error(balance_owner, initial_balance, 100), 'Error final balance owner'
    );
    let balance_receiver = project_contract.balance_of(receiver_address, 2025);
    assert(equals_with_error(balance_receiver, 0, 100), 'Error final balance receiver');

}


fn test_transfer(
    raw_supply: u64,
    raw_share: u256,
    raw_last_digits_share: u256,
    percentage_of_balance_to_send: u256,
    max_supply_for_vintage: u64
) {

    let supply = raw_supply % max_supply_for_vintage;
    if raw_share == 0 {
        return;
    }
    if supply == 0 {
        return;
    }
    let last_digits_share = raw_last_digits_share % 100;
    let share_modulo = raw_share % CC_DECIMALS_MULTIPLIER;
    let share = share_modulo * 100 + last_digits_share;

    if share == 0 {
        return;
    }

    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let receiver_address: ContractAddress = contract_address_const::<'receiver'>();
    let (project_address, _) = fuzzing_setup(supply);
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let project_contract = IProjectDispatcher { contract_address: project_address };
    start_prank(CheatTarget::One(project_address), owner_address);

    assert(absorber.is_setup(), 'Error during setup');

    mint_utils(project_address, owner_address, share);

    let initial_balance = project_contract.balance_of(owner_address, 2025);
    let amount = percentage_of_balance_to_send * initial_balance / 10_000;
    project_contract
        .safe_transfer_from(owner_address, receiver_address, 2025, amount.into(), array![].span());

    let balance_owner = project_contract.balance_of(owner_address, 2025);
    assert(
        equals_with_error(balance_owner, initial_balance - amount, 100), 'Error balance owner 1'
    );
    let balance_receiver = project_contract.balance_of(receiver_address, 2025);
    assert(equals_with_error(balance_receiver, amount, 100), 'Error balance receiver 1');

    start_prank(CheatTarget::One(project_address), receiver_address);
    project_contract
        .safe_transfer_from(receiver_address, owner_address, 2025, amount.into(), array![].span());

    let balance_owner = project_contract.balance_of(owner_address, 2025);
    assert(equals_with_error(balance_owner, initial_balance, 100), 'Error balance owner 2');
    let balance_receiver = project_contract.balance_of(receiver_address, 2025);
    assert(equals_with_error(balance_receiver, 0, 100), 'Error balance receiver 2');
}

#[test]
fn fuzz_test_transfer_low_supply_low_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 1 CC, so 10^6g of CC + 2 digits after the comma for precision => 10^8
    let max_supply_for_vintage: u64 = 100_000_000;
    let percentage_of_balance_to_send = 1;  // with 2 digits after the comma, so 0.01%
    test_transfer(raw_supply, raw_share, raw_last_digits_share, percentage_of_balance_to_send, max_supply_for_vintage);
}

#[test]
fn fuzz_test_transfer_low_supply_medium_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 1 CC, so 10^6g of CC + 2 digits after the comma for precision => 10^8
    let max_supply_for_vintage: u64 = 100_000_000;
    let percentage_of_balance_to_send = 300;  // with 2 digits after the comma, so 3%
    test_transfer(raw_supply, raw_share, raw_last_digits_share, percentage_of_balance_to_send, max_supply_for_vintage);
}

#[test]
fn fuzz_test_transfer_low_supply_high_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 1 CC, so 10^6g of CC + 2 digits after the comma for precision => 10^8
    let max_supply_for_vintage: u64 = 100_000_000;
    let percentage_of_balance_to_send = 10_000;  // with 2 digits after the comma, so 100%
    test_transfer(raw_supply, raw_share, raw_last_digits_share, percentage_of_balance_to_send, max_supply_for_vintage);
}

#[test]
fn fuzz_test_transfer_medium_supply_low_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10k CC, so 10^10g of CC + 2 digits after the comma for precision => 10^12
    let max_supply_for_vintage: u64 = 1_000_000_000_000;
    let percentage_of_balance_to_send = 1;  // with 2 digits after the comma, so 0.01%
    test_transfer(raw_supply, raw_share, raw_last_digits_share, percentage_of_balance_to_send, max_supply_for_vintage);
}

#[test]
fn fuzz_test_transfer_medium_supply_medium_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10k CC, so 10^10g of CC + 2 digits after the comma for precision => 10^12
    let max_supply_for_vintage: u64 = 1_000_000_000_000;
    let percentage_of_balance_to_send = 300;  // with 2 digits after the comma, so 3%
    test_transfer(raw_supply, raw_share, raw_last_digits_share, percentage_of_balance_to_send, max_supply_for_vintage);
}

#[test]
fn fuzz_test_transfer_medium_supply_high_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10k CC, so 10^10g of CC + 2 digits after the comma for precision => 10^12
    let max_supply_for_vintage: u64 = 1_000_000_000_000;
    let percentage_of_balance_to_send = 10_000;  // with 2 digits after the comma, so 100%
    test_transfer(raw_supply, raw_share, raw_last_digits_share, percentage_of_balance_to_send, max_supply_for_vintage);
}

#[test]
fn fuzz_test_transfer_high_supply_low_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10M CC, so 10^13g of CC + 2 digits after the comma for precision => 10^15
    let max_supply_for_vintage: u64 = 1_000_000_000_000_000;
    let percentage_of_balance_to_send = 1;  // with 2 digits after the comma, so 0.01%
    test_transfer(raw_supply, raw_share, raw_last_digits_share, percentage_of_balance_to_send, max_supply_for_vintage);
}

#[test]
fn fuzz_test_transfer_high_supply_medium_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10M CC, so 10^13g of CC + 2 digits after the comma for precision => 10^15
    let max_supply_for_vintage: u64 = 1_000_000_000_000_000;
    let percentage_of_balance_to_send = 300;  // with 2 digits after the comma, so 3%
    test_transfer(raw_supply, raw_share, raw_last_digits_share, percentage_of_balance_to_send, max_supply_for_vintage);
}

#[test]
fn fuzz_test_transfer_high_supply_high_amount(
    raw_supply: u64, raw_share: u256, raw_last_digits_share: u256
) {
    // max supply of a vintage is 10M CC, so 10^13g of CC + 2 digits after the comma for precision => 10^15
    let max_supply_for_vintage: u64 = 1_000_000_000_000_000;
    let percentage_of_balance_to_send = 10_000;  // with 2 digits after the comma, so 100%
    test_transfer(raw_supply, raw_share, raw_last_digits_share, percentage_of_balance_to_send, max_supply_for_vintage);
}
