#[starknet::component]
mod VintageComponent {
    // Starknet imports
    use starknet::{get_block_timestamp, get_caller_address};

    // Internal imports
    use carbon_v3::components::vintage::interface::IVintage;
    use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};

    // Constants
    use carbon_v3::models::constants::{CC_DECIMALS, CC_DECIMALS_MULTIPLIER};
    use carbon_v3::contracts::project::Project::OWNER_ROLE;

    // Roles
    use openzeppelin::access::accesscontrol::interface::IAccessControl;

    #[storage]
    struct Storage {
        Vintage_vintages: LegacyMap<u256, CarbonVintage>,
        Vintage_vintages_len: usize,
        Vintage_project_carbon: u128,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    enum Event {
        ProjectCarbonUpdate: ProjectCarbonUpdate,
        VintageUpdate: VintageUpdate,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProjectCarbonUpdate {
        old_carbon: u128,
        new_carbon: u128,
    }


    #[derive(Drop, PartialEq, starknet::Event)]
    struct VintageUpdate {
        #[key]
        token_id: u256,
        vintage: CarbonVintage,
    }

    mod Errors {
        const INVALID_ARRAY_LENGTH: felt252 = 'Absorber: invalid array length';
        const INVALID_STARTING_YEAR: felt252 = 'Absorber: invalid starting year';
    }

    #[embeddable_as(VintageImpl)]
    impl Vintage<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IAccessControl<TContractState>
    > of IVintage<ComponentState<TContractState>> {
        fn get_project_carbon(self: @ComponentState<TContractState>) -> u128 {
            let mut project_carbon: u128 = 0;

            // let mut index = self.Vintage_vintages_len.read();
            // while index > 0 {
            //     index -= 1;
            //     let vintage = self.Vintage_vintages.read(index.into());
            //     if vintage.status != CarbonVintageType::Unset {
            //         project_carbon += vintage.supply.into();
            //     }
            // };

            project_carbon = self.Vintage_project_carbon.read();

            project_carbon
        }

        fn get_num_vintages(self: @ComponentState<TContractState>) -> usize {
            self.Vintage_vintages_len.read()
        }

        fn get_cc_decimals(self: @ComponentState<TContractState>) -> u8 {
            CC_DECIMALS
        }

        // Share is a percentage, 100% = CC_DECIMALS_MULTIPLIER
        fn share_to_cc(self: @ComponentState<TContractState>, share: u256, token_id: u256) -> u256 {
            let cc_supply: u256 = self.get_carbon_vintage(token_id).supply.into();
            let result = share * cc_supply / CC_DECIMALS_MULTIPLIER;
            assert(result <= cc_supply, 'CC value exceeds vintage supply');
            result
        }

        fn cc_to_share(
            self: @ComponentState<TContractState>, cc_value: u256, token_id: u256
        ) -> u256 {
            let cc_supply = self.get_carbon_vintage(token_id).supply.into();
            assert(cc_supply > 0, 'CC supply of vintage is 0');
            let share = cc_value * CC_DECIMALS_MULTIPLIER / cc_supply;
            assert(share <= CC_DECIMALS_MULTIPLIER, 'Share value exceeds 100%');
            share
        }

        fn get_cc_vintages(self: @ComponentState<TContractState>) -> Span<CarbonVintage> {
            let mut vintages = ArrayTrait::<CarbonVintage>::new();
            let n = self.Vintage_vintages_len.read();
            let mut index = 0;
            loop {
                if index >= n {
                    break ();
                }
                let vintage = self.Vintage_vintages.read(index.into());
                vintages.append(vintage);
                index += 1;
            };
            vintages.span()
        }

        fn get_carbon_vintage(
            self: @ComponentState<TContractState>, token_id: u256
        ) -> CarbonVintage {
            self.Vintage_vintages.read(token_id)
        }

        fn get_initial_cc_supply(self: @ComponentState<TContractState>, token_id: u256) -> u128 {
            self.get_carbon_vintage(token_id).supply
                + self.get_carbon_vintage(token_id).failed
                - self.get_carbon_vintage(token_id).created
        }


        fn rebase_vintage(
            ref self: ComponentState<TContractState>, token_id: u256, new_cc_supply: u128
        ) {
            // [Check] Caller is owner
            self.assert_only_role(OWNER_ROLE);

            let mut vintage: CarbonVintage = self.Vintage_vintages.read(token_id);
            let old_supply = vintage.supply;

            assert(new_cc_supply != old_supply, 'New supply same as old supply');

            // Negative rebase, failed carbon credits
            if new_cc_supply < old_supply {
                let diff = old_supply - new_cc_supply;
                vintage.supply = new_cc_supply;
                vintage.failed = vintage.failed + diff;
            } // Positive rebase, created carbon credits
            else {
                let diff = new_cc_supply - old_supply;
                vintage.supply = new_cc_supply;
                vintage.created = vintage.created + diff;
            }
            vintage.supply = new_cc_supply;
            self.Vintage_vintages.write(token_id, vintage);
        }


        fn update_vintage_status(
            ref self: ComponentState<TContractState>, token_id: u256, status: u8
        ) {
            // [Check] Caller is owner
            self.assert_only_role(OWNER_ROLE);

            let new_status: CarbonVintageType = status.try_into().expect('Invalid status');
            let mut vintage: CarbonVintage = self.Vintage_vintages.read(token_id);
            vintage.status = new_status;
            self.Vintage_vintages.write(token_id, vintage);
        }

        fn set_project_carbon(ref self: ComponentState<TContractState>, new_carbon: u128) {
            // [Check] Caller is owner
            self.assert_only_role(OWNER_ROLE);

            // [Check] Project carbon is not 0
            assert(new_carbon >= 0, 'Project carbon cannot be 0');
            // [Effect] Update storage
            let old_carbon = self.Vintage_project_carbon.read();
            self.Vintage_project_carbon.write(new_carbon);
            // [Event] Emit event
            self.emit(ProjectCarbonUpdate { old_carbon, new_carbon, });
        }

        fn set_vintages(
            ref self: ComponentState<TContractState>,
            yearly_absorptions: Span<u128>,
            start_year: u32
        ) {
            // [Check] Caller is owner
            self.assert_only_role(OWNER_ROLE);

            // [Check] Vintages length is not 0
            assert(yearly_absorptions.len() > 0, 'Vintages length is 0');
            let vintages_num = yearly_absorptions.len();

            // [Effect] Update storage
            self.Vintage_vintages_len.write(vintages_num);
            let mut index = 0;
            loop {
                if index == vintages_num {
                    break ();
                }
                let supply = *yearly_absorptions.at(index);

                let vintage = CarbonVintage {
                    year: (start_year + index).into(),
                    supply: supply,
                    failed: 0,
                    created: 0,
                    status: CarbonVintageType::Projected,
                };
                self.Vintage_vintages.write(index.into(), vintage);
                self.emit(VintageUpdate { token_id: index.into(), vintage: vintage, });
                index += 1;
            };
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
            ref self: ComponentState<TContractState>, starting_year: u32, number_of_years: u32
        ) {
            // [Storage] Store new vintages
            let mut index = starting_year;
            let n = index + number_of_years;
            loop {
                if index == n {
                    break ();
                }
                let vintage: CarbonVintage = CarbonVintage {
                    year: index.into(),
                    supply: 0,
                    failed: 0,
                    created: 0,
                    status: CarbonVintageType::Projected,
                };
                // [Effect] Store values
                self.Vintage_vintages.write(index.into(), vintage);
                index += 1;
            };
        }

        fn assert_only_role(ref self: ComponentState<TContractState>, role: felt252) {
            // [Check] Caller has role
            let caller = get_caller_address();
            let has_role = self.get_contract().has_role(role, caller);
            assert(has_role, 'Caller does not have role');
        }
    }
}
