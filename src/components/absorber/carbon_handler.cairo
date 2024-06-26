#[starknet::component]
mod AbsorberComponent {
    // Core imports
    use traits::Into;
    use array::{ArrayTrait, SpanTrait};

    // Starknet imports
    use starknet::{get_block_timestamp, get_caller_address, ContractAddress};

    // External imports
    use alexandria_numeric::interpolate::{interpolate, Interpolation, Extrapolation};
    use alexandria_storage::list::{List, ListTrait};
    use openzeppelin::access::accesscontrol::interface::IAccessControl;


    // Internal imports
    use carbon_v3::components::absorber::interface::{IAbsorber, ICarbonCreditsHandler};
    use carbon_v3::data::carbon_vintage::{CarbonVintage, CarbonVintageType};
    use carbon_v3::contracts::project::Project::{OWNER_ROLE};

    // Constants

    const YEAR_SECONDS: u64 = 31556925;
    const CC_DECIMALS_MULTIPLIER: u256 = 100_000_000_000_000;
    const CREDIT_CARBON_TON: u256 = 1_000_000;
    const CC_DECIMALS: u8 = 8; // from grams to convert to tons, with 2 decimals

    #[storage]
    struct Storage {
        Absorber_starting_year: u64,
        Absorber_project_carbon: u256,
        Absorber_times: List<u64>,
        Absorber_absorptions: List<u64>,
        Absorber_vintage_cc: LegacyMap<u256, CarbonVintage>,
        Absorber_number_of_vintages: u64
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AbsorptionUpdate: AbsorptionUpdate,
        ProjectValueUpdate: ProjectValueUpdate,
    }

    #[derive(Drop, starknet::Event)]
    struct AbsorptionUpdate {
        #[key]
        time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct ProjectValueUpdate {
        #[key]
        value: u256
    }


    mod Errors {
        const INVALID_ARRAY_LENGTH: felt252 = 'Absorber: invalid array length';
        const INVALID_STARTING_YEAR: felt252 = 'Absorber: invalid starting year';
    }

