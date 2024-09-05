#[starknet::component]
mod ResaleComponent {
    // Core imports

    use core::num::traits::zero::Zero;
    use core::hash::LegacyHash;
    use hash::HashStateTrait;

    // Starknet imports

    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    // Internal imports

    use carbon_v3::components::resale::interface::IResaleHandler;
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

    // ERC20
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

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
        Resale_carbonable_project_address: ContractAddress,
        Resale_carbon_pending_resale: LegacyMap<(u256, ContractAddress), u256>,
        Resale_carbon_sold: LegacyMap<(u256, ContractAddress), u256>,
        Resale_merkle_root: felt252,
        Resale_allocations_claimed: LegacyMap<Allocation, bool>,
        Resale_allocation_id: LegacyMap<ContractAddress, u256>,
        Resale_token_address: ContractAddress,
        Resale_account_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        RequestedResale: RequestedResale,
        Resale: Resale,
        PendingResaleRemoved: PendingResaleRemoved,
        AllocationClaimed: AllocationClaimed,
    }

    #[derive(Drop, starknet::Event)]
    struct RequestedResale {
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
    struct Resale {
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
    struct PendingResaleRemoved {
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
        const NOT_ENOUGH_CARBON: felt252 = 'Resale: Not enough carbon';
        const NOT_ENOUGH_TOKENS: felt252 = 'Resale: Not enough tokens';
        const NOT_ENOUGH_PENDING: felt252 = 'Resale: Not enough pending';
        const EMPTY_INPUT: felt252 = 'Resale: Inputs cannot be empty';
        const ARRAY_MISMATCH: felt252 = 'Resale: Array lengths mismatch';
        const INVALID_PROOF: felt252 = 'Resale: Invalid proof';
        const ALREADY_CLAIMED: felt252 = 'Resale: Already claimed';
        const MISSING_ROLE: felt252 = 'Resale: Missing role';
        const ZERO_ADDRESS: felt252 = 'Resale: Address is invalid';
    }

    #[embeddable_as(ResaleHandlerImpl)]
    impl ResaleHandler<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IAccessControl<TContractState>
    > of IResaleHandler<ComponentState<TContractState>> {
        fn deposit_vintage(
            ref self: ComponentState<TContractState>, token_id: u256, cc_amount: u256
        ) {
            let caller_address: ContractAddress = get_caller_address();
            let project_address: ContractAddress = self.Resale_carbonable_project_address.read();

            let vintages = IVintageDispatcher { contract_address: project_address };
            let stored_vintage: CarbonVintage = vintages.get_carbon_vintage(token_id);
            assert(stored_vintage.status != CarbonVintageType::Unset, 'Vintage status is not set');

            let project = IProjectDispatcher { contract_address: project_address };
            let caller_balance = project.balance_of(caller_address, token_id);
            assert(caller_balance >= cc_amount, Errors::NOT_ENOUGH_CARBON);

            self._add_pending_resale(caller_address, token_id, cc_amount);
        }

        fn deposit_vintages(
            ref self: ComponentState<TContractState>, token_ids: Span<u256>, cc_amounts: Span<u256>
        ) {
            // [Check] vintages and carbon values are defined
            assert(token_ids.len() > 0, Errors::EMPTY_INPUT);
            assert(token_ids.len() == cc_amounts.len(), Errors::ARRAY_MISMATCH);

            let mut index: u32 = 0;
            loop {
                // [Check] Vintage is defined
                let token_id = *token_ids.at(index);
                let carbon_amount = *cc_amounts.at(index);

                if token_id != 0 && carbon_amount != 0 {
                    self.deposit_vintage(token_id, carbon_amount);
                }

                index += 1;
                if index == token_ids.len() {
                    break;
                }
            };
        }

        fn claim(
            ref self: ComponentState<TContractState>,
            amount: u128,
            timestamp: u128,
            id: u128,
            proof: Array::<felt252>
        ) {
            let mut merkle_tree: MerkleTree<Hasher> = MerkleTreeImpl::new();
            let claimee = get_caller_address();

            // [Verify not already claimed]
            let claimed = self.check_claimed(claimee, timestamp, amount, id);
            assert(!claimed, Errors::ALREADY_CLAIMED);

            // [Verify the proof]
            let amount_felt: felt252 = amount.into();
            let claimee_felt: felt252 = claimee.into();
            let timestamp_felt: felt252 = timestamp.into();
            let id_felt: felt252 = id.into();

            let intermediate_hash = LegacyHash::hash(claimee_felt, amount_felt);
            let intermediate_hash = LegacyHash::hash(intermediate_hash, timestamp_felt);
            let leaf = LegacyHash::hash(intermediate_hash, id_felt);

            let root_computed = merkle_tree.compute_root(leaf, proof.span());

            let stored_root = self.Resale_merkle_root.read();
            assert(root_computed == stored_root, Errors::INVALID_PROOF);

            // [Mark as claimed]
            let allocation = Allocation {
                claimee: claimee, amount: amount, timestamp: timestamp, id: id
            };
            self.Resale_allocations_claimed.write(allocation, true);

            self._claim_tokens(claimee, id.into(), amount.into());

            // [Emit event]
            self
                .emit(
                    AllocationClaimed {
                        claimee: claimee, amount: amount, timestamp: timestamp, id: id
                    }
                );
        }

        fn get_pending_resale(
            self: @ComponentState<TContractState>, address: ContractAddress, token_id: u256
        ) -> u256 {
            self.Resale_carbon_pending_resale.read((token_id, address))
        }

        fn get_carbon_sold(
            self: @ComponentState<TContractState>, address: ContractAddress, token_id: u256
        ) -> u256 {
            self.Resale_carbon_sold.read((token_id, address))
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
            self.Resale_allocations_claimed.read(allocation)
        }

        fn set_merkle_root(ref self: ComponentState<TContractState>, root: felt252) {
            self.assert_only_role(OWNER_ROLE);
            self.Resale_merkle_root.write(root);
        }

        fn get_merkle_root(self: @ComponentState<TContractState>) -> felt252 {
            self.Resale_merkle_root.read()
        }

        fn set_resale_token(
            ref self: ComponentState<TContractState>, token_address: ContractAddress
        ) {
            self.assert_only_role(OWNER_ROLE);
            assert(token_address.into() != 0, Errors::ZERO_ADDRESS);
            self.Resale_token_address.write(token_address);
        }

        fn get_resale_token(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Resale_token_address.read()
        }

        fn set_resale_account(
            ref self: ComponentState<TContractState>, account_address: ContractAddress
        ) {
            self.assert_only_role(OWNER_ROLE);
            assert(account_address.into() != 0, Errors::ZERO_ADDRESS);
            self.Resale_account_address.write(account_address);
        }

        fn get_resale_account(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Resale_account_address.read()
        }

        fn sell_carbon_credits(
            ref self: ComponentState<TContractState>,
            token_id: u256,
            cc_amount: u256,
            resale_price: u256,
            merkle_root: felt252,
        ) {
            self.assert_only_role(OWNER_ROLE);
            let this: ContractAddress = get_contract_address();
            let project_address: ContractAddress = self.Resale_carbonable_project_address.read();

            let project = IProjectDispatcher { contract_address: project_address };
            // let DECIMALS = project.decimals();

            // [Check] enough carbon credits and tokens
            let this_balance = project.balance_of(this, token_id);
            assert(this_balance >= cc_amount, Errors::NOT_ENOUGH_CARBON);

            // [Check] enough tokens
            let token_address = self.get_resale_token();
            let token = IERC20Dispatcher { contract_address: token_address };
            let token_amount = cc_amount * resale_price / 1_000_000; // USDC price per ton
            let caller = get_caller_address();
            let caller_balance = token.balance_of(caller);
            assert(caller_balance >= token_amount, Errors::NOT_ENOUGH_TOKENS);
            let allowance = token.allowance(caller, this);
            assert(allowance >= token_amount, Errors::NOT_ENOUGH_TOKENS);

            // [Transfer] carbon credits and tokens
            let account_address = self.get_resale_account();
            token.transfer_from(caller, this, token_amount);
            project.safe_transfer_from(this, account_address, token_id, cc_amount, array![].span());

            self.set_merkle_root(merkle_root);
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
            ref self: ComponentState<TContractState>,
            carbonable_project_address: ContractAddress,
            resale_token_address: ContractAddress,
            resale_account_address: ContractAddress
        ) {
            assert(carbonable_project_address.into() != 0, Errors::ZERO_ADDRESS);
            assert(resale_token_address.into() != 0, Errors::ZERO_ADDRESS);
            assert(resale_account_address.into() != 0, Errors::ZERO_ADDRESS);
            self.Resale_carbonable_project_address.write(carbonable_project_address);
            self.Resale_token_address.write(resale_token_address);
            self.Resale_account_address.write(resale_account_address);
        }

        fn _add_pending_resale(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            token_id: u256,
            amount: u256
        ) {
            let current_pending_resale = self.Resale_carbon_pending_resale.read((token_id, from));

            let new_pending_resale = current_pending_resale + amount;
            self.Resale_carbon_pending_resale.write((token_id, from), new_pending_resale);

            let current_allocation_id = self.Resale_allocation_id.read(from);
            let new_allocation_id = current_allocation_id + 1;
            self.Resale_allocation_id.write(from, new_allocation_id);

            // transfer the carbon credits to the project
            let project = IProjectDispatcher {
                contract_address: self.Resale_carbonable_project_address.read()
            };
            project
                .safe_transfer_from(
                    from, get_contract_address(), token_id, amount, array![].span()
                );

            self
                .emit(
                    RequestedResale {
                        from: from,
                        project: self.Resale_carbonable_project_address.read(),
                        token_id: token_id,
                        allocation_id: new_allocation_id,
                        old_amount: current_pending_resale,
                        new_amount: new_pending_resale,
                    }
                );
        }

        fn _remove_pending_resale(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            token_id: u256,
            amount: u256
        ) {
            let current_pending_resale = self.Resale_carbon_pending_resale.read((token_id, from));
            assert(current_pending_resale >= amount, Errors::NOT_ENOUGH_PENDING);

            let new_pending_resale = current_pending_resale - amount;
            self.Resale_carbon_pending_resale.write((token_id, from), new_pending_resale);

            self
                .emit(
                    PendingResaleRemoved {
                        from: from,
                        token_id: token_id,
                        old_amount: current_pending_resale,
                        new_amount: new_pending_resale
                    }
                );
        }

        fn _claim_tokens(
            ref self: ComponentState<TContractState>,
            user: ContractAddress,
            token_id: u256,
            amount: u256
        ) {
            let project_address = self.Resale_carbonable_project_address.read();
            self._remove_pending_resale(user, token_id, amount);

            // [Effect] Update the carbon credits sold
            let current_resale = self.Resale_carbon_sold.read((token_id, user));
            let new_resale = current_resale + amount;
            self.Resale_carbon_sold.write((token_id, user), new_resale);

            // [Effect] Transfer the tokens to the user
            let token_address = self.Resale_token_address.read();
            let token = IERC20Dispatcher { contract_address: token_address };
            token.transfer(user, amount);

            // [Emits] Resale event
            self
                .emit(
                    Resale {
                        from: user,
                        project: project_address,
                        token_id: token_id,
                        old_amount: current_resale,
                        new_amount: new_resale
                    }
                );
        }

        fn assert_only_role(self: @ComponentState<TContractState>, role: felt252) {
            // [Check] Caller has role
            let caller = get_caller_address();
            let has_role = self.get_contract().has_role(role, caller);
            assert(has_role, Errors::MISSING_ROLE);
        }
    }
}
