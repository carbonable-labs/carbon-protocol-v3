use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
pub trait IExternal<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, token_id: u256, value: u256);
    fn burn(ref self: TContractState, from: ContractAddress, token_id: u256, value: u256);
    fn batch_mint(
        ref self: TContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
    );
    fn batch_burn(
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
    fn balanceOf(self: @TContractState, account: ContractAddress, token_id: u256) -> u256;
    fn balance_of_batch(
        self: @TContractState, accounts: Span<ContractAddress>, token_ids: Span<u256>
    ) -> Span<u256>;
    fn balanceOfBatch(
        self: @TContractState, accounts: Span<ContractAddress>, token_ids: Span<u256>
    ) -> Span<u256>;
    fn safe_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        value: u256,
        data: Span<felt252>
    );
    fn safeTransferFrom(
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
    fn safeBatchTransferFrom(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_ids: Span<u256>,
        values: Span<u256>,
        data: Span<felt252>
    );
    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn setApprovalForAll(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn is_approved_for_all(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn isApprovedForAll(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn cc_to_internal(self: @TContractState, cc_value_to_send: u256, token_id: u256) -> u256;

    fn internal_to_cc(self: @TContractState, internal_value_to_send: u256, token_id: u256) -> u256;
    fn get_balances(self: @TContractState, account: ContractAddress) -> Span<u256>;
}


#[starknet::contract]
pub mod Project {
    use core::num::traits::Zero;
    use starknet::{get_caller_address, ContractAddress, ClassHash};

    use carbon_v3::components::erc1155::erc1155::{ERC1155Component, ERC1155HooksEmptyImpl};
    use carbon_v3::components::vintage::vintage::VintageComponent;
    use carbon_v3::components::metadata::MetadataComponent;

    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use erc4906::erc4906_component::ERC4906Component;

    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: VintageComponent, storage: vintage, event: VintageEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: ERC4906Component, storage: erc4906, event: ERC4906Event);
    component!(path: MetadataComponent, storage: metadata, event: MetadataEvent);

    impl ERC1155Impl = ERC1155Component::ERC1155Impl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl =
        OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl VintageImpl = VintageComponent::VintageImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl CarbonV3MetadataImpl = MetadataComponent::CarbonV3MetadataImpl<ContractState>;

    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;
    impl VintageInternalImpl = VintageComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl ERC4906InternalImpl = ERC4906Component::InternalImpl<ContractState>;

    // Constants
    use carbon_v3::constants::{
        OWNER_ROLE, MINTER_ROLE, OFFSETTER_ROLE, IERC165_BACKWARD_COMPATIBLE_ID, OLD_IERC1155_ID
    };

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


    pub mod Errors {
        pub const UNEQUAL_ARRAYS_URI: felt252 = 'URI Array len do not match';
        pub const INVALID_ARRAY_LENGTH: felt252 = 'ERC1155: no equal array length';
    }

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, starting_year: u32, number_of_years: u32
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(OWNER_ROLE, owner);
        self.accesscontrol.set_role_admin(MINTER_ROLE, OWNER_ROLE);
        self.accesscontrol.set_role_admin(OFFSETTER_ROLE, OWNER_ROLE);
        self.accesscontrol.set_role_admin(OWNER_ROLE, OWNER_ROLE);
        self.erc1155.initializer("");
        self.ownable.initializer(owner);
        self.vintage.initializer(starting_year, number_of_years);

        self.src5.register_interface(OLD_IERC1155_ID);
        self.src5.register_interface(IERC165_BACKWARD_COMPATIBLE_ID);
    }

    // Externals
    #[abi(embed_v0)]
    impl ExternalImpl of super::IExternal<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256) {
            // [Check] Only Minter can mint
            let isMinter = self.accesscontrol.has_role(MINTER_ROLE, get_caller_address());
            assert(isMinter, 'Only Minter can mint');
            self._mint(to, token_id, value);
        }

        fn burn(ref self: ContractState, from: ContractAddress, token_id: u256, value: u256) {
            // [Check] Only Offsetter can burn
            let isOffseter = self.accesscontrol.has_role(OFFSETTER_ROLE, get_caller_address());
            assert(isOffseter, 'Only Offsetter can burn');
            self._burn(from, token_id, value);
        }

        fn batch_mint(
            ref self: ContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
        ) {
            let isMinter = self.accesscontrol.has_role(MINTER_ROLE, get_caller_address());
            assert(isMinter, 'Only Minter can batch mint');
            self._batch_mint(to, token_ids, values);
        }

        fn batch_burn(
            ref self: ContractState,
            from: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>
        ) {
            // [Check] Only Offsetter can burn
            let isOffseter = self.accesscontrol.has_role(OFFSETTER_ROLE, get_caller_address());
            assert(isOffseter, 'Only Offsetter can batch burn');
            self._batch_offset(from, token_ids, values);
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
                ._emit_batch_metadata_update(from_token_id: 1, to_token_id: num_vintages.into());
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

        fn balanceOf(self: @ContractState, account: ContractAddress, token_id: u256) -> u256 {
            self._balance_of(account, token_id)
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

        fn balanceOfBatch(
            self: @ContractState, accounts: Span<ContractAddress>, token_ids: Span<u256>
        ) -> Span<u256> {
            super::IExternal::balance_of_batch(self, accounts, token_ids)
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>
        ) {
            self._safe_transfer_from(from, to, token_id, value, data);
        }

        fn safeTransferFrom(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>
        ) {
            self._safe_transfer_from(from, to, token_id, value, data)
        }

        fn safe_batch_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>
        ) {
            let mut index = 0;
            let self_snap = @self;
            let mut to_send = array![];
            loop {
                if index == token_ids.len() {
                    break;
                }
                to_send.append(self_snap.cc_to_internal(*values.at(index), *token_ids.at(index)));
                index += 1;
            };
            self._safe_batch_transfer_from(from, to, token_ids, to_send.span(), data);
        }

        fn safeBatchTransferFrom(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>
        ) {
            super::IExternal::safe_batch_transfer_from(ref self, from, to, token_ids, values, data)
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            self.erc1155.set_approval_for_all(operator, approved);
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            self.erc1155.set_approval_for_all(operator, approved);
        }

        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.erc1155.is_approved_for_all(owner, operator)
        }

        fn isApprovedForAll(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.erc1155.is_approved_for_all(owner, operator)
        }

        fn cc_to_internal(self: @ContractState, cc_value_to_send: u256, token_id: u256) -> u256 {
            let vintage_supply = self.vintage.get_carbon_vintage(token_id).supply.into();
            let initial_project_supply = self.vintage.get_initial_project_cc_supply();
            cc_value_to_send * initial_project_supply / vintage_supply
        }

        fn internal_to_cc(
            self: @ContractState, internal_value_to_send: u256, token_id: u256
        ) -> u256 {
            let vintage_supply = self.vintage.get_carbon_vintage(token_id).supply.into();
            let initial_project_supply = self.vintage.get_initial_project_cc_supply();
            internal_value_to_send * vintage_supply / initial_project_supply
        }

        fn get_balances(self: @ContractState, account: ContractAddress) -> Span<u256> {
            let mut token_ids = array![];
            let mut accounts = array![];
            let num_vintages = self.vintage.get_num_vintages();
            for i in 0
                ..num_vintages {
                    let token_id = (i + 1).into();
                    token_ids.append(token_id);
                    accounts.append(account);
                };
            super::IExternal::balance_of_batch(self, accounts.span(), token_ids.span())
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            // This function can only be called by the owner
            let isOwner = self.accesscontrol.has_role(OWNER_ROLE, get_caller_address());
            assert!(isOwner, "Only Owner can upgrade");

            // Replace the class hash upgrading the contract
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _balance_of(self: @ContractState, account: ContractAddress, token_id: u256) -> u256 {
            self.internal_to_cc(self.erc1155.balance_of(account, token_id), token_id)
        }

        fn _mint(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256) {
            let isMinter = self.accesscontrol.has_role(MINTER_ROLE, get_caller_address());
            assert(isMinter, 'Only Minter can mint');
            self.erc1155.mint(to, token_id, value);
            let cc_value = self.internal_to_cc(value, token_id);
            self
                .emit(
                    ERC1155Component::Event::TransferSingle(
                        ERC1155Component::TransferSingle {
                            operator: get_caller_address(),
                            from: Zero::zero(),
                            to,
                            id: token_id,
                            value: cc_value,
                        }
                    )
                );
        }

        fn _batch_mint(
            ref self: ContractState, to: ContractAddress, token_ids: Span<u256>, values: Span<u256>
        ) {
            self.erc1155.batch_mint(to, token_ids, values);
            let operator = get_caller_address();
            let mut values_to_emit: Array<u256> = Default::default();
            let self_snap = @self;
            let mut index = 0;
            loop {
                if index == token_ids.len() {
                    break;
                }
                let token_id = *token_ids.at(index);
                let cc_value = self_snap.internal_to_cc(*values.at(index), token_id);
                values_to_emit.append(cc_value);

                self
                    .emit(
                        ERC1155Component::Event::TransferSingle(
                            ERC1155Component::TransferSingle {
                                operator, from: Zero::zero(), to, id: token_id, value: cc_value,
                            }
                        )
                    );
                index += 1;
            };
            // TransferBatch not handled by Starkscan yet
        // let values_to_emit = values_to_emit.span();

            // self
        //     .emit(
        //         ERC1155Component::Event::TransferBatch(
        //             ERC1155Component::TransferBatch {
        //                 operator: get_caller_address(),
        //                 from: Zero::zero(),
        //                 to,
        //                 ids: token_ids,
        //                 values: values_to_emit,
        //             }
        //         )
        //     );
        }

        fn _burn(ref self: ContractState, from: ContractAddress, token_id: u256, value: u256) {
            self.erc1155.burn(from, token_id, value);
            let caller = get_caller_address();
            let cc_value = self.internal_to_cc(value, token_id);
            self
                .emit(
                    ERC1155Component::Event::TransferSingle(
                        ERC1155Component::TransferSingle {
                            operator: caller, from, to: Zero::zero(), id: token_id, value: cc_value,
                        }
                    )
                );
        }

        fn _batch_offset(
            ref self: ContractState,
            from: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>
        ) {
            self.erc1155.batch_burn(from, token_ids, values);
            let caller = get_caller_address();
            let mut values_to_emit: Array<u256> = Default::default();
            let self_snap = @self;
            let mut index = 0;
            loop {
                if index == token_ids.len() {
                    break;
                }
                let token_id = *token_ids.at(index);
                let cc_value = self_snap.internal_to_cc(*values.at(index), token_id);
                values_to_emit.append(cc_value);

                self
                    .emit(
                        ERC1155Component::Event::TransferSingle(
                            ERC1155Component::TransferSingle {
                                operator: caller,
                                from,
                                to: Zero::zero(),
                                id: token_id,
                                value: cc_value,
                            }
                        )
                    );

                index += 1;
            };
            // let values_to_emit = values_to_emit.span();
        // self
        //     .emit(
        //         ERC1155Component::Event::TransferBatch(
        //             ERC1155Component::TransferBatch {
        //                 operator: get_caller_address(),
        //                 from,
        //                 to: Zero::zero(),
        //                 ids: token_ids,
        //                 values: values_to_emit,
        //             }
        //         )
        //     );
        }

        fn _safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            value: u256,
            data: Span<felt252>
        ) {
            let to_send = self.cc_to_internal(value, token_id);
            self.erc1155.safe_transfer_from(from, to, token_id, to_send, data);
            self
                .emit(
                    ERC1155Component::Event::TransferSingle(
                        ERC1155Component::TransferSingle {
                            operator: get_caller_address(), from, to, id: token_id, value: value,
                        }
                    )
                );
        }

        fn _safe_batch_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_ids: Span<u256>,
            values: Span<u256>,
            data: Span<felt252>
        ) {
            self.erc1155.safe_batch_transfer_from(from, to, token_ids, values, data);
            let caller = get_caller_address();
            let mut values_to_emit: Array<u256> = Default::default();
            let self_snap = @self;
            let mut index = 0;
            loop {
                if index == token_ids.len() {
                    break;
                }
                let token_id = *token_ids.at(index);
                let cc_value = self_snap.internal_to_cc(*values.at(index), token_id);
                values_to_emit.append(cc_value);

                self
                    .emit(
                        ERC1155Component::Event::TransferSingle(
                            ERC1155Component::TransferSingle {
                                operator: caller, from, to, id: token_id, value: cc_value,
                            }
                        )
                    );

                index += 1;
            };
            // let values_to_emit = values_to_emit.span();
        // self
        //     .emit(
        //         ERC1155Component::Event::TransferBatch(
        //             ERC1155Component::TransferBatch {
        //                 operator: get_caller_address(),
        //                 from,
        //                 to,
        //                 ids: token_ids,
        //                 values: values_to_emit,
        //             }
        //         )
        //     );
        }
    }
}

