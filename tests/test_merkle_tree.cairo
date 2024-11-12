use starknet::{ContractAddress, contract_address_const};
use snforge_std as snf;
use snforge_std::{
    ContractClassTrait, spy_events, EventSpy, start_cheat_caller_address, stop_cheat_caller_address,
    EventSpyAssertionsTrait
};

// Contracts
use carbon_v3::components::offsetter::interface::{
    IOffsetHandlerDispatcher, IOffsetHandlerDispatcherTrait
};
use carbon_v3::components::offsetter::OffsetComponent;

/// Utils for testing purposes
use super::tests_lib::{default_setup_and_deploy, deploy_offsetter};

/// Utils to import mock data
use super::tests_lib::{
    MERKLE_ROOT_FIRST_WAVE, MERKLE_ROOT_SECOND_WAVE, get_bob_first_wave_allocation,
    get_bob_second_wave_allocation, get_alice_second_wave_allocation, get_john_multiple_allocations
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

    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);

    start_cheat_caller_address(offsetter_address, bob_address);
    assert_eq!(contract.get_merkle_root(), root);

    assert!(contract.confirm_for_merkle_tree(bob_address, amount, timestamp, id, proof));
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_address() {
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, _, amount, timestamp, id, proof) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    let invalid_address = contract_address_const::<'DUMMY'>();
    assert!(!contract.check_claimed(invalid_address, timestamp, amount, id));

    assert!(!contract.confirm_for_merkle_tree(invalid_address, amount, timestamp, id, proof));
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_amount() {
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, bob_address, _, timestamp, id, proof) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    let invalid_amount = 0;
    assert!(!contract.check_claimed(bob_address, timestamp, invalid_amount, id));

    assert!(!contract.confirm_for_merkle_tree(bob_address, invalid_amount, timestamp, id, proof));
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_timestamp() {
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, bob_address, amount, _, id, proof) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    let invalid_timestamp = 0;
    assert!(!contract.check_claimed(bob_address, invalid_timestamp, amount, id));

    assert!(!contract.confirm_for_merkle_tree(bob_address, amount, invalid_timestamp, id, proof));
}

#[test]
#[should_panic(expected: 'Invalid proof')]
fn test_claim_with_invalid_proof() {
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, bob_address, amount, timestamp, id, _) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    let invalid_proof: Array<felt252> = array![0x123, 0x1];
    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    assert!(!contract.confirm_for_merkle_tree(bob_address, amount, timestamp, id, invalid_proof));
}

#[test]
fn test_claim_after_root_update() {
    /// Test that an unclaimed allocation from the first wave can still be claimed after setting a new Merkle root.
    let owner_address = contract_address_const::<'OWNER'>();
    let (root, bob_address, amount, timestamp, id, _) = get_bob_first_wave_allocation();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    let (new_root, _, _, _, _, new_proof) = get_bob_second_wave_allocation();
    contract.set_merkle_root(new_root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    assert!(contract.confirm_for_merkle_tree(bob_address, amount, timestamp, id, new_proof));
}

#[test]
fn test_alice_claims_in_second_wave() {
    /// Test that Bob can confirm his allocation from the first wave and Alice can confirm her allocation from the second wave.
    let (root, bob_address, amount, timestamp, id, proof) = get_bob_first_wave_allocation();
    let owner_address = contract_address_const::<'OWNER'>();
    let project_address = default_setup_and_deploy();
    let offsetter_address = deploy_offsetter(project_address);
    let contract = IOffsetHandlerDispatcher { contract_address: offsetter_address };

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(root);
    assert!(!contract.check_claimed(bob_address, timestamp, amount, id));

    assert!(contract.confirm_for_merkle_tree(bob_address, amount, timestamp, id, proof));

    let (new_root, alice_address, amount, timestamp, id, proof) =
        get_alice_second_wave_allocation();
    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(new_root);
    assert!(!contract.check_claimed(alice_address, timestamp, amount, id));

    assert!(contract.confirm_for_merkle_tree(alice_address, amount, timestamp, id, proof));
}

#[test]
fn test_john_claims_multiple_allocations() {
    /// Test that John can confirm_for_merkle_tree two of his three allocations from the first wave, and the remaining one from the second wave.
    let (
        root,
        new_root,
        john_address,
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
    assert!(!contract.check_claimed(john_address, timestamp1, amount1, id_1));
    assert!(!contract.check_claimed(john_address, timestamp2, amount2, id_2));
    assert!(!contract.check_claimed(john_address, timestamp3, amount3, id_3));

    assert!(contract.confirm_for_merkle_tree(john_address, amount1, timestamp1, id_1, proof1));
    assert!(contract.confirm_for_merkle_tree(john_address, amount2, timestamp2, id_2, proof2));

    start_cheat_caller_address(offsetter_address, owner_address);
    contract.set_merkle_root(new_root);

    assert!(contract.confirm_for_merkle_tree(john_address, amount4, timestamp4, id_4, proof4));
}
