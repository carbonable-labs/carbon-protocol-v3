#[starknet::component]
mod OffsetComponent {
    // Core imports
    use core::hash::LegacyHash;


    // Starknet imports

    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map
    };

    // Internal imports

    use carbon_v3::components::offsetter::interface::IOffsetHandler;
    use alexandria_merkle_tree::merkle_tree::{
        Hasher, MerkleTree, MerkleTreeImpl, pedersen::PedersenHasherImpl, MerkleTreeTrait,
    };
    use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
    use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
    use carbon_v3::components::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use carbon_v3::contracts::project::{
        IExternalDispatcher as IProjectDispatcher,
        IExternalDispatcherTrait as IProjectDispatcherTrait
    };

    // Roles
    use openzeppelin::access::accesscontrol::interface::IAccessControl;

    // Constants
    use carbon_v3::contracts::project::Project::OWNER_ROLE;

    #[derive(Copy, Drop, Debug, Hash, starknet::Store, Serde, PartialEq)]
    struct Allocation {
        claimee: ContractAddress,
        amount: u128,
        timestamp: u128,
        id: u128
    }

    #[storage]
    struct Storage {
        Offsetter_carbonable_project_address: ContractAddress,
        Offsetter_carbon_pending_retirement: Map<(u256, ContractAddress), u256>,
        Offsetter_carbon_retired: Map<(u256, ContractAddress), u256>,
        Offsetter_merkle_root: felt252,
        Offsetter_allocations_claimed: Map<Allocation, bool>,
        Offsetter_allocation_id: Map<ContractAddress, u256>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        RequestedRetirement: RequestedRetirement,
        Retired: Retired,
        PendingRetirementRemoved: PendingRetirementRemoved,
        AllocationClaimed: AllocationClaimed,
    }

    #[derive(Drop, starknet::Event)]
    struct RequestedRetirement {
        #[key]
        from: ContractAddress,
        #[key]
        project: ContractAddress,
        #[key]
        token_id: u256,
        #[key]
        allocation_id: u256,
        old_amount: u256,
        new_amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Retired {
        #[key]
        from: ContractAddress,
        #[key]
        project: ContractAddress,
        #[key]
        token_id: u256,
        old_amount: u256,
        new_amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct PendingRetirementRemoved {
        #[key]
        from: ContractAddress,
        #[key]
        token_id: u256,
        old_amount: u256,
        new_amount: u256
    }

    #[derive(Drop, starknet::Event)]
    pub struct AllocationClaimed {
        pub claimee: ContractAddress,
        pub amount: u128,
        pub timestamp: u128,
        pub id: u128
    }

    mod Errors {
        const INVALID_VINTAGE_STATUS: felt252 = 'vintage status is not audited';
    }

    #[embeddable_as(OffsetHandlerImpl)]
    impl OffsetHandler<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IAccessControl<TContractState>
    > of IOffsetHandler<ComponentState<TContractState>> {
        fn retire_carbon_credits(
            ref self: ComponentState<TContractState>, token_id: u256, cc_amount: u256
        ) {
            let caller_address: ContractAddress = get_caller_address();
            let project_address: ContractAddress = self.Offsetter_carbonable_project_address.read();

            // [Check] Vintage got the right status
            let vintages = IVintageDispatcher { contract_address: project_address };
            let stored_vintage: CarbonVintage = vintages.get_carbon_vintage(token_id);
            assert(
                stored_vintage.status == CarbonVintageType::Audited, 'Vintage status is not audited'
            );

            let erc1155 = IERC1155Dispatcher { contract_address: project_address };
            let caller_balance = erc1155.balance_of(caller_address, token_id);
            assert(caller_balance >= cc_amount, 'Not own enough carbon credits');

            self._add_pending_retirement(caller_address, token_id, cc_amount);
        }

        fn retire_list_carbon_credits(
            ref self: ComponentState<TContractState>, token_ids: Span<u256>, cc_amounts: Span<u256>
        ) {
            // [Check] vintages and carbon values are defined
            assert(token_ids.len() > 0, 'Inputs cannot be empty');
            assert(token_ids.len() == cc_amounts.len(), 'Vintages and Values mismatch');

            let mut index: u32 = 0;
            loop {
                // [Check] Vintage is defined
                let token_id = *token_ids.at(index);
                let carbon_amount = *cc_amounts.at(index);

                if token_id != 0 && carbon_amount != 0 {
                    self.retire_carbon_credits(token_id, carbon_amount);
                }

                index += 1;
                if index == token_ids.len() {
                    break;
                }
            };
        }

        fn confirm_for_merkle_tree(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            amount: u128,
            timestamp: u128,
            id: u128,
            proof: Array::<felt252>
        ) -> bool {
            let mut merkle_tree: MerkleTree<Hasher> = MerkleTreeImpl::new();

            // [Verify the proof]
            let amount_felt: felt252 = amount.into();
            let from_felt: felt252 = from.into();
            let timestamp_felt: felt252 = timestamp.into();
            let id_felt: felt252 = id.into();

            let intermediate_hash = LegacyHash::hash(from_felt, amount_felt);
            let intermediate_hash = LegacyHash::hash(intermediate_hash, timestamp_felt);
            let leaf = LegacyHash::hash(intermediate_hash, id_felt);

            let root_computed = merkle_tree.compute_root(leaf, proof.span());

            let stored_root = self.Offsetter_merkle_root.read();
            if root_computed != stored_root {
                assert(root_computed == stored_root, 'Invalid proof');
                return false;
            }

            return true;
        }

        fn confirm_offset(
            ref self: ComponentState<TContractState>,
            amount: u128,
            timestamp: u128,
            id: u128,
            proof: Array::<felt252>
        ) {
            let claimee = get_caller_address();

            // [Verify not already claimed]
            let claimed = self.check_claimed(claimee, timestamp, amount, id);
            assert(!claimed, 'Already claimed');

            // [Verify if the merkle tree claim is possible]
            assert(
                self.confirm_for_merkle_tree(claimee, amount, timestamp, id, proof), 'Invalid proof'
            );

            //If everything is correct, we offset the carbon credits
            self._offset_carbon_credit(claimee, 1, amount.into());

            // [Mark as claimed]
            let allocation = Allocation {
                claimee: claimee, amount: amount, timestamp: timestamp, id: id
            };
            self.Offsetter_allocations_claimed.entry(allocation).write(true);

            // [Emit event]
            self
                .emit(
                    AllocationClaimed {
                        claimee: claimee, amount: amount, timestamp: timestamp, id: id
                    }
                );
        }

        fn get_allocation_id(self: @ComponentState<TContractState>, from: ContractAddress) -> u256 {
            self.Offsetter_allocation_id.entry(from).read()
        }

        fn get_retirement(
            self: @ComponentState<TContractState>, token_id: u256, from: ContractAddress
        ) -> u256 {
            self.Offsetter_carbon_retired.entry((token_id, from)).read()
        }


        fn get_pending_retirement(
            self: @ComponentState<TContractState>, address: ContractAddress, token_id: u256
        ) -> u256 {
            self.Offsetter_carbon_pending_retirement.entry((token_id, address)).read()
        }

        fn get_carbon_retired(
            self: @ComponentState<TContractState>, address: ContractAddress, token_id: u256
        ) -> u256 {
            self.Offsetter_carbon_retired.entry((token_id, address)).read()
        }

        fn check_claimed(
            self: @ComponentState<TContractState>,
            claimee: ContractAddress,
            timestamp: u128,
            amount: u128,
            id: u128
        ) -> bool {
            // Check if claimee has already claimed this allocation, by checking in the mapping
            let allocation = Allocation {
                claimee: claimee, amount: amount.into(), timestamp: timestamp.into(), id: id.into()
            };
            self.Offsetter_allocations_claimed.entry(allocation).read()
        }

        fn set_merkle_root(ref self: ComponentState<TContractState>, root: felt252) {
            self.assert_only_role(OWNER_ROLE);
            self.Offsetter_merkle_root.write(root);
        }

        fn get_merkle_root(self: @ComponentState<TContractState>) -> felt252 {
            self.Offsetter_merkle_root.read()
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IAccessControl<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(
            ref self: ComponentState<TContractState>, carbonable_project_address: ContractAddress
        ) {
            self.Offsetter_carbonable_project_address.write(carbonable_project_address);
        }

        fn _add_pending_retirement(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            token_id: u256,
            amount: u256
        ) {
            let current_pending_retirement = self
                .Offsetter_carbon_pending_retirement
                .entry((token_id, from))
                .read();

            let new_pending_retirement = current_pending_retirement + amount;
            self
                .Offsetter_carbon_pending_retirement
                .entry((token_id, from))
                .write(new_pending_retirement);

            let current_allocation_id = self.Offsetter_allocation_id.entry(from).read();
            let new_allocation_id = current_allocation_id + 1;
            self.Offsetter_allocation_id.entry(from).write(new_allocation_id);

            // transfer the carbon credits to the project
            let project = IProjectDispatcher {
                contract_address: self.Offsetter_carbonable_project_address.read()
            };
            project
                .safe_transfer_from(
                    from, get_contract_address(), token_id, amount, array![].span()
                );

            self
                .emit(
                    RequestedRetirement {
                        from: from,
                        project: self.Offsetter_carbonable_project_address.read(),
                        token_id: token_id,
                        allocation_id: new_allocation_id,
                        old_amount: current_pending_retirement,
                        new_amount: new_pending_retirement,
                    }
                );
        }

        fn _remove_pending_retirement(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            token_id: u256,
            amount: u256
        ) {
            let current_pending_retirement = self
                .Offsetter_carbon_pending_retirement
                .entry((token_id, from))
                .read();
            assert(current_pending_retirement >= amount, 'Not enough pending retirement');

            let new_pending_retirement = current_pending_retirement - amount;
            self
                .Offsetter_carbon_pending_retirement
                .entry((token_id, from))
                .write(new_pending_retirement);

            self
                .emit(
                    PendingRetirementRemoved {
                        from: from,
                        token_id: token_id,
                        old_amount: current_pending_retirement,
                        new_amount: new_pending_retirement
                    }
                );
        }

        fn _offset_carbon_credit(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            token_id: u256,
            amount: u256
        ) {
            self._remove_pending_retirement(from, token_id, amount);

            let project_address = self.Offsetter_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };
            let amount_to_offset = project.cc_to_internal(amount, token_id);
            project.burn(from, token_id, amount_to_offset);
            let current_retirement = self.Offsetter_carbon_retired.entry((token_id, from)).read();
            let new_retirement = current_retirement + amount;
            self.Offsetter_carbon_retired.entry((token_id, from)).write(new_retirement);

            self
                .emit(
                    Retired {
                        from: from,
                        project: self.Offsetter_carbonable_project_address.read(),
                        token_id: token_id,
                        old_amount: current_retirement,
                        new_amount: new_retirement
                    }
                );
        }

        fn assert_only_role(self: @ComponentState<TContractState>, role: felt252) {
            // [Check] Caller has role
            let caller = get_caller_address();
            let has_role = self.get_contract().has_role(role, caller);
            assert(has_role, 'Caller does not have role');
        }
    }
}
