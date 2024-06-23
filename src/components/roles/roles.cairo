// Role identifiers
const MINTER_ROLE: felt252 = selector!("Minter");
const OFFSETER_ROLE: felt252 = selector!("Offsetter");
const OWNER_ROLE: felt252 = selector!("Owner");

#[starknet::component]
mod RoleComponent {

    // Starknet imports
    use starknet::ContractAddress

    // External imports
    use openzeppelin::access::accesscontrol::AccessControlComponent;

    // Internal imports
    use super::{MINTER_ROLE, OFFSETER_ROLE, OWNER_ROLE};

    #[storage]
    struct Storage {
        access_control: AccessControlComponent::Storage
    }
 
    #[embeddable_as(RoleImpl)]
    impl Role<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
        > of IRole<ComponentState<TContractState>> {
            fn grant_minter_role(ref self: ComponentState<TContractState>, address: ContractAddress) {
                self.accesscontrol._grant_role(MINTER_ROLE, address);
            }

            fn grant_offsetter_role(ref self: ComponentState<TContractState>, address: ContractAddress) {
                self.accesscontrol._grant_role(OFFSETER_ROLE, address);
            }

            fn grant_owner_role(ref self: ComponentState<TContractState>, address: ContractAddress) {
                self.accesscontrol._grant_role(OWNER_ROLE, address);
            }
        }


}