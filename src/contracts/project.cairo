use starknet::ContractAddress;

#[starknet::interface]
trait IExternal<ContractState> {
    fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256);
    fn offset(ref self: ContractState, from: ContractAddress, token_id: u256, value: u256);
    fn batch_mint(
        ref self: ContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
    );
    fn batch_offset(
        ref self: ContractState, from: ContractAddress, token_ids: Span<u256>, values: Span<u256>
    );
    fn set_uri(ref self: ContractState, uri: ByteArray);
    fn get_uri(self: @ContractState, token_id: u256) -> ByteArray;
    fn decimals(self: @ContractState) -> u8;
    fn balance_of(self: @ContractState, account: ContractAddress, token_id: u256) -> u256;
    fn balance_of_batch(
        self: @ContractState, accounts: Span<ContractAddress>, token_ids: Span<u256>
    ) -> Span<u256>;
    fn shares_of(self: @ContractState, account: ContractAddress, token_id: u256) -> u256;
    fn safe_transfer_from(
        ref self: ContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        value: u256,
        data: Span<felt252>
    );
    fn safe_batch_transfer_from(
        ref self: ContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_ids: Span<u256>,
        values: Span<u256>,
        data: Span<felt252>
    );
    fn is_approved_for_all(
        self: @ContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn set_approval_for_all(ref self: ContractState, operator: ContractAddress, approved: bool);
}


#[starknet::contract]
mod Project {
    use carbon_v3::components::absorber::interface::ICarbonCreditsHandlerDispatcher;
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
    const CC_DECIMALS_MULTIPLIER: u256 = 100_000_000_000_000;

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
        const INVALID_ARRAY_LENGTH: felt252 = 'ERC1155: no equal array length';
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

        fn offset(ref self: ContractState, from: ContractAddress, token_id: u256, value: u256) {
            let share_value = self.absorber.cc_to_share(value, token_id);
            self.erc1155.burn(from, token_id, share_value);
        }

        fn batch_mint(
            ref self: ContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
        ) {
            // TODO : Add access control as only the Minter in the list should be able to mint the tokens
            // TODO : Check the avalibility of the ampount of vintage cc_supply for each values.it should be done in the absorber/carbon_handler
            self.erc1155.batch_mint(to, token_ids, values);
        }

        fn batch_offset(
            ref self: ContractState,
            from: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>
        ) {
            // TODO : Check that the caller is the owner of the value he wnt to burn
            // TODO : Add access control as only the Offsetter in the list should be able to burn the values
            self.erc1155.batch_burn(from, token_ids, values);
        }

        fn set_uri(ref self: ContractState, uri: ByteArray) {
            self.erc1155.set_base_uri(uri);
        }

        fn get_uri(self: @ContractState, token_id: u256) -> ByteArray {
            let uri_result: ByteArray = self.erc1155.uri(token_id);
            uri_result
        }

        fn decimals(self: @ContractState) -> u8 {
            self.absorber.get_cc_decimals()
        }

        fn balance_of(self: @ContractState, account: ContractAddress, token_id: u256) -> u256 {
            self._balance_of(account, token_id) // Internal call to avoid ambiguous call
        }

        fn balance_of_batch(
            self: @ContractState, accounts: Span<ContractAddress>, token_ids: Span<u256>
        ) -> Span<u256> {
            assert(accounts.len() == token_ids.len(), Errors::INVALID_ARRAY_LENGTH);

            let mut batch_balances = array![];
            let mut index = 0;
            loop {
                if index == token_ids.len() {
                    break;
                }
                batch_balances.append(self._balance_of(*accounts.at(index), *token_ids.at(index)));
                index += 1;
            };

            batch_balances.span()
        }

        fn shares_of(self: @ContractState, account: ContractAddress, token_id: u256) -> u256 {
            self.erc1155.ERC1155_balances.read((token_id, account))
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>
        ) {
            let share_value = self.absorber.cc_to_share(value, token_id);
            self.erc1155.safe_transfer_from(from, to, token_id, share_value, data);
        }

        fn safe_batch_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>
        ) {
            self.erc1155.safe_batch_transfer_from(from, to, token_ids, values, data);
        }

        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.erc1155.is_approved_for_all(owner, operator)
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            self.erc1155.set_approval_for_all(operator, approved);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _balance_of(self: @ContractState, account: ContractAddress, token_id: u256) -> u256 {
            let share = self.erc1155.balance_of(account, token_id);
            self.absorber.share_to_cc(share, token_id)
        }
    }
}
