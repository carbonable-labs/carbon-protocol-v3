use starknet::{ContractAddress, contract_address_const, get_caller_address};
use snforge_std::{CheatTarget, ContractClassTrait, EventSpy, SpyOn, start_prank, stop_prank,};
use super::tests_lib::{deploy_erc721};
use carbon_v3::contracts::project::{IERC721Dispatcher, IERC721DispatcherTrait};

#[test]
fn test_erc721_mint() {
    /// Test that only project contract can call mint function

    let project_contract_address: ContractAddress = contract_address_const::<'PROJECT'>();
    let receiver_address: ContractAddress = contract_address_const::<'RECEIVER'>();
    let (erc721_address,) = deploy_erc721(project_contract_address);
    let erc721_contract = IERC721Dispatcher { contract_address: erc721_address };

    // Call mint function with `project_contract_address` as caller
    start_prank(CheatTarget::One(erc721_address), project_contract_address);
    erc721_contract.mint(receiver_address, 1);
    let nft_owner: ContractAddress = erc721_contract.owner_of(1);
    assert_eq!(nft_owner, receiver_address);
}

#[test]
#[should_panic(expected: 'ERC721: caller not owner')]
fn test_erc721_mint_panic() {
    // Test that ERC721 contract panics when mint function is called by an unauthorized address
    let project_contract_address: ContractAddress = contract_address_const::<'PROJECT'>();
    let receiver_address: ContractAddress = contract_address_const::<'RECEIVER'>();
    let random_address: ContractAddress = contract_address_const::<'RANDOM'>();
    let (erc721_address,) = deploy_erc721(project_contract_address);
    let erc721_contract = IERC721Dispatcher { contract_address: erc721_address };

    // Call mint function with a random address
    start_prank(CheatTarget::One(erc721_address), random_address);
    erc721_contract.mint(receiver_address, 1);
}
