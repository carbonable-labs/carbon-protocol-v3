#[starknet::component]
pub mod VintageComponent {
    // Starknet imports
    use starknet::get_caller_address;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map
    };


    // Internal imports
    use carbon_v3::components::vintage::interface::IVintage;
    use carbon_v3::models::{CarbonVintage, CarbonVintageType};

    // Constants
    use carbon_v3::constants::{CC_DECIMALS, OWNER_ROLE};


    // Roles
    use openzeppelin::access::accesscontrol::interface::IAccessControl;

    #[storage]
    pub struct Storage {
        Vintage_vintages: Map<u256, CarbonVintage>,
        Vintage_vintages_len: usize,
        Vintage_project_carbon: u256,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        ProjectCarbonUpdated: ProjectCarbonUpdated,
        VintageUpdate: VintageUpdate,
        VintageRebased: VintageRebased,
        VintageStatusUpdated: VintageStatusUpdated,
        VintageSet: VintageSet,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct VintageRebased {
        #[key]
        token_id: u256,
        old_supply: u256,
        new_supply: u256,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct VintageStatusUpdated {
        #[key]
        token_id: u256,
        old_status: CarbonVintageType,
        new_status: CarbonVintageType,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProjectCarbonUpdated {
        old_carbon: u256,
        new_carbon: u256,
    }


    #[derive(Drop, PartialEq, starknet::Event)]
    struct VintageUpdate {
        #[key]
        token_id: u256,
        old_vintage: CarbonVintage,
        new_vintage: CarbonVintage,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct VintageSet {
        #[key]
        token_id: u256,
        old_vintage: CarbonVintage,
        new_vintage: CarbonVintage,
    }

    pub mod Errors {
        pub const INVALID_ARRAY_LENGTH: felt252 = 'Vintage: invalid array length';
        pub const INVALID_STARTING_YEAR: felt252 = 'Vintage: invalid starting year';
        pub const INVALID_CALLER: felt252 = 'Vintage: invalid caller';
    }

    #[embeddable_as(VintageImpl)]
    impl Vintage<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IAccessControl<TContractState>
    > of IVintage<ComponentState<TContractState>> {
        fn get_project_carbon(self: @ComponentState<TContractState>) -> u256 {
            self.Vintage_project_carbon.read()
        }

        fn get_num_vintages(self: @ComponentState<TContractState>) -> usize {
            self.Vintage_vintages_len.read()
        }

        fn get_cc_decimals(self: @ComponentState<TContractState>) -> u8 {
            CC_DECIMALS
        }

        fn get_cc_vintages(self: @ComponentState<TContractState>) -> Span<CarbonVintage> {
            let mut vintages = ArrayTrait::<CarbonVintage>::new();
            let num_vintages = self.Vintage_vintages_len.read();
            let mut index = 0;
            loop {
                if index >= num_vintages {
                    break ();
                }
                let token_id: u256 = (index + 1).into();
                let vintage = self.Vintage_vintages.entry(token_id).read();
                vintages.append(vintage);
                index += 1;
            };
            vintages.span()
        }

        fn get_carbon_vintage(
            self: @ComponentState<TContractState>, token_id: u256
        ) -> CarbonVintage {
            self.Vintage_vintages.entry(token_id).read()
        }

        fn get_initial_cc_supply(self: @ComponentState<TContractState>, token_id: u256) -> u256 {
            self.get_carbon_vintage(token_id).supply
                + self.get_carbon_vintage(token_id).failed
                - self.get_carbon_vintage(token_id).created
        }

        fn get_initial_project_cc_supply(self: @ComponentState<TContractState>) -> u256 {
            let mut project_supply: u256 = 0;
            let num_vintage = self.Vintage_vintages_len.read();
            let mut index = 0;
            loop {
                if index >= num_vintage {
                    break ();
                }
                let token_id = (index + 1).into();
                let initial_vintage_supply = self.get_initial_cc_supply(token_id);
                project_supply += initial_vintage_supply;
                index += 1;
            };
            project_supply
        }


        fn rebase_vintage(
            ref self: ComponentState<TContractState>, token_id: u256, new_cc_supply: u256
        ) {
            self.assert_only_role(OWNER_ROLE);

            let mut vintage: CarbonVintage = self.Vintage_vintages.entry(token_id).read();
            let old_supply = vintage.supply;

            if (new_cc_supply == old_supply) {
                return ();
            }

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
            self.Vintage_vintages.entry(token_id).write(vintage);

            self
                .emit(
                    VintageRebased {
                        token_id: token_id, old_supply: old_supply, new_supply: new_cc_supply,
                    }
                );
        }


        fn update_vintage_status(
            ref self: ComponentState<TContractState>, token_id: u256, status: u8
        ) {
            self.assert_only_role(OWNER_ROLE);

            let new_status: CarbonVintageType = status.try_into().expect('Invalid status');
            let mut vintage: CarbonVintage = self.Vintage_vintages.entry(token_id).read();
            let old_status = vintage.status;
            vintage.status = new_status;
            self.Vintage_vintages.entry(token_id).write(vintage);

            self
                .emit(
                    VintageStatusUpdated {
                        token_id: token_id, old_status: old_status, new_status: new_status,
                    }
                );
        }

        fn set_vintages(
            ref self: ComponentState<TContractState>,
            yearly_absorptions: Span<u256>,
            start_year: u32
        ) {
            self.assert_only_role(OWNER_ROLE);

            assert(yearly_absorptions.len() > 0, Errors::INVALID_ARRAY_LENGTH);
            let vintages_num = yearly_absorptions.len();

            // [Effect] Update storage
            let mut index = 0;
            loop {
                if index == vintages_num {
                    break ();
                }
                let supply = *yearly_absorptions.at(index);
                let token_id = (index + 1).into();
                let old_vintage = self.Vintage_vintages.entry(token_id).read();
                let new_vintage = CarbonVintage {
                    year: (start_year + index).into(),
                    supply: supply,
                    failed: 0,
                    created: 0,
                    status: CarbonVintageType::Projected,
                };
                self.Vintage_vintages.entry(token_id).write(new_vintage);

                self.emit(VintageUpdate { token_id, old_vintage, new_vintage });
                index += 1;
            };
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IAccessControl<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(
            ref self: ComponentState<TContractState>, starting_year: u32, number_of_years: u32
        ) {
            // [Storage] Store new vintages
            self.Vintage_vintages_len.write(number_of_years.into());
            let mut index = 0;
            let n = number_of_years;
            loop {
                if index == n {
                    break ();
                }
                let token_id = (index + 1).into();

                let vintage: CarbonVintage = CarbonVintage {
                    year: index.into(),
                    supply: 0,
                    failed: 0,
                    created: 0,
                    status: CarbonVintageType::Projected,
                };

                self.Vintage_vintages.entry(token_id).write(vintage);
                index += 1;
            };
        }

        fn assert_only_role(ref self: ComponentState<TContractState>, role: felt252) {
            // [Check] Caller has role
            let caller = get_caller_address();
            let has_role = self.get_contract().has_role(role, caller);
            assert(has_role, Errors::INVALID_CALLER);
        }
    }
}
