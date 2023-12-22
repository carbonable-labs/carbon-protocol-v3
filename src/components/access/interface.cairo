use starknet::ContractAddress;

#[starknet::interface]
trait IMinter<TContractState> {
    fn get_minters(self: @TContractState) -> Span<ContractAddress>;
    fn add_minter(ref self: TContractState, user: ContractAddress);
    fn revoke_minter(ref self: TContractState, user: ContractAddress);
}

#[starknet::interface]
trait ICertifier<TContractState> {
    fn get_certifier(self: @TContractState) -> ContractAddress;
    fn set_certifier(ref self: TContractState, user: ContractAddress);
}

#[starknet::interface]
trait IWithdrawer<TContractState> {
    fn get_withdrawer(self: @TContractState) -> ContractAddress;
    fn set_withdrawer(ref self: TContractState, user: ContractAddress);
}
