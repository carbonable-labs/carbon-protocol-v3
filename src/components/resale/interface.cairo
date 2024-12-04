use starknet::ContractAddress;

#[starknet::interface]
pub trait IResaleHandler<TContractState> {
    /// Deposit carbon credits from one vintage for resale.
    fn deposit_vintage(ref self: TContractState, token_id: u256, cc_amount: u256);

    /// Deposit carbon credits from a list of vintage for resale.
    /// The method will fail if any cc_amount is less than the user's balance for that vintage.
    fn deposit_vintages(ref self: TContractState, token_ids: Span<u256>, cc_amounts: Span<u256>);

    // Claim a reward assigned to caller
    fn claim(
        ref self: TContractState,
        amount: u128,
        timestamp: u128,
        vintage: u256,
        id: u128,
        proof: Array::<felt252>
    );

    /// Get the pending amount of resale of a vintage for the caller address.
    fn get_pending_resale(self: @TContractState, address: ContractAddress, token_id: u256) -> u256;

    /// Get the total amount of resale token of a vintage for the caller address.
    fn get_carbon_sold(self: @TContractState, address: ContractAddress, token_id: u256) -> u256;

    /// Set the merkle root of the resale tree
    fn set_merkle_root(ref self: TContractState, root: felt252);

    /// Get the merkle root
    fn get_merkle_root(self: @TContractState) -> felt252;

    /// Check if a reward has been claimed
    fn check_claimed(
        self: @TContractState,
        claimee: ContractAddress,
        timestamp: u128,
        amount: u128,
        vintage: u256,
        id: u128
    ) -> bool;

    /// Resale strategy for carbon credits
    fn sell_carbon_credits(
        ref self: TContractState,
        token_id: u256,
        cc_amount: u256,
        resale_price: u256,
        merkle_root: felt252,
    );

    /// Set the resale token address
    fn set_resale_token(ref self: TContractState, token_address: ContractAddress);
    /// Get the resale token address
    fn get_resale_token(self: @TContractState) -> ContractAddress;
    /// Set the resale account address
    fn set_resale_account(ref self: TContractState, account_address: ContractAddress);
    /// Get the resale account address
    fn get_resale_account(self: @TContractState) -> ContractAddress;
}
