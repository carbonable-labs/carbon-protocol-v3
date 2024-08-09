use carbon_v3::models::carbon_vintage::CarbonVintage;

#[starknet::interface]
trait IVintage<TContractState> {
    /// Returns the project total carbon credits.
    fn get_project_carbon(self: @TContractState) -> u128;

    /// Returns the number of vintages of the project.
    fn get_num_vintages(self: @TContractState) -> usize;

    /// Returns all available vintage details.
    fn get_cc_vintages(self: @TContractState) -> Span<CarbonVintage>;

    /// Returns the vintage details with the given token_id.
    fn get_carbon_vintage(self: @TContractState, token_id: u256) -> CarbonVintage;

    /// Get the initial supply of carbon credits for a vintage, before any rebases
    fn get_initial_cc_supply(self: @TContractState, token_id: u256) -> u256;

    /// Get the initial supply of carbon credits for a project, before any rebases
    fn get_initial_project_cc_supply(self: @TContractState) -> u256;

    /// Get number of decimal for total supply to have a carbon credit
    fn get_cc_decimals(self: @TContractState) -> u8;

    /// Update the vintage status
    fn update_vintage_status(ref self: TContractState, token_id: u256, status: u8);

    /// Adapt the cc_supply of a vintage, will impact holders balance.
    fn rebase_vintage(ref self: TContractState, token_id: u256, new_cc_supply: u256);

    /// Set all carbon vintages based on absorption curve
    fn set_vintages(ref self: TContractState, yearly_absorptions: Span<u256>, start_year: u32);
}
