use starknet::ContractAddress;
use carbon_v3::data::carbon_vintage::{CarbonVintage};

#[starknet::interface]
trait IAbsorber<TContractState> {
    /// Returns the first timestamp of the absorption.
    fn get_start_time(self: @TContractState) -> u64;

    /// Returns the last timestamp of the absorption.
    fn get_final_time(self: @TContractState) -> u64;

    /// Returns the times of the absorption.
    fn get_times(self: @TContractState) -> Span<u64>;

    /// Returns the absorptions.
    fn get_absorptions(self: @TContractState) -> Span<u64>;

    /// Returns the absorption for the given timestamp.
    fn get_absorption(self: @TContractState, time: u64) -> u64;

    /// Returns the absorption at the current timestamp
    fn get_current_absorption(self: @TContractState) -> u64;

    /// Returns the total absorption.
    fn get_final_absorption(self: @TContractState) -> u64;

    /// Returns the project value.
    fn get_project_carbon(self: @TContractState) -> u256;

    /// Returns the ton equivalent.
    fn get_ton_equivalent(self: @TContractState) -> u64;

    ///  Convert a share of supply balance to a carbon credit balance.
    fn share_to_cc(self: @TContractState, share: u256, token_id: u256) -> u256;

    // Convert a carbon credit balance to a share of supply balance.
    fn cc_to_share(self: @TContractState, cc_value: u256, token_id: u256) -> u256;

    /// Returns true is the given project has been setup.
    fn is_setup(self: @TContractState) -> bool;

    /// Setup the absorption curve parameters.
    fn set_absorptions(ref self: TContractState, times: Span<u64>, absorptions: Span<u64>);

    /// Setup the project carbon for the given slot.
    fn set_project_carbon(ref self: TContractState, project_carbon: u256);

    /// Compute number of Carbon Credit of each vintage for given value
    fn compute_carbon_vintage_distribution(self: @TContractState, share: u256) -> Span<u256>;
}

#[starknet::interface]
trait ICarbonCreditsHandler<TContractState> {
    /// Returns the carbon credits vintage list.
    fn get_cc_vintages(self: @TContractState) -> Span<CarbonVintage>;

    fn get_years_vintage(self: @TContractState) -> Span<u256>;

    fn get_specific_carbon_vintage(self: @TContractState, year: u256) -> CarbonVintage;

    fn get_vintage_supply(self: @TContractState, year: u256) -> u64;

    // Get number of decimal for total supply to have a carbon credit
    fn get_cc_decimals(self: @TContractState) -> u8;

    // Update the vintage status
    fn update_vintage_status(ref self: TContractState, year: u64, status: felt252);
}
