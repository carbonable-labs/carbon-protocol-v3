// Starknet deps

use starknet::ContractAddress;

// External deps

use openzeppelin::tests::utils::constants as c;
use openzeppelin::utils::serde::SerializedAppend;
use snforge_std as snf;
use snforge_std::{CheatTarget, ContractClassTrait, EventSpy, SpyOn};
use alexandria_storage::list::{List, ListTrait};

// Components

use carbon_v3::components::absorber::interface::{
    IAbsorber, IAbsorberDispatcher, IAbsorberDispatcherTrait, ICarbonCreditsHandler,
    ICarbonCreditsHandlerDispatcher, ICarbonCreditsHandlerDispatcherTrait
};
use carbon_v3::components::minter::interface::{IMint, IMintDispatcher, IMintDispatcherTrait};

// Contracts

use carbon_v3::contracts::project::{
    Project, IExternalDispatcher as IProjectDispatcher,
    IExternalDispatcherTrait as IProjectDispatcherTrait
};

/// Deploys a project contract.
fn deploy_project(owner: felt252) -> (ContractAddress, EventSpy) {
    let contract = snf::declare('Project');
    let uri: ByteArray = "uri";
    let mut calldata: Array<felt252> = array![];
    calldata.append_serde(uri.into());
    calldata.append_serde(c::OWNER());
    let contract_address = contract.deploy(@calldata).unwrap();

    let mut spy = snf::spy_events(SpyOn::One(contract_address));

    (contract_address, spy)
}

/// Sets up the project contract.
fn setup_project(
    contract_address: ContractAddress,
    ton_equivalent: u64,
    project_carbon: u256,
    times: Span<u64>,
    absorptions: Span<u64>
) {
    let project = IAbsorberDispatcher { contract_address };

    project.set_absorptions(times, absorptions);
    project.set_project_carbon(project_carbon);
    snf::store(
        contract_address,
        selector!("Absorber_ton_equivalent"),
        array![ton_equivalent.into()].span(),
    ); // Only way to set ton equivalent for the moment (TO CHANGE)
}

#[test]
fn test_constructor_ok() {
    let (_project_address, _spy) = deploy_project(c::OWNER().into());
}

#[test]
fn test_is_setup() {
    let (project_address, _) = deploy_project(c::OWNER().into());
    let project = IAbsorberDispatcher { contract_address: project_address };

    setup_project(
        project_address,
        1000000,
        121099000000,
        array![21, 674579600, 1706115600, 1737738000].span(),
        array![21, 29609535, 47991466, 88828605].span(),
    );

    assert(project.is_setup(), 'Error during setup');
}
