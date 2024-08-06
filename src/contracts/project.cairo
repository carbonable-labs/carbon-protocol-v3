use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IExternal<TContractState> {
    // fn mint(ref self: TContractState, to: ContractAddress, token_id: u256, value: u256);
    fn offset(ref self: TContractState, from: ContractAddress, token_id: u256, value: u256);
    fn batch_mint(
        ref self: TContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
    );
    fn batch_offset(
        ref self: TContractState, from: ContractAddress, token_ids: Span<u256>, values: Span<u256>
    );
    fn uri(self: @TContractState, token_id: u256) -> Span<felt252>;
    fn get_provider(self: @TContractState) -> ContractAddress;
    fn set_provider(ref self: TContractState, provider: ContractAddress);
    fn get_uri(self: @TContractState) -> ClassHash;
    fn set_uri(ref self: TContractState, class_hash: ClassHash);
    fn decimals(self: @TContractState) -> u8;
    fn only_owner(self: @TContractState, caller_address: ContractAddress) -> bool;
    fn grant_minter_role(ref self: TContractState, minter: ContractAddress);
    fn revoke_minter_role(ref self: TContractState, account: ContractAddress);
    fn grant_offsetter_role(ref self: TContractState, offsetter: ContractAddress);
    fn revoke_offsetter_role(ref self: TContractState, account: ContractAddress);
    fn balance_of(self: @TContractState, account: ContractAddress, token_id: u256) -> u256;
    fn balance_of_batch(
        self: @TContractState, accounts: Span<ContractAddress>, token_ids: Span<u256>
    ) -> Span<u256>;
    fn shares_of(self: @TContractState, account: ContractAddress, token_id: u256) -> u256;
    fn safe_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        value: u256,
        data: Span<felt252>
    );
    fn safe_batch_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_ids: Span<u256>,
        values: Span<u256>,
        data: Span<felt252>
    );
    fn is_approved_for_all(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn cc_to_internal(
        self: @TContractState, account: ContractAddress, cc_value_to_send: u256, token_id: u256
    ) -> u256;
}


#[starknet::contract]
mod Project {
    use carbon_v3::components::vintage::interface::IVintageDispatcher;
    use starknet::{get_caller_address, ContractAddress, ClassHash};

