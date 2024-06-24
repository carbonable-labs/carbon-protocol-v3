#[starknet::component]
mod VintageComponent {
    // Starknet imports
    use starknet::get_block_timestamp;

    // Internal imports
    use carbon_v3::components::vintage::interface::IVintage;
    use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};

    // Constants
    use carbon_v3::models::constants::{CC_DECIMALS, CC_DECIMALS_MULTIPLIER};

    #[storage]
    struct Storage {
        Absorber_vintages: LegacyMap<u256, CarbonVintage>,
        Absorber_vintages_len: u64
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    enum Event {
        ProjectCarbonUpdate: ProjectCarbonUpdate,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProjectCarbonUpdate {
        old_carbon: u128,
        new_carbon: u128,
    }

    mod Errors {
        const INVALID_ARRAY_LENGTH: felt252 = 'Absorber: invalid array length';
        const INVALID_STARTING_YEAR: felt252 = 'Absorber: invalid starting year';
    }

    #[embeddable_as(VintageImpl)]
    impl Vintage<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of IVintage<ComponentState<TContractState>> {
        fn get_project_carbon(self: @ComponentState<TContractState>) -> u128 {
            let mut project_carbon: u128 = 0;

            let mut index = self.Absorber_vintages_len.read();
            while index > 0 {
                index -= 1;
                let vintage = self.Absorber_vintages.read(index.into());
                if vintage.status != CarbonVintageType::Unset {
                    project_carbon += vintage.supply.into();
                }
            };

            project_carbon
        }

        fn get_num_vintages(self: @ComponentState<TContractState>) -> u64 {
            self.Absorber_vintages_len.read().into()
        }

        fn get_cc_decimals(self: @ComponentState<TContractState>) -> u8 {
            CC_DECIMALS
        }

        fn share_to_cc(self: @ComponentState<TContractState>, share: u256, token_id: u256) -> u256 {
            let cc_supply = self.get_carbon_vintage(token_id).supply.into();
            share * cc_supply / CC_DECIMALS_MULTIPLIER
        }

        fn cc_to_share(
            self: @ComponentState<TContractState>, cc_value: u256, token_id: u256
        ) -> u256 {
            let cc_supply = self.get_carbon_vintage(token_id).supply.into();
            (cc_value * CC_DECIMALS_MULTIPLIER / cc_supply)
        }

        fn get_cc_vintages(self: @ComponentState<TContractState>) -> Span<CarbonVintage> {
            let mut vintages = ArrayTrait::<CarbonVintage>::new();
            let n = self.Absorber_vintages_len.read();
            let mut index = 0;
            loop {
                if index >= n {
                    break ();
                }
                let vintage = self.Absorber_vintages.read(index.into());
                vintages.append(vintage);
                index += 1;
            };
            vintages.span()
        }

        fn get_carbon_vintage(
            self: @ComponentState<TContractState>, token_id: u256
        ) -> CarbonVintage {
            self.Absorber_vintages.read(token_id)
        }


        fn rebase_vintage(
            ref self: ComponentState<TContractState>, token_id: u256, new_cc_supply: u128
        ) {
            let mut vintage: CarbonVintage = self.Absorber_vintages.read(token_id);
            let old_supply = vintage.supply;

            if new_cc_supply < old_supply {
                let diff = old_supply - new_cc_supply;
                vintage.supply = new_cc_supply;
                vintage.failed = vintage.failed + diff;
            }
            vintage.supply = new_cc_supply;
            self.Absorber_vintages.write(token_id, vintage);
        }


        fn update_vintage_status(
            ref self: ComponentState<TContractState>, token_id: u64, status: u8
        ) {
            let new_status: CarbonVintageType = status.try_into().expect('Invalid status');
            let mut vintage: CarbonVintage = self.Absorber_vintages.read(token_id.into());
            vintage.status = new_status;
            self.Absorber_vintages.write(token_id.into(), vintage);
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(
            ref self: ComponentState<TContractState>, starting_year: u64, number_of_years: u64
        ) {
            // [Storage] Store new vintages
            let mut index = starting_year;
            let n = index + number_of_years;
            loop {
                if index == n {
                    break ();
                }
                let vintage: CarbonVintage = CarbonVintage {
                    vintage: index.into(),
                    supply: 0,
                    failed: 0,
                    status: CarbonVintageType::Projected,
                };
                // [Effect] Store values
                self.Absorber_vintages.write(index.into(), vintage);
                index += 1;
            };
        }
    }
}
