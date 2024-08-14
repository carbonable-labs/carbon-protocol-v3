#[starknet::component]
mod OffsetComponent {
    // Core imports

    use core::clone::Clone;
    use core::array::SpanTrait;
    use core::hash::LegacyHash;
    use zeroable::Zeroable;
    use traits::{Into, TryInto};
    use option::OptionTrait;
    use array::{Array, ArrayTrait};
    use hash::HashStateTrait;
    use poseidon::PoseidonTrait;

    // Starknet imports

    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_contract_address, get_block_timestamp
    };

    // Internal imports

    use carbon_v3::components::offsetter::interface::IOffsetHandler;
    use carbon_v3::components::offsetter::merkle_tree::MerkleTreeTrait;
    use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
    use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
    use carbon_v3::components::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use carbon_v3::contracts::project::{
        IExternalDispatcher as IProjectDispatcher,
        IExternalDispatcherTrait as IProjectDispatcherTrait
    };

    // Constants
    use carbon_v3::contracts::project::Project::OWNER_ROLE;

    #[derive(Copy, Drop, Debug, Hash, starknet::Store, Serde, PartialEq)]
    struct Allocation {
        claimee: ContractAddress,
        amount: u128,
        timestamp: u128
    }

    #[storage]
    struct Storage {
        Offsetter_carbonable_project_address: ContractAddress,
        Offsetter_carbon_pending_retirement: LegacyMap<(u256, ContractAddress), u256>,
        Offsetter_carbon_retired: LegacyMap<(u256, ContractAddress), u256>,
        Offsetter_merkle_root: felt252,
        Offsetter_allocations_claimed: LegacyMap<
            Allocation, bool
        >, // todo: several deposit for same timestamp may cause issues
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
        pub timestamp: u128
    }

    mod Errors {
        const INVALID_VINTAGE_STATUS: felt252 = 'vintage status is not audited';
    }

    #[embeddable_as(OffsetHandlerImpl)]
    impl OffsetHandler<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of IOffsetHandler<ComponentState<TContractState>> {
        fn retire_carbon_credits(
            ref self: ComponentState<TContractState>, token_id: u256, cc_value: u256
        ) {
            let caller_address: ContractAddress = get_caller_address();
            let project_address: ContractAddress = self.Offsetter_carbonable_project_address.read();

            // [Check] Vintage got the right status
            let vintages = IVintageDispatcher { contract_address: project_address };
            let stored_vintage: CarbonVintage = vintages
                .get_carbon_vintage(token_id.try_into().expect('Invalid vintage year'));
            assert(
                stored_vintage.status == CarbonVintageType::Audited, 'Vintage status is not audited'
            );

            let erc1155 = IERC1155Dispatcher { contract_address: project_address };
            let caller_balance = erc1155.balance_of(caller_address, token_id);
            assert(caller_balance >= cc_value, 'Not own enough carbon credits');

            self._add_pending_retirement(caller_address, token_id, cc_value);
        }

        fn retire_list_carbon_credits(
            ref self: ComponentState<TContractState>,
            vintages: Span<u256>,
            carbon_values: Span<u256>
        ) {
            // [Check] vintages and carbon values are defined
            assert(vintages.len() > 0, 'Inputs cannot be empty');
            assert(vintages.len() == carbon_values.len(), 'Vintages and Values mismatch');

            let mut index: u32 = 0;
            loop {
                // [Check] Vintage is defined
                let token_id = match vintages.get(index) {
                    Option::Some(value) => *value.unbox(),
                    Option::None => 0,
                };
                let carbon_amount = match carbon_values.get(index) {
                    Option::Some(value) => *value.unbox(),
                    Option::None => 0,
                };

                if token_id != 0 && carbon_amount != 0 {
                    self.retire_carbon_credits(token_id, carbon_amount);
                }

                index += 1;
                if index == vintages.len() {
                    break;
                }
            };
        }

        fn claim(
            ref self: ComponentState<TContractState>,
            amount: u128,
            timestamp: u128,
            proof: Array::<felt252>
        ) {
            let mut merkle_tree = MerkleTreeTrait::new();
            let claimee = get_caller_address();
            // [Verify the proof]
            let amount_felt: felt252 = amount.into();
            let claimee_felt: felt252 = claimee.into();
            let timestamp_felt: felt252 = timestamp.into();

            let intermediate_hash = LegacyHash::hash(claimee_felt, amount_felt);
            let leaf = LegacyHash::hash(intermediate_hash, timestamp_felt);

            let root_computed = merkle_tree.compute_root(leaf, proof.span());
            let stored_root = self.Offsetter_merkle_root.read();
            assert(root_computed == stored_root, 'Invalid proof');

            // [Verify not already claimed]
            let claimed = self.check_claimed(claimee, timestamp, amount);
            assert(!claimed, 'Already claimed');

            // [Mark as claimed]
            let allocation = Allocation { claimee: claimee, amount: amount, timestamp: timestamp };
            self.Offsetter_allocations_claimed.write(allocation, true);

            // [Emit event]
            self.emit(AllocationClaimed { claimee: claimee, amount: amount, timestamp: timestamp });
        }

        fn get_pending_retirement(
            ref self: ComponentState<TContractState>, address: ContractAddress, token_id: u256
        ) -> u256 {
            self.Offsetter_carbon_pending_retirement.read((token_id, address))
        }

        fn get_carbon_retired(
            ref self: ComponentState<TContractState>, address: ContractAddress, token_id: u256
        ) -> u256 {
            self.Offsetter_carbon_retired.read((token_id, address))
        }

        fn check_claimed(
            ref self: ComponentState<TContractState>,
            claimee: ContractAddress,
            timestamp: u128,
            amount: u128
        ) -> bool {
            // check if claimee has already claimed for this timestamp, by checking in the mapping
            let allocation = Allocation {
                claimee: claimee, amount: amount.into(), timestamp: timestamp.into()
            };
            self.Offsetter_allocations_claimed.read(allocation)
        }

        fn set_merkle_root(ref self: ComponentState<TContractState>, root: felt252) {
            self.Offsetter_merkle_root.write(root);
        }

        fn get_merkle_root(ref self: ComponentState<TContractState>) -> felt252 {
            self.Offsetter_merkle_root.read()
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
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
                .read((token_id, from));

            let new_pending_retirement = current_pending_retirement + amount;
            self
                .Offsetter_carbon_pending_retirement
                .write((token_id, from), new_pending_retirement);

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
                        old_amount: current_pending_retirement,
                        new_amount: new_pending_retirement
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
                .read((token_id, from));
            assert(current_pending_retirement >= amount, 'Not enough pending retirement');

            let new_pending_retirement = current_pending_retirement - amount;
            self
                .Offsetter_carbon_pending_retirement
                .write((token_id, from), new_pending_retirement);

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

            let project = IProjectDispatcher {
                contract_address: self.Offsetter_carbonable_project_address.read()
            };
            let amount_to_offset = project.cc_to_internal(amount, token_id);
            project.burn(from, token_id, amount_to_offset);
            let current_retirement = self.Offsetter_carbon_retired.read((token_id, from));
            let new_retirement = current_retirement + amount;
            self.Offsetter_carbon_retired.write((token_id, from), new_retirement);

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
    }
}
