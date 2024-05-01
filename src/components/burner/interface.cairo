use starknet::ContractAddress;
use carbon_v3::data::carbon_vintage::{CarbonVintage};

#[starknet::interface]
trait IBurnHandler<TContractState> {
    /// Retire carbon credits from one vintage of carbon credits.
    fn retire_carbon_credits(ref self: TContractState, vintage: u256, carbon_values: u256);
    
    /// Retire carbon credits from the list of carbon credits.
    /// Behaviour is : 
    /// - If one of the carbon values is not enough or vintage status is not righ, 
    /// the function will fail and no carbon will be retired and the function will revert.
    fn retire_list_carbon_credits(ref self: TContractState, vintages: Span<u256>, carbon_values: Span<u256>);

    /// Get the pending retirement of a vintage for the caller address.
    fn get_pending_retirement(ref self: TContractState, vintage: u256) -> u256;

    /// Get the carbon retirement of a vintage for the caller address.
    fn get_carbon_retired(ref self: TContractState, vintage: u256) -> u256;
}