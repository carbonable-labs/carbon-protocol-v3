use core::clone::Clone;
use core::result::ResultTrait;
use starknet::{ContractAddress, contract_address_const};
use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, test_address, spy_events, EventSpy, start_cheat_caller_address,
    stop_cheat_caller_address, EventSpyAssertionsTrait
};

// Contracts
use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
use carbon_v3::components::offsetter::interface::{
    IOffsetHandlerDispatcher, IOffsetHandlerDispatcherTrait
};
use carbon_v3::components::offsetter::OffsetComponent;

// use merkle_tree_cairo::claimer::{OffsetComponent, IOffsetHandlerDispatcher, IOffsetHandlerDispatcherTrait};

/// Utils for testing purposes
use super::tests_lib::{
    equals_with_error, deploy_project, setup_project, default_setup_and_deploy,
    perform_fuzzed_transfer, buy_utils, deploy_erc20, deploy_minter, helper_sum_balance,
    helper_check_vintage_balances, helper_get_token_ids, helper_expected_transfer_event,
    deploy_offsetter,
};

/// Utils to import mock data
use super::tests_lib::{
    MERKLE_ROOT_FIRST_WAVE, MERKLE_ROOT_SECOND_WAVE, get_bob_first_wave_allocation,
    get_bob_combined_wave_allocation, get_alice_combined_wave_allocation,
    get_john_multiple_allocations
};

#[test]
fn test_set_merkle_root() {
    /// Test that the Merkle root can be set and retrieved correctly.
    let owner_address = contract_address_const::<'OWNER'>();
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(MERKLE_ROOT_FIRST_WAVE);

    start_cheat_caller_address(offsetter_address, user_address);
    let root = contract.get_merkle_root();
    assert_eq!(root, MERKLE_ROOT_FIRST_WAVE);
}

#[test]
#[should_panic(expected: 'Caller does not have role')]
fn test_set_merkle_root_without_owner_role() {
    /// Test that only the owner can set the Merkle root.
    let user_address: ContractAddress = contract_address_const::<'USER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, user_address);
    contract.set_merkle_root(MERKLE_ROOT_FIRST_WAVE);
}

#[test]
fn test_bob_claims_single_allocation() {
    /// Test a simple claim scenario where Bob claims his allocation from the first wave.
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    let (root, bob_address, amount, timestamp, proof) = get_bob_first_wave_allocation();
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);

    start_cheat_caller_address(offsetter_address, bob_address);
    assert_eq!(contract.get_merkle_root(), root);

    assert!(!contract.check_claimed(bob_address, timestamp, amount));

    start_cheat_caller_address(offsetter_address, bob_address);
    contract.claim(amount, timestamp, proof);

    assert!(contract.check_claimed(bob_address, timestamp, amount));
}

#[test]
fn test_bob_claims_multiple_allocations() {
    /// Test that a user with two allocations can claim both correctly.
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);

    let ROOT = 0x7be624496a1672132d43607a5aa283940fe5ea7bbdee39b34606ea895a91e05;
    let address = contract_address_const::<0x123>();
    let amount1 = 0x64;
    let timestamp1 = 0x1;
    let proof1 = array![
        0x7eca5c09f03332447da957fea8123007825b06a57286c4fcfc35f130d450588,
        0x5e5ec048d441d324737e44bde3bb146ad3f782fba4ebabd52017f67f381969b
    ];

    let amount2 = 0x6e;
    let timestamp2 = 0x13;
    let proof2 = array![
        0x6a716202ba08ca9b9f199b0d54d80508fd7a30687f821ec13478a166f1eaec0,
        0xd31a5d1a36d3a6c35438017cacb878814c47b7fb49245ce812323e96790a87
    ];

    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(ROOT);
    assert!(!contract.check_claimed(address, timestamp1, amount1));

    start_cheat_caller_address(offsetter_address, address);
    contract.claim(amount1, timestamp1, proof1);
    assert!(contract.check_claimed(address, timestamp1, amount1));

    assert!(!contract.check_claimed(address, timestamp2, amount2));
    contract.claim(amount2, timestamp2, proof2);
    assert!(contract.check_claimed(address, timestamp2, amount2));
}