    #[embeddable_as(AbsorberImpl)]
    impl Absorber<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IAccessControl<TContractState>
    > of IAbsorber<ComponentState<TContractState>> {
        // Absorption
        fn get_starting_year(self: @ComponentState<TContractState>) -> u64 {
            self.Absorber_starting_year.read()
        }

        fn get_start_time(self: @ComponentState<TContractState>) -> u64 {
            let times = self.Absorber_times.read();
            if times.len() == 0 {
                return 0;
            }
            times[0]
        }

        fn get_final_time(self: @ComponentState<TContractState>) -> u64 {
            let times = self.Absorber_times.read();
            if times.len() == 0 {
                return 0;
            }
            times[times.len() - 1]
        }

        fn get_times(self: @ComponentState<TContractState>) -> Span<u64> {
            self.Absorber_times.read().array().expect('Can\'t get times').span()
        }

        fn get_absorptions(self: @ComponentState<TContractState>) -> Span<u64> {
            self.Absorber_absorptions.read().array().expect('Can\'t get absorptions').span()
        }

        fn get_absorption(self: @ComponentState<TContractState>, time: u64) -> u64 {
            let times = self.Absorber_times.read();
            if times.len() == 0 {
                return 0;
            }

            let absorptions = self.Absorber_absorptions.read();
            if absorptions.len() == 0 {
                return 0;
            }

            // [Compute] Convert into u256 to avoid overflow
            let time_u256: u256 = time.into();
            let times_u256 = self.__list_u64_into_u256(@times);
            let absorptions_u256 = self.__list_u64_into_u256(@absorptions);
            let absorption = interpolate(
                time_u256,
                times_u256,
                absorptions_u256,
                Interpolation::Linear,
                Extrapolation::Constant
            );

            absorption.try_into().expect('Absorber: Absorption overflow')
        }

        fn get_current_absorption(self: @ComponentState<TContractState>) -> u64 {
            self.get_absorption(get_block_timestamp())
        }

        fn get_final_absorption(self: @ComponentState<TContractState>) -> u64 {
            let absorptions = self.Absorber_absorptions.read();
            if absorptions.len() == 0 {
                return 0;
            }
            absorptions[absorptions.len() - 1]
        }

        fn get_project_carbon(self: @ComponentState<TContractState>) -> u256 {
            self.Absorber_project_carbon.read()
        }

        fn get_ton_equivalent(self: @ComponentState<TContractState>) -> u64 {
            // Use cc decimals to convert from grams to tons
            let carbon_g = self.Absorber_project_carbon.read();
            (carbon_g / CREDIT_CARBON_TON).try_into().expect('Absorber: Ton overflow')
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

        fn is_setup(self: @ComponentState<TContractState>) -> bool {
            self.Absorber_project_carbon.read()
                * self.Absorber_times.read().len().into()
                * self.Absorber_absorptions.read().len().into()
                * self.Absorber_number_of_vintages.read().into()
                * self.Absorber_starting_year.read().into()
                * self.Absorber_project_carbon.read() != 0
        }

        // Constraints : times lapse between absorptions point should be equal to 1 year
        fn set_absorptions(
            ref self: ComponentState<TContractState>, times: Span<u64>, absorptions: Span<u64>
        ) {
            // [Check] Caller is owner
            let caller_address = get_caller_address();
            let isOwner = self.get_contract().has_role(OWNER_ROLE, caller_address);
            assert(isOwner, 'Caller is not owner');

            // [Check] Times and prices are defined
            assert(times.len() == absorptions.len(), 'Times and absorptions mismatch');
            assert(times.len() > 0, 'Inputs cannot be empty');

            // [Effect] Clean times and absorptions
            let mut stored_times: List<u64> = self.Absorber_times.read();
            stored_times.len = 0;
            let mut stored_absorptions: List<u64> = self.Absorber_absorptions.read();
            stored_absorptions.len = 0;

            // [Effect] Store new times and absorptions and carbon value in vintage
            let starting_year: u32 = self.Absorber_starting_year.read().try_into().unwrap();
            let mut index: u32 = 0;
            let _ = stored_times.append(*times[index]);
            let _ = stored_absorptions.append(*absorptions[index]);
            // [Effect] 
            let mut vintage: CarbonVintage = self
                .Absorber_vintage_cc
                .read((starting_year + index).into());
            vintage.supply = *absorptions[index];
            vintage.status = CarbonVintageType::Projected;
            self.Absorber_vintage_cc.write((starting_year + index).into(), vintage);

            loop {
                index += 1;
                if index == times.len() {
                    break;
                }
                // [Check] Times are sorted
                assert(*times[index] > *times[index - 1], 'Times not sorted');
                // [Check] Absorptions are sorted
                assert(*absorptions[index] >= *absorptions[index - 1], 'Absorptions not sorted');
                // [Effect] Store values
                let _ = stored_times.append(*times[index]);
                let _ = stored_absorptions.append(*absorptions[index]);
                let mut vintage: CarbonVintage = self
                    .Absorber_vintage_cc
                    .read((starting_year + index).into());
                let mut current_absorption = *absorptions[index] - *absorptions[index - 1];
                vintage.supply = current_absorption;
                vintage.status = CarbonVintageType::Projected;
                self.Absorber_vintage_cc.write((starting_year + index).into(), vintage);
            };
            self.Absorber_number_of_vintages.write(index.into());

            // [Event] Emit event
            let current_time = get_block_timestamp();
            self.emit(AbsorptionUpdate { time: current_time });
        }

        fn set_project_carbon(ref self: ComponentState<TContractState>, project_carbon: u256) {
            // [Check] Caller is owner
            let caller_address = get_caller_address();
            let isOwner = self.get_contract().has_role(OWNER_ROLE, caller_address);
            assert(isOwner, 'Caller is not owner');

            // [Event] Update storage
            self.Absorber_project_carbon.write(project_carbon);

            // [Event] Emit event
            self.emit(Event::ProjectValueUpdate(ProjectValueUpdate { value: project_carbon }));
        }

        fn rebase_vintage(
            ref self: ComponentState<TContractState>, token_id: u256, new_cc_supply: u64
        ) {
            let mut vintage: CarbonVintage = self.Absorber_vintage_cc.read(token_id);
            let old_supply = vintage.supply;

            if new_cc_supply < old_supply {
                let diff = old_supply - new_cc_supply;
                vintage.supply = new_cc_supply;
                vintage.failed = vintage.failed + diff;
            }
            vintage.supply = new_cc_supply;
            self.Absorber_vintage_cc.write(token_id, vintage);
        }
    }

    #[embeddable_as(CarbonCreditsHandlerImpl)]
    impl CarbonCreditsHandler<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of ICarbonCreditsHandler<ComponentState<TContractState>> {
        fn get_cc_vintages(self: @ComponentState<TContractState>) -> Span<CarbonVintage> {
            let mut vintages = ArrayTrait::<CarbonVintage>::new();
            let mut index = self.Absorber_starting_year.read();
            let n = self.Absorber_number_of_vintages.read() + index;
            loop {
                if index >= n {
                    break ();
                }
                let vintage = self.Absorber_vintage_cc.read(index.into());
                vintages.append(vintage);
                index += 1;
            };
            vintages.span()
        }

        fn get_vintage_years(self: @ComponentState<TContractState>) -> Span<u256> {
            let mut years = ArrayTrait::<u256>::new();
            let mut index = self.Absorber_starting_year.read();
            let n = self.Absorber_number_of_vintages.read() + index - 1;
            loop {
                if index > n {
                    break ();
                }
                let vintage = self.Absorber_vintage_cc.read(index.into());
                years.append(vintage.vintage);
                index += 1;
            };

            years.span()
        }

        fn get_carbon_vintage(
            self: @ComponentState<TContractState>, token_id: u256
        ) -> CarbonVintage {
            self.Absorber_vintage_cc.read(token_id)
        }

        fn get_cc_decimals(self: @ComponentState<TContractState>) -> u8 {
            CC_DECIMALS
        }

        fn update_vintage_status(
            ref self: ComponentState<TContractState>, token_id: u64, status: u8
        ) {
            let new_status: CarbonVintageType = self.__u8_into_CarbonVintageType(status);
            let mut vintage: CarbonVintage = self.Absorber_vintage_cc.read(token_id.into());
            vintage.status = new_status;
            self.Absorber_vintage_cc.write(token_id.into(), vintage);
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(
            ref self: ComponentState<TContractState>, starting_year: u64, number_of_years: u64
        ) {
            // [Storage] Clean times and absorptions
            let mut stored_times: List<u64> = self.Absorber_times.read();
            stored_times.len = 0;
            let mut stored_absorptions: List<u64> = self.Absorber_absorptions.read();
            stored_absorptions.len = 0;

            // [Storage] Clean vintages
            let mut index = self.Absorber_starting_year.read();
            let n = self.Absorber_number_of_vintages.read() + index;
            loop {
                if index >= n {
                    break ();
                }
                self.Absorber_vintage_cc.write(index.into(), Default::default());
                index += 1;
            };

            // [Storage] Store new starting year
            assert(starting_year > 0, Errors::INVALID_STARTING_YEAR);
            self.Absorber_starting_year.write(starting_year);

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
                self.Absorber_vintage_cc.write(index.into(), vintage);
                index += 1;
            };
        }

        fn __list_u64_into_u256(
            self: @ComponentState<TContractState>, list: @List<u64>
        ) -> Span<u256> {
            let mut array = ArrayTrait::<u256>::new();
            let mut index = 0;
            loop {
                if index == list.len() {
                    break ();
                }
                array.append(list[index].into());
                index += 1;
            };
            array.span()
        }

        fn __span_u64_into_u256(
            self: @ComponentState<TContractState>, span: Span<u64>
        ) -> Span<u256> {
            let mut array = ArrayTrait::<u256>::new();
            let mut index = 0;
            loop {
                if index == span.len() {
                    break ();
                }
                array.append((*span[index]).into());
                index += 1;
            };
            array.span()
        }

        fn __u8_into_CarbonVintageType(
            self: @ComponentState<TContractState>, status: u8
        ) -> CarbonVintageType {
            assert(status < 4, 'Invalid status');
            match status {
                0 => CarbonVintageType::Unset,
                1 => CarbonVintageType::Projected,
                2 => CarbonVintageType::Confirmed,
                3 => CarbonVintageType::Audited,
                _ => CarbonVintageType::Unset,
            }
        }
    }
}

