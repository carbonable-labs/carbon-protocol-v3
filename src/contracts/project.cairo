use starknet::ContractAddress;

#[starknet::interface]
trait IERC721<TContractState> {
    fn get_name(self: @TContractState) -> felt252;
    fn get_symbol(self: @TContractState) -> felt252;
    fn get_token_uri(self: @TContractState, token_id: u256) -> felt252;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
    fn get_approved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn approve(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
    fn mint(ref self: TContractState, to: ContractAddress, token_id: u256);
}

#[starknet::interface]
trait IExternal<ContractState> {
    fn mint(
        ref self: ContractState,
        to: ContractAddress,
        token_id: u256,
        value: u256,
        erc721_address: ContractAddress
    );
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
    fn only_owner(self: @ContractState, caller_address: ContractAddress) -> bool;
    fn grant_minter_role(ref self: ContractState, minter: ContractAddress);
    fn revoke_minter_role(ref self: ContractState, account: ContractAddress);
    fn grant_offsetter_role(ref self: ContractState, offsetter: ContractAddress);
    fn revoke_offsetter_role(ref self: ContractState, account: ContractAddress);
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
    use super::{IERC721Dispatcher, IERC721DispatcherTrait};

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
    // Access Control - RBAC
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    // ERC4906
    use erc4906::erc4906_component::ERC4906Component;

    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: AbsorberComponent, storage: absorber, event: AbsorberEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: ERC4906Component, storage: erc4906, event: ERC4906Event);

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
    // Access Control
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;

    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;
    impl AbsorberInternalImpl = AbsorberComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl ERC4906InternalImpl = ERC4906Component::ERC4906HelperInternal<ContractState>;

    // Constants
    const IERC165_BACKWARD_COMPATIBLE_ID: felt252 = 0x80ac58cd;
    const OLD_IERC1155_ID: felt252 = 0xd9b67a26;
    const CC_DECIMALS_MULTIPLIER: u256 = 100_000_000_000_000;
    const MINTER_ROLE: felt252 = selector!("Minter");
    const OFFSETTER_ROLE: felt252 = selector!("Offsetter");
    const OWNER_ROLE: felt252 = selector!("Owner");

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
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        erc4906: ERC4906Component::Storage,
        erc721_address: ContractAddress,
        has_minted_nft: bool
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
        AbsorberEvent: AbsorberComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        ERC4906Event: ERC4906Component::Event,
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
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(OWNER_ROLE, owner);
        self.accesscontrol._set_role_admin(MINTER_ROLE, OWNER_ROLE);
        self.accesscontrol._set_role_admin(OFFSETTER_ROLE, OWNER_ROLE);
        self.accesscontrol._set_role_admin(OWNER_ROLE, OWNER_ROLE);
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
        fn mint(
            ref self: ContractState,
            to: ContractAddress,
            token_id: u256,
            value: u256,
            erc721_address: ContractAddress
        ) {
            // [Check] Only Minter can mint
            let isMinter = self.accesscontrol.has_role(MINTER_ROLE, get_caller_address());
            assert(isMinter, 'Only Minter can mint');
            let has_minted_nft: bool = self.has_minted_nft.read();
            if has_minted_nft != true {
                let erc721 = IERC721Dispatcher { contract_address: erc721_address };
                erc721.mint(to, token_id);
                self.has_minted_nft.write(true);
            }
            self.erc1155.mint(to, token_id, value);
        }

        fn offset(ref self: ContractState, from: ContractAddress, token_id: u256, value: u256) {
            // [Check] Only Offsetter can offset
            let isOffseter = self.accesscontrol.has_role(OFFSETTER_ROLE, get_caller_address());
            assert(isOffseter, 'Only Offsetter can offset');
            let share_value = self.absorber.cc_to_share(value, token_id);
            self.erc1155.burn(from, token_id, share_value);
        }

        fn batch_mint(
            ref self: ContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
        ) {
            // TODO : Check the avalibility of the ampount of vintage cc_supply for each values.it should be done in the absorber/carbon_handler
            // [Check] Only Minter can mint
            let isMinter = self.accesscontrol.has_role(MINTER_ROLE, get_caller_address());
            assert(isMinter, 'Only Minter can batch mint');
            self.erc1155.batch_mint(to, token_ids, values);
        }

        fn batch_offset(
            ref self: ContractState,
            from: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>
        ) {
            // TODO : Check that the caller is the owner of the value he wnt to burn
            // [Check] Only Offsetter can offset
            let isOffseter = self.accesscontrol.has_role(OFFSETTER_ROLE, get_caller_address());
            assert(isOffseter, 'Only Offsetter can batch offset');
            self.erc1155.batch_burn(from, token_ids, values);
        }

        fn set_uri(ref self: ContractState, uri: ByteArray) {
            self.erc1155.set_base_uri(uri);

            // get all vintage years 
            let cc_vintage_years: Span<u256> = self.absorber.get_vintage_years();
            let from_vintage_year = *cc_vintage_years.at(0);
            let to_vintage_year = *cc_vintage_years.at(cc_vintage_years.len() - 1);

            /// Emit BatchMetadataUpdate event
            self
                .erc4906
                ._emit_batch_metadata_update(
                    fromTokenId: from_vintage_year, toTokenId: to_vintage_year
                );
        }

        fn get_uri(self: @ContractState, token_id: u256) -> ByteArray {
            let uri_result: ByteArray = self.erc1155.uri(token_id);
            uri_result
        }

        fn decimals(self: @ContractState) -> u8 {
            self.absorber.get_cc_decimals()
        }

        fn only_owner(self: @ContractState, caller_address: ContractAddress) -> bool {
            self.accesscontrol.has_role(OWNER_ROLE, caller_address)
        }

        fn grant_minter_role(ref self: ContractState, minter: ContractAddress) {
            let isOwner = self.accesscontrol.has_role(OWNER_ROLE, get_caller_address());
            assert!(isOwner, "Only Owner can grant minter role");
            self.accesscontrol._grant_role(MINTER_ROLE, minter);
        }

        fn revoke_minter_role(ref self: ContractState, account: ContractAddress) {
            let isOwner = self.accesscontrol.has_role(OWNER_ROLE, get_caller_address());
            assert!(isOwner, "Only Owner can revoke minter role");
            self.accesscontrol._revoke_role(MINTER_ROLE, account);
        }

        fn grant_offsetter_role(ref self: ContractState, offsetter: ContractAddress) {
            let isOwner = self.accesscontrol.has_role(OWNER_ROLE, get_caller_address());
            assert!(isOwner, "Only Owner can grant offsetter role");
            self.accesscontrol._grant_role(OFFSETTER_ROLE, offsetter);
        }

        fn revoke_offsetter_role(ref self: ContractState, account: ContractAddress) {
            let isOwner = self.accesscontrol.has_role(OWNER_ROLE, get_caller_address());
            assert!(isOwner, "Only Owner can revoke offsetter role");
            self.accesscontrol._revoke_role(OFFSETTER_ROLE, account);
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