#[test]
#[should_panic(expected: 'Already claimed')]
fn test_bob_claims_twice() {
    /// Test that trying to claim the same allocation twice results in a panic.
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, bob_address, amount, timestamp, proof) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount));

    start_cheat_caller_address(offsetter_address, bob_address);
    contract.claim(amount, timestamp, proof.clone());
    assert!(contract.check_claimed(bob_address, timestamp, amount));

    contract.claim(amount, timestamp, proof);
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_address() {
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, _, amount, timestamp, proof) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    let invalid_address = contract_address_const::<'DUMMY'>();
    assert!(!contract.check_claimed(invalid_address, timestamp, amount));

    start_cheat_caller_address(offsetter_address, invalid_address);
    contract.claim(amount, timestamp, proof);
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_amount() {
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, bob_address, _, timestamp, proof) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    let invalid_amount = 0;
    assert!(!contract.check_claimed(bob_address, timestamp, invalid_amount));

    start_cheat_caller_address(offsetter_address, bob_address);
    contract.claim(invalid_amount, timestamp, proof);
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_timestamp() {
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, bob_address, amount, _, proof) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    let invalid_timestamp = 0;
    assert!(!contract.check_claimed(bob_address, invalid_timestamp, amount));

    start_cheat_caller_address(offsetter_address, bob_address);
    contract.claim(amount, invalid_timestamp, proof);
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_proof() {
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, bob_address, amount, timestamp, _) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    let invalid_proof: Array<felt252> = array![0x123, 0x1];
    assert!(!contract.check_claimed(bob_address, timestamp, amount));

    start_cheat_caller_address(offsetter_address, bob_address);
    contract.claim(amount, timestamp, invalid_proof);
}

#[test]
fn test_event_emission_on_claim() {
    let (root, bob_address, amount, timestamp, proof) = get_bob_first_wave_allocation();
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount));

    let mut spy = spy_events();
    start_cheat_caller_address(offsetter_address, bob_address);
    contract.claim(amount, timestamp, proof);

    let expected_event = OffsetComponent::Event::AllocationClaimed(
        OffsetComponent::AllocationClaimed { claimee: bob_address, amount, timestamp }
    );
    spy.assert_emitted(@array![(offsetter_address, expected_event)]);

    assert!(contract.check_claimed(bob_address, timestamp, amount));
}

#[test]
fn test_claim_after_root_update() {
    /// Test that an unclaimed allocation from the first wave can still be claimed after setting a new Merkle root.
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, bob_address, amount, timestamp, _) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount));

    let (new_root, _, _, _, new_proof) = get_bob_combined_wave_allocation();
    contract.set_merkle_root(new_root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount));

    start_cheat_caller_address(offsetter_address, bob_address);
    contract.claim(amount, timestamp, new_proof);
    assert!(contract.check_claimed(bob_address, timestamp, amount));
}

#[test]
fn test_alice_claims_in_second_wave() {
    /// Test that Bob can claim his allocation from the first wave and Alice can claim her allocation from the second wave.
    let (root, bob_address, amount, timestamp, proof) = get_bob_first_wave_allocation();
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount));

    let mut spy = spy_events();
    start_cheat_caller_address(offsetter_address, bob_address);
    contract.claim(amount, timestamp, proof);

    let expected_event = OffsetComponent::Event::AllocationClaimed(
        OffsetComponent::AllocationClaimed { claimee: bob_address, amount, timestamp }
    );
    spy.assert_emitted(@array![(offsetter_address, expected_event)]);
    assert!(contract.check_claimed(bob_address, timestamp, amount));

    let (new_root, alice_address, amount, timestamp, proof) = get_alice_combined_wave_allocation();
    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(new_root);
    assert!(!contract.check_claimed(alice_address, timestamp, amount));

    start_cheat_caller_address(offsetter_address, alice_address);
    contract.claim(amount, timestamp, proof);
    assert!(contract.check_claimed(alice_address, timestamp, amount));
}

#[test]
fn test_john_claims_multiple_allocations() {
    /// Test that John can claim two of his three allocations from the first wave, and the remaining one from the second wave.
    let (
        root,
        new_root,
        john_address,
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
        _,
        proof4
    ) =
        get_john_multiple_allocations();

    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(john_address, timestamp1, amount1));
    assert!(!contract.check_claimed(john_address, timestamp2, amount2));
    assert!(!contract.check_claimed(john_address, timestamp3, amount3));

    start_cheat_caller_address(offsetter_address, john_address);
    contract.claim(amount1, timestamp1, proof1);
    contract.claim(amount2, timestamp2, proof2);
    assert!(contract.check_claimed(john_address, timestamp1, amount1));
    assert!(contract.check_claimed(john_address, timestamp2, amount2));
    assert!(!contract.check_claimed(john_address, timestamp3, amount3));

    contract.set_merkle_root(new_root);
    contract.claim(amount4, timestamp4, proof4);
    assert!(contract.check_claimed(john_address, timestamp4, amount4));
    assert!(!contract.check_claimed(john_address, timestamp3, amount3));
}
