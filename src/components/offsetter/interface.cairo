use starknet::ContractAddress;
use carbon_v3::models::carbon_vintage::CarbonVintage;

#[starknet::interface]
trait IOffsetHandler<TContractState> {
    /// Retire carbon credits from one vintage of carbon credits.
    fn retire_carbon_credits(ref self: TContractState, token_id: u256, cc_value: u256);

    /// Retire carbon credits from the list of carbon credits.
    /// Behaviour is : 
    /// - If one of the carbon values is not enough or vintage status is not right, 
    /// the function will fail and no carbon will be retired and the function will revert.
    fn retire_list_carbon_credits(
        ref self: TContractState, vintages: Span<u256>, carbon_values: Span<u256>
    );

    fn claim(ref self: TContractState, amount: u128, timestamp: u128, proof: Array::<felt252>);

    /// Get the pending retirement of a vintage for the caller address.
    fn get_pending_retirement(ref self: TContractState, token_id: u256) -> u256;

    /// Get the carbon retirement of a vintage for the caller address.
    fn get_carbon_retired(
        ref self: TContractState, address: ContractAddress, token_id: u256
    ) -> u256;
fn set_merkle_root(ref self: TContractState, root: felt252);

fn get_merkle_root(ref self: TContractState) -> felt252;

fn check_claimed(
    ref self: TContractState, claimee: ContractAddress, timestamp: u128, amount: u128
) -> bool;
}
