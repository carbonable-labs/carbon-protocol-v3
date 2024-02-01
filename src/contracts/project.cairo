use starknet::ContractAddress;

#[starknet::interface]
trait IExternal<ContractState> {
    fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256);
    fn burn(ref self: ContractState, token_id: u256, value: u256);
    fn batch_mint(
        ref self: ContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
    );
    fn batch_burn(ref self: ContractState, token_ids: Span<u256>, values: Span<u256>);
    fn set_uri(ref self: ContractState, token_id: u256, uri: felt252);
    fn set_list_uri(ref self: ContractState, token_ids: Span<u256>, uris: Span<felt252>);
    fn decimals(self: @ContractState) -> u8;
}


#[starknet::contract]
mod Project {
    use carbon_v3::components::absorber::interface::ICarbonCredits;
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
    use carbon_v3::components::absorber::carbon::AbsorberComponent;

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
    impl OwnableCamelOnlyImpl =
        OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl AbsorberImpl = AbsorberComponent::AbsorberImpl<ContractState>;
    #[abi(embed_v0)]
    impl CarbonCreditsImpl = AbsorberComponent::CarbonCreditsImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;


    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    // Constants
    const IERC165_BACKWARD_COMPATIBLE_ID: felt252 = 0x80ac58cd;
    const OLD_IERC1155_ID: felt252 = 0xd9b67a26;

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
        const UNEQUAL_ARRAYS_URI: felt252 = 'URI Array len do not match';
    }

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState, name: felt252, symbol: felt252, owner: ContractAddress
    ) {
        self.erc1155.initializer(name, symbol);
        self.ownable.initializer(owner);

        self.src5.register_interface(OLD_IERC1155_ID);
        self.src5.register_interface(IERC165_BACKWARD_COMPATIBLE_ID);
    }

    // Externals
    #[external(v0)]
    impl ExternalImpl of super::IExternal<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256) {
            self.erc1155._mint(to, token_id, value);
        }

        fn burn(ref self: ContractState, token_id: u256, value: u256) {
            self.erc1155._burn(get_caller_address(), token_id, value);
        }

        fn batch_mint(
            ref self: ContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
        ) {
            self.erc1155._batch_mint(to, token_ids, values);
        }

        fn batch_burn(ref self: ContractState, token_ids: Span<u256>, values: Span<u256>) {
            self.erc1155._batch_burn(get_caller_address(), token_ids, values);
        }

        fn set_uri(ref self: ContractState, token_id: u256, uri: felt252) {
            self.erc1155._set_uri(token_id, uri);
        }

        fn set_list_uri(
            ref self: ContractState, mut token_ids: Span<u256>, mut uris: Span<felt252>
        ) {
            assert(token_ids.len() == uris.len(), Errors::UNEQUAL_ARRAYS_URI);

            loop {
                if token_ids.len() == 0 {
                    break;
                }
                let id = *token_ids.pop_front().unwrap();
                let uri = *uris.pop_front().unwrap();

                self.erc1155._set_uri(id, uri);
            }
        }

        fn decimals(self: @ContractState) -> u8 {
            self.absorber.get_cc_decimals()
        }
    }
}