    // Ownable
    use openzeppelin::access::ownable::OwnableComponent;
    // Upgradable
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    //SRC5
    use openzeppelin::introspection::src5::SRC5Component;
    // ERC1155
    use carbon_v3::components::erc1155::ERC1155Component;
    // Vintage
    use carbon_v3::components::vintage::VintageComponent;
    // Metadata
    use carbon_v3::components::metadata::MetadataComponent;
    // Access Control - RBAC
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    // ERC4906
    use erc4906::erc4906_component::ERC4906Component;

    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: VintageComponent, storage: vintage, event: VintageEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: ERC4906Component, storage: erc4906, event: ERC4906Event);
    component!(path: MetadataComponent, storage: metadata, event: MetadataEvent);

    // ERC1155
    impl ERC1155Impl = ERC1155Component::ERC1155Impl<ContractState>;
    // #[abi(embed_v0)]
    // impl ERC1155MetadataURIImpl =
    //     ERC1155Component::ERC1155MetadataURIImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC1155Camel = ERC1155Component::ERC1155CamelImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl =
        OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl VintageImpl = VintageComponent::VintageImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    // Access Control
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    // Metadata
    impl CarbonV3MetadataImpl = MetadataComponent::CarbonV3MetadataImpl<ContractState>;

    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;
    impl VintageInternalImpl = VintageComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl ERC4906InternalImpl = ERC4906Component::ERC4906HelperInternal<ContractState>;

    // Constants
    const IERC165_BACKWARD_COMPATIBLE_ID: felt252 = 0x80ac58cd;
    const OLD_IERC1155_ID: felt252 = 0xd9b67a26;
    use carbon_v3::models::constants::CC_DECIMALS_MULTIPLIER;
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
        vintage: VintageComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        erc4906: ERC4906Component::Storage,
        #[substorage(v0)]
        metadata: MetadataComponent::Storage,
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
        VintageEvent: VintageComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        ERC4906Event: ERC4906Component::Event,
        #[flat]
        MetadataEvent: MetadataComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterRoleGranted {
        account: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterRoleRevoked {
        account: ContractAddress,
    }

    mod Errors {
        const UNEQUAL_ARRAYS_URI: felt252 = 'URI Array len do not match';
        const INVALID_ARRAY_LENGTH: felt252 = 'ERC1155: no equal array length';
    }

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, starting_year: u32, number_of_years: u32
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(OWNER_ROLE, owner);
        self.accesscontrol._set_role_admin(MINTER_ROLE, OWNER_ROLE);
        self.accesscontrol._set_role_admin(OFFSETTER_ROLE, OWNER_ROLE);
        self.accesscontrol._set_role_admin(OWNER_ROLE, OWNER_ROLE);
        self.erc1155.initializer("");
        self.ownable.initializer(owner);
        self.vintage.initializer(starting_year, number_of_years);

        self.src5.register_interface(OLD_IERC1155_ID);
        self.src5.register_interface(IERC165_BACKWARD_COMPATIBLE_ID);
    }

    // Externals
    #[abi(embed_v0)]
    impl ExternalImpl of super::IExternal<ContractState> {
        // fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256) {
        //     // [Check] Only Minter can mint
        //     let isMinter = self.accesscontrol.has_role(MINTER_ROLE, get_caller_address());
        //     assert(isMinter, 'Only Minter can mint');
        //     self.erc1155.mint(to, token_id, value);
        // }

        fn offset(ref self: ContractState, from: ContractAddress, token_id: u256, value: u256) {
            // [Check] Only Offsetter can offset
            let isOffseter = self.accesscontrol.has_role(OFFSETTER_ROLE, get_caller_address());
            assert(isOffseter, 'Only Offsetter can offset');
            self.erc1155.burn(from, token_id, value);
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

        fn uri(self: @ContractState, token_id: u256) -> Span<felt252> {
            self.metadata.uri(token_id)
        }

        fn get_provider(self: @ContractState) -> ContractAddress {
            self.metadata.get_provider()
        }

        fn set_provider(ref self: ContractState, provider: ContractAddress) {
            let isOwner = self.accesscontrol.has_role(OWNER_ROLE, get_caller_address());
            assert!(isOwner, "Caller is not owner");
            self.metadata.set_provider(provider);
        }

        fn set_uri(ref self: ContractState, class_hash: ClassHash) {
            let isOwner = self.accesscontrol.has_role(OWNER_ROLE, get_caller_address());
            assert!(isOwner, "Caller is not owner");

            self.metadata.set_uri(class_hash);

            let num_vintages = self.vintage.get_num_vintages();

            /// Emit BatchMetadataUpdate event
            self
                .erc4906
                ._emit_batch_metadata_update(fromTokenId: 0, toTokenId: num_vintages.into());
        }

        fn get_uri(self: @ContractState) -> ClassHash {
            self.metadata.get_uri()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.vintage.get_cc_decimals()
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
            let amount_cc_bought = self
                .erc1155
                .ERC1155_balances
                .read((token_id, account)); // expressed in grams
            let initial_project_supply = self.vintage.get_initial_project_cc_supply();
            if initial_project_supply == 0 {
                panic!("Initial project supply is not set");
            }
            (amount_cc_bought * CC_DECIMALS_MULTIPLIER) / initial_project_supply.into()
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>
        ) {
            let to_send = self.cc_to_internal(from, value, token_id);
            self.erc1155.safe_transfer_from(from, to, token_id, to_send, data);
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

        fn cc_to_internal(
            self: @ContractState, account: ContractAddress, cc_value_to_send: u256, token_id: u256
        ) -> u256 {
            let vintage_supply = self.vintage.get_carbon_vintage(token_id).supply.into();
            let initial_project_supply = self.vintage.get_initial_project_cc_supply();
            cc_value_to_send * initial_project_supply / vintage_supply

        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _balance_of(self: @ContractState, account: ContractAddress, token_id: u256) -> u256 {
            let share = self.shares_of(account, token_id);
            let supply_vintage: u256 = self.vintage.get_carbon_vintage(token_id).supply.into();
            share * supply_vintage / CC_DECIMALS_MULTIPLIER
        }
    }
}
