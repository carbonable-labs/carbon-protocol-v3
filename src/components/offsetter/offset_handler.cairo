#[starknet::component]
mod OffsetComponent {
    // Core imports

    use core::clone::Clone;
    use core::array::SpanTrait;
    use zeroable::Zeroable;
    use traits::{Into, TryInto};
    use option::OptionTrait;
    use array::{Array, ArrayTrait};
    use hash::HashStateTrait;
    use poseidon::PoseidonTrait;

    // Starknet imports

    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};

    // Internal imports

    use carbon_v3::components::offsetter::interface::IOffsetHandler;
    use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
    use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
    use carbon_v3::components::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use carbon_v3::contracts::project::{
        IExternalDispatcher as IProjectDispatcher,
        IExternalDispatcherTrait as IProjectDispatcherTrait
    };

    // Constants

    const CC_DECIMALS_MULTIPLIER: u256 = 100_000_000_000_000;

    #[storage]
    struct Storage {
        Offsetter_carbonable_project_address: ContractAddress,
        Offsetter_carbon_pending_retirement: LegacyMap<(u256, ContractAddress), u256>,
        Offsetter_carbon_retired: LegacyMap<(u256, ContractAddress), u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        RequestedRetirement: RequestedRetirement,
        Retired: Retired,
        PendingRetirementRemoved: PendingRetirementRemoved,
    }

    #[derive(Drop, starknet::Event)]
    struct RequestedRetirement {
        #[key]
        from: ContractAddress,
        #[key]
        project: ContractAddress,
        #[key]
        vintage: u256,
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
        vintage: u256,
        old_amount: u256,
        new_amount: u256
    }

    #[derive(Drop, starknet::Event)]
struct PendingRetirementRemoved {
    #[key]
    from: ContractAddress,
    #[key]
    vintage: u256,
    old_amount: u256,
    new_amount: u256
}

    mod Errors {
        const INVALID_VINTAGE_STATUS: felt252 = 'vintage status is not audited';
    }

    #[embeddable_as(OffsetHandlerImpl)]
    impl OffsetHandler<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of IOffsetHandler<ComponentState<TContractState>> {
        fn retire_carbon_credits(
            ref self: ComponentState<TContractState>, vintage: u256, cc_value: u256
        ) { // TODO use token_id instead of vintage
            let caller_address: ContractAddress = get_caller_address();
            let project_address: ContractAddress = self.Offsetter_carbonable_project_address.read();

            // [Check] Vintage got the right status
            let vintages = IVintageDispatcher { contract_address: project_address };
            let stored_vintage: CarbonVintage = vintages
                .get_carbon_vintage(vintage.try_into().expect('Invalid vintage year'));
            assert(
                stored_vintage.status == CarbonVintageType::Audited, 'Vintage status is not audited'
            );

            let erc1155 = IERC1155Dispatcher { contract_address: project_address };
            let caller_balance = erc1155.balance_of(caller_address, vintage);
            assert(caller_balance >= cc_value, 'Not own enough carbon credits');
            
            self._add_pending_retirement(caller_address, vintage, cc_value);

            self._offset_carbon_credit(caller_address, vintage, cc_value);
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
                let vintage = match vintages.get(index) {
                    Option::Some(value) => *value.unbox(),
                    Option::None => 0,
                };
                let carbon_amount = match carbon_values.get(index) {
                    Option::Some(value) => *value.unbox(),
                    Option::None => 0,
                };

                if vintage != 0 && carbon_amount != 0 {
                    self.retire_carbon_credits(vintage, carbon_amount);
                }

                index += 1;
                if index == vintages.len() {
                    break;
                }
            };
        }

        fn get_pending_retirement(ref self: ComponentState<TContractState>, vintage: u256) -> u256 {
            let caller_address: ContractAddress = get_caller_address();
            self.Offsetter_carbon_pending_retirement.read((vintage, caller_address))
        }

        fn get_carbon_retired(ref self: ComponentState<TContractState>, vintage: u256) -> u256 {
            let caller_address: ContractAddress = get_caller_address();
            self.Offsetter_carbon_retired.read((vintage, caller_address))
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
            vintage: u256,
            amount: u256
        ) {
            let current_pending_retirement = self
                .Offsetter_carbon_pending_retirement
                .read((vintage, from));

            let new_pending_retirement = current_pending_retirement + amount;
            self.Offsetter_carbon_pending_retirement.write((vintage, from), new_pending_retirement);

            self
                .emit(
                    RequestedRetirement {
                        from: from,
                        project: self.Offsetter_carbonable_project_address.read(),
                        vintage: vintage,
                        old_amount: current_pending_retirement,
                        new_amount: new_pending_retirement
                    }
                );
        }

        fn _remove_pending_retirement(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            vintage: u256,
            amount: u256
        ) {
            let current_pending_retirement = self
                .Offsetter_carbon_pending_retirement
                .read((vintage, from));
            assert(current_pending_retirement >= amount, 'Not enough pending retirement');
            
            let new_pending_retirement = current_pending_retirement - amount;
            self.Offsetter_carbon_pending_retirement.write((vintage, from), new_pending_retirement);

            self.emit(
                PendingRetirementRemoved {
                    from: from,
                    vintage: vintage,
                    old_amount: current_pending_retirement,
                    new_amount: new_pending_retirement
                }
            );
        }

        fn _offset_carbon_credit(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            vintage: u256,
            amount: u256
        ) {
            self._remove_pending_retirement(from, vintage, amount);

            let project = IProjectDispatcher {
                contract_address: self.Offsetter_carbonable_project_address.read()
            };
            project.offset(from, vintage, amount);
            let current_retirement = self.Offsetter_carbon_retired.read((vintage, from));
            let new_retirement = current_retirement + amount;
            self.Offsetter_carbon_retired.write((vintage, from), new_retirement);

            self
                .emit(
                    Retired {
                        from: from,
                        project: self.Offsetter_carbonable_project_address.read(),
                        vintage: vintage,
                        old_amount: current_retirement,
                        new_amount: new_retirement
                    }
                );
        }
    }
}
