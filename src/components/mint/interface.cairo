use starknet::ContractAddress;

#[starknet::interface]
trait IMint<TContractState> {
    fn get_carbonable_project_address(self: @TContractState) -> ContractAddress;
    fn get_payment_token_address(self: @TContractState) -> ContractAddress;
    fn is_public_sale_open(self: @TContractState) -> bool;
    fn get_unit_price(self: @TContractState) -> u256;
    fn get_available_value(self: @TContractState) -> u256;
    fn get_claimed_value(self: @TContractState, account: ContractAddress) -> u256;
    fn is_sold_out(self: @TContractState) -> bool;
    fn is_canceled(self: @TContractState) -> bool;
    fn set_public_sale_open(ref self: TContractState, public_sale_open: bool);
    fn set_unit_price(ref self: TContractState, unit_price: u256);
    fn withdraw(ref self: TContractState);
    fn transfer(
        ref self: TContractState,
        token_address: ContractAddress,
        recipient: ContractAddress,
        amount: u256
    );
    fn book(ref self: TContractState, value: u256, force: bool);
    fn claim(ref self: TContractState, user_address: ContractAddress, id: u32);
    fn refund(ref self: TContractState, user_address: ContractAddress, id: u32);
    fn refund_to(
        ref self: TContractState, to: ContractAddress, user_address: ContractAddress, id: u32
    );
    fn cancel(ref self: TContractState);
}
