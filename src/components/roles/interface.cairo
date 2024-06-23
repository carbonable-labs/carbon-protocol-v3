use starknet::ContractAddress

#[starknet::interface]
trait IRole<TContractState>{
    fn grant_minter_role(ref self: TContractState, address: ContractAddress);
    fn grant_offsetter_role(ref self: TContractState, address: ContractAddress);
    fn grant_owner_role(ref self: TContractState, address: ContractAddress);
}