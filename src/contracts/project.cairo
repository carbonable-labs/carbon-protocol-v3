use starknet::ContractAddress;

#[starknet::interface]
trait IExternal<ContractState> {
    fn mint_specific_cc(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256);
    fn burn_specific_cc(ref self: ContractState, token_id: u256, value: u256);
}


#[starknet::contract]
mod Project {
    use openzeppelin::token::erc1155::erc1155::ERC1155Component::InternalTrait;
use core::traits::Into;
    use starknet::{get_caller_address, ContractAddress, ClassHash};

    // Ownable
    use openzeppelin::access::ownable::OwnableComponent;
    // Upgradable
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    //SRC5
    use openzeppelin::introspection::src5::SRC5Component;
    // ERC1155
    use openzeppelin::token::erc1155::ERC1155Component;
    // Absorber
    use carbon_v3::components::absorber::module::AbsorberComponent;


    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: AbsorberComponent, storage: absorber, event: AbsorberEvent);

    // ERC1155
    #[abi(embed_v0)]
    impl ERC1155Impl = ERC1155Component::ERC1155Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC1155MetadataImpl = ERC1155Component::ERC1155MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC1155CamelOnly = ERC1155Component::ERC1155CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl = OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl AbsorberImpl = AbsorberComponent::AbsorberImpl<ContractState>;

    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // Constants
    const IERC165_BACKWARD_COMPATIBLE_ID: u32 = 0x80ac58cd_u32;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc1155: ERC1155Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        absorber: AbsorberComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC1155Event: ERC1155Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        AbsorberEvent: AbsorberComponent::Event
    }

    mod Errors {
        const UNEQUAL_ARRAYS_VALUES: felt252 = 'Values array len do not match';
        const UNEQUAL_ARRAYS_URI: felt252 = 'URI Array len do not match';
    }

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252, 
        owner: ContractAddress
    ) {
        self.erc1155.initializer(name, symbol);
        self.ownable.initializer(owner);
    }

    // Externals
    #[external(v0)]
    impl ExternalImpl of super::IExternal<ContractState> {

        fn mint_specific_cc(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256) {
            self.erc1155._mint(to, token_id, value);
        }

        fn burn_specific_cc(ref self: ContractState, token_id: u256, value: u256) {
            self.erc1155._burn(token_id, value);
        }
    }
}
