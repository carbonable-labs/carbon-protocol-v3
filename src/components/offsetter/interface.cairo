use starknet::ContractAddress;
use carbon_v3::models::carbon_vintage::CarbonVintage;

#[starknet::interface]
trait IOffsetHandler<TContractState> {
    /// Deposit carbon credits from one vintage for offset.
    fn deposit_vintage(ref self: TContractState, token_id: u256, cc_amount: u256);

    /// Deposit carbon credits from a list of vintage for resale.
    fn deposit_vintages(
        ref self: TContractState, token_ids: Span<u256>, cc_amounts: Span<u256>
    );

    ///Verify and validate the proof on the Merkle tree side to confirm the offset.
    fn confirm_for_merkle_tree(
        self: @TContractState,
        from: ContractAddress,
        amount: u128,
        timestamp: u128,
        id: u128,
        proof: Array::<felt252>
    ) -> bool;

    ///Verify on the business logic side, confirm on the Merkle tree side, and perform the offset
    ///action.
    fn confirm_offset(
        ref self: TContractState, amount: u128, timestamp: u128, id: u128, proof: Array::<felt252>
    );

    fn get_allocation_id(self: @TContractState, from: ContractAddress) -> u256;


    fn get_retirement(self: @TContractState, token_id: u256, from: ContractAddress) -> u256;

    /// Get the pending retirement of a vintage for the caller address.
    fn get_pending_retirement(
        self: @TContractState, address: ContractAddress, token_id: u256
    ) -> u256;

    /// Get the carbon retirement of a vintage for the caller address.
    fn get_carbon_retired(self: @TContractState, address: ContractAddress, token_id: u256) -> u256;
    fn set_merkle_root(ref self: TContractState, root: felt252);

    fn get_merkle_root(self: @TContractState) -> felt252;

    fn check_claimed(
        self: @TContractState, claimee: ContractAddress, timestamp: u128, amount: u128, id: u128
    ) -> bool;
}
