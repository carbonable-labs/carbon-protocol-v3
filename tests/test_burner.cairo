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
use carbon_v3::components::burner::interface::{IBurnHandlerDispatcher, IBurnHandlerDispatcherTrait};

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};
use carbon_v3::contracts::minter::Minter;
use carbon_v3::mock::usdcarb::USDCarb;

// Utils for testing purposes

use carbon_v3::tests_lib::{default_setup_and_deploy, mint_utils, deploy_burner};

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
fn test_burner_init() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (burner_address, _) = deploy_burner(owner_address, project_address);

    let burner = IBurnHandlerDispatcher { contract_address: burner_address };

    // [Assert] cointract is empty
    start_prank(CheatTarget::One(burner_address), owner_address);
    let carbon_pending = burner.get_carbon_retired(2025);
    assert(carbon_pending == 0, 'carbon pending should be 0');

    let carbon_retired = burner.get_carbon_retired(2025);
    assert(carbon_retired == 0, 'carbon retired should be 0');
}

// Nominal cases

#[test]
fn test_burner_retirement() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (burner_address, _) = deploy_burner(owner_address, project_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(burner_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    assert(absorber.is_setup(), 'Error during setup');
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let decimal: u8 = project_contract.decimals();
    assert(decimal == 6, 'Error of decimal');

    let share: u256 = 10 * CC_DECIMALS_MULTIPLIER; // 10%
    mint_utils(project_address, owner_address, share);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());

    // [Effect] try to retire carbon credits
    let burner = IBurnHandlerDispatcher { contract_address: burner_address };
    burner.retire_carbon_credits(2025, 100000);

    let carbon_retired = burner.get_carbon_retired(2025);
    assert(carbon_retired == 100000, 'Carbon retired is wrong');
}

// Error cases

#[test]
#[should_panic(expected: ('Not own enough carbon credits',))]
fn test_burner_not_enough_CC() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (burner_address, _) = deploy_burner(owner_address, project_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(burner_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let absorber = IAbsorberDispatcher { contract_address: project_address };
    let carbon_credits = ICarbonCreditsHandlerDispatcher { contract_address: project_address };

    assert(absorber.is_setup(), 'Error during setup');
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let decimal: u8 = project_contract.decimals();
    assert(decimal == 6, 'Error of decimal');

    let share = 33 * CC_DECIMALS_MULTIPLIER;
    mint_utils(project_address, owner_address, share);

    // [Effect] update Vintage status
    carbon_credits.update_vintage_status(2025, CarbonVintageType::Audited.into());

    // [Effect] try to retire carbon credits
    let burner = IBurnHandlerDispatcher { contract_address: burner_address };
    let balance_owner = project_contract.balance_of(owner_address, 2025);
    burner.retire_carbon_credits(2025, balance_owner + 1);
}

#[test]
#[should_panic(expected: ('Vintage status is not audited',))]
fn test_burner_wrong_status() {
    let owner_address: ContractAddress = contract_address_const::<'OWNER'>();
    let (project_address, _) = default_setup_and_deploy();
    let (burner_address, _) = deploy_burner(owner_address, project_address);

    // [Prank] use owner address as caller
    start_prank(CheatTarget::One(project_address), owner_address);
    start_prank(CheatTarget::One(burner_address), owner_address);

    // [Effect] setup a batch of carbon credits
    let absorber = IAbsorberDispatcher { contract_address: project_address };

    assert(absorber.is_setup(), 'Error during setup');
    let project_contract = IProjectDispatcher { contract_address: project_address };

    let decimal: u8 = project_contract.decimals();
    assert(decimal == 6, 'Error of decimal');

    let share = 33 * CC_DECIMALS_MULTIPLIER;
    mint_utils(project_address, owner_address, share);

    // [Effect] try to retire carbon credits
    let burner = IBurnHandlerDispatcher { contract_address: burner_address };
    burner.retire_carbon_credits(2025, 1000000);
}
