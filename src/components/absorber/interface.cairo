use starknet::ContractAddress;

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
    fn get_project_value(self: @TContractState) -> u256;

    /// Returns the ton equivalent.
    fn get_ton_equivalent(self: @TContractState) -> u64;

    /// Returns true is the given project has been setup.
    fn is_setup(self: @TContractState) -> bool;

    /// Setup the absorption curve parameters.
    fn set_absorptions(ref self: TContractState, times: Span<u64>, absorptions: Span<u64>);

    /// Setup the project value for the given slot.
    fn set_project_value(ref self: TContractState, project_value: u256);
}

#[starknet::interface]
trait ICarbonCredits<TContractState> {
    /// Returns the carbon credits vintage list.
    fn get_cc_vintages(self: @TContractState) -> Span<u256>;

    /// Compute number of Carbon Credit of each vintage for given value
    fn compute_cc_distribution(self: @TContractState, share: u256) -> Span<u256>;

    // Get number of decimal for total supply to have a carbon credit
    fn get_cc_decimals(self: @TContractState) -> u8;
}
