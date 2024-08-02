use starknet::ContractAddress;

#[starknet::interface]
trait IMint<TContractState> {
    fn get_carbonable_project_address(self: @TContractState) -> ContractAddress;
    fn get_payment_token_address(self: @TContractState) -> ContractAddress;
    fn get_unit_price(self: @TContractState) -> u256;
    fn get_remaining_mintable_cc(self: @TContractState) -> u256;
    fn get_max_mintable_cc(self: @TContractState) -> u256;
    fn get_min_money_amount_per_tx(self: @TContractState) -> u256;
    fn is_public_sale_open(self: @TContractState) -> bool;
    fn is_sold_out(self: @TContractState) -> bool;
    fn is_canceled(self: @TContractState) -> bool;
    fn set_max_mintable_cc(ref self: TContractState, max_mintable_cc: u256);
    fn set_public_sale_open(ref self: TContractState, public_sale_open: bool);
    fn set_min_money_amount_per_tx(ref self: TContractState, min_money_amount_per_tx: u256);
    fn set_unit_price(ref self: TContractState, unit_price: u256);
    fn withdraw(ref self: TContractState);
    fn retrieve_amount(
        ref self: TContractState,
        token_address: ContractAddress,
        recipient: ContractAddress,
        amount: u256
    );
    fn public_buy(ref self: TContractState, cc_amount: u256);
    fn cancel_mint(ref self: TContractState, should_cancel: bool);
}
