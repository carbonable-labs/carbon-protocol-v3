use starknet::ContractAddress;

#[starknet::interface]
trait IExternal<ContractState> {
    fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256);
    fn burn(ref self: ContractState, from: ContractAddress, token_id: u256, value: u256);
    fn batch_mint(
        ref self: ContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
    );
    fn batch_burn(
        ref self: ContractState, from: ContractAddress, token_ids: Span<u256>, values: Span<u256>
    );
    fn set_uri(ref self: ContractState, uri: ByteArray);
    fn decimals(self: @ContractState) -> u8;
    fn balance(self: @ContractState, account: ContractAddress, token_id: u256) -> u256;
    fn only_owner(self: @ContractState);
}


#[starknet::contract]
mod Project {
    use carbon_v3::components::absorber::interface::ICarbonCreditsHandlerDispatcher;
    use carbon_v3::components::erc1155::erc1155::ERC1155Component::InternalTrait;
    use core::traits::Into;
    use starknet::{get_caller_address, ContractAddress, ClassHash};

    // Ownable
    use openzeppelin::access::ownable::OwnableComponent;
    // Upgradable
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    //SRC5
    use openzeppelin::introspection::src5::SRC5Component;
    // ERC1155
    use carbon_v3::components::erc1155::ERC1155Component;
    // Absorber
    use carbon_v3::components::absorber::carbon_handler::AbsorberComponent;

    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: AbsorberComponent, storage: absorber, event: AbsorberEvent);

    // ERC1155
    #[abi(embed_v0)]
    impl ERC1155Impl = ERC1155Component::ERC1155Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC1155MetadataURIImpl =
        ERC1155Component::ERC1155MetadataURIImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC1155Camel = ERC1155Component::ERC1155CamelImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl =
        OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl AbsorberImpl = AbsorberComponent::AbsorberImpl<ContractState>;
    #[abi(embed_v0)]
    impl CarbonCreditsHandlerImpl =
        AbsorberComponent::CarbonCreditsHandlerImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;
    impl AbsorberInternalImpl = AbsorberComponent::InternalImpl<ContractState>;

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
        ref self: ContractState,
        base_uri: felt252,
        owner: ContractAddress,
        starting_year: u64,
        number_of_years: u64
    ) {
        let base_uri_bytearray: ByteArray = format!("{}", base_uri);
        self.erc1155.initializer(base_uri_bytearray);
        self.ownable.initializer(owner);
        self.absorber.initializer(starting_year, number_of_years);

        self.src5.register_interface(OLD_IERC1155_ID);
        self.src5.register_interface(IERC165_BACKWARD_COMPATIBLE_ID);
    }

    // Externals
    #[abi(embed_v0)]
    impl ExternalImpl of super::IExternal<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256) {
            self.erc1155.mint(to, token_id, value);
        }

        fn burn(ref self: ContractState, from: ContractAddress, token_id: u256, value: u256) {
            self.erc1155.burn(from, token_id, value);
        }

        fn batch_mint(
            ref self: ContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
        ) {
            // TODO : Add access control as only the Minter in the list should be able to mint the tokens
            // TODO : Check the avalibility of the ampount of vintage cc_supply for each values.it should be done in the absorber/carbon_handler
            self.erc1155.batch_mint(to, token_ids, values);
        }

        fn batch_burn(
            ref self: ContractState,
            from: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>
        ) {
            // TODO : Check that the caller is the owner of the value he wnt to burn
            // TODO : Add access control as only the Burner in the list should be able to burn the values
            self.erc1155.batch_burn(from, token_ids, values);
        }

        fn set_uri(ref self: ContractState, uri: ByteArray) {
            self.erc1155.set_base_uri(uri);
        }

        fn decimals(self: @ContractState) -> u8 {
            6
        }

    }
}
