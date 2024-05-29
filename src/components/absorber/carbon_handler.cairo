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

    // Internal imports
    use carbon_v3::components::absorber::interface::{IAbsorber, ICarbonCreditsHandler};
    use carbon_v3::data::carbon_vintage::{CarbonVintage, CarbonVintageType};

    // Constants

    const YEAR_SECONDS: u64 = 31556925;
    const CC_DECIMALS_MULTIPLIER: u256 = 1_000_000_000_000;
    const CREDIT_CARBON_TON: u256 = 1_000_000;
    const CC_DECIMALS: u8 = 6;

    #[storage]
    struct Storage {
        Absorber_starting_year: u64,
        Absorber_project_carbon: u256,
        Absorber_times: List<u64>,
        Absorber_absorptions: List<u64>,
        Absorber_vintage_cc: List<CarbonVintage>,
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
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of IAbsorber<ComponentState<TContractState>> {
        // Absorption
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

        fn share_to_cc(self: @ComponentState<TContractState>, share: u256, token_id: u256) -> u256 {
            let cc_supply = self.get_vintage_supply(token_id).into();
            share * cc_supply /100 / CC_DECIMALS_MULTIPLIER
        }

        fn cc_to_share(
            self: @ComponentState<TContractState>, cc_value: u256, token_id: u256
        ) -> u256 {
            let cc_supply = self.get_vintage_supply(token_id).into();
            (cc_value *100 * CC_DECIMALS_MULTIPLIER / cc_supply)
        }

        fn is_setup(self: @ComponentState<TContractState>) -> bool {
            self.Absorber_project_carbon.read()
                * self.Absorber_times.read().len().into()
                * self.Absorber_absorptions.read().len().into()
                * self.Absorber_vintage_cc.read().len().into()
                * self.Absorber_starting_year.read().into()
                * self.Absorber_project_carbon.read() != 0
        }

        // Constraints : times lapse between absorptions point should be equal to 1 year
        fn set_absorptions(
            ref self: ComponentState<TContractState>, times: Span<u64>, absorptions: Span<u64>
        ) {
            // [Check] Times and prices are defined
            assert(times.len() == absorptions.len(), 'Times and absorptions mismatch');
            assert(times.len() > 0, 'Inputs cannot be empty');

            let mut stored_vintage_cc: List<CarbonVintage> = self.Absorber_vintage_cc.read();

            // [Effect] Clean times and absorptions
            let mut stored_times: List<u64> = self.Absorber_times.read();
            stored_times.len = 0;
            let mut stored_absorptions: List<u64> = self.Absorber_absorptions.read();
            stored_absorptions.len = 0;

            // [Effect] Store new times and absorptions and carbon value in vintage
            let mut index: u32 = 0;
            let _ = stored_times.append(*times[index]);
            let _ = stored_absorptions.append(*absorptions[index]);
            // [Effect] 
            let mut vintage: CarbonVintage = self.Absorber_vintage_cc.read()[index];
            vintage.supply = *absorptions[index];
            let _ = stored_vintage_cc.set(index, vintage);

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
                let mut vintage: CarbonVintage = self.Absorber_vintage_cc.read()[index];
                let mut current_absorption = *absorptions[index] - *absorptions[index - 1];
                vintage.supply = current_absorption;
                let _ = stored_vintage_cc.set(index, vintage);
            };

            // [Event] Emit event
            let current_time = get_block_timestamp();
            self.emit(AbsorptionUpdate { time: current_time });
        }

        fn set_project_carbon(ref self: ComponentState<TContractState>, project_carbon: u256) {
            // [Event] Update storage
            self.Absorber_project_carbon.write(project_carbon);

            // [Event] Emit event
            self.emit(Event::ProjectValueUpdate(ProjectValueUpdate { value: project_carbon }));
        }

        fn compute_carbon_vintage_distribution(
            self: @ComponentState<TContractState>, share: u256
        ) -> Span<u256> {
            let times = self.Absorber_times.read();
            let absorptions = self.Absorber_absorptions.read();
            let absorptions_u256 = self
                .__span_u64_into_u256(absorptions.array().expect('Can\'t get absorptions').span());

            // [Check] list time and absorptions are equal size
            assert(times.len() == absorptions.len(), Errors::INVALID_ARRAY_LENGTH);

            let mut cc_distribution: Array<u256> = Default::default();
            let mut index = 0;
            loop {
                if index == times.len() {
                    break ();
                }
                let mut current_absorption: u256 = 0;
                if index == 0 {
                    current_absorption = *absorptions_u256[index];
                } else {
                    current_absorption = *absorptions_u256[index] - *absorptions_u256[index - 1];
                }
                cc_distribution.append((current_absorption * share / CC_DECIMALS_MULTIPLIER / 100));
                index += 1;
            };
            cc_distribution.span()
        }

        fn rebase_vintage(
            ref self: ComponentState<TContractState>, token_id: u256, new_cc_supply: u64
        ) {
            let mut stored_vintages: List<CarbonVintage> = self.Absorber_vintage_cc.read();
            let mut index = 0;
            loop {
                if index == stored_vintages.len() {
                    break;
                }
                let stored_vintage: CarbonVintage = stored_vintages[index].clone();
                if stored_vintage.vintage == token_id.into() {
                    let mut vintage = stored_vintages[index].clone();
                    let old_supply = vintage.supply;
                    if new_cc_supply < old_supply {
                        let diff = old_supply - new_cc_supply;
                        vintage.supply = new_cc_supply;
                        vintage.failed = vintage.failed + diff;
                        let _ = stored_vintages.set(index, vintage);
                        break;
                    }
                    vintage.supply = new_cc_supply;
                    let _ = stored_vintages.set(index, vintage);
                    break;
                }
                index += 1;
            };
            self.Absorber_vintage_cc.write(stored_vintages);
        }
    }

    #[embeddable_as(CarbonCreditsHandlerImpl)]
    impl CarbonCreditsHandler<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of ICarbonCreditsHandler<ComponentState<TContractState>> {
        fn get_cc_vintages(self: @ComponentState<TContractState>) -> Span<CarbonVintage> {
            self.Absorber_vintage_cc.read().array().expect('Can\'t get vintages').span()
        }

        fn get_vintage_years(self: @ComponentState<TContractState>) -> Span<u256> {
            let vintages = self.Absorber_vintage_cc.read();
            let mut years: Array<u256> = Default::default();
            let mut index = 0;
            loop {
                if index == vintages.len() {
                    break ();
                }
                let vintage = vintages[index].clone();
                years.append(vintage.vintage);
                index += 1;
            };
            years.span()
        }

        fn get_carbon_vintage(
            self: @ComponentState<TContractState>, token_id: u256
        ) -> CarbonVintage {
            if token_id == 0 {
                return Default::default();
            }
            let carbon_vintages: List<CarbonVintage> = self.Absorber_vintage_cc.read();
            let mut found_vintage: CarbonVintage = Default::default();

            let mut index = 0;
            let mut tmp_vintage: CarbonVintage = Default::default();
            loop {
                if index == carbon_vintages.len() {
                    break ();
                }

                tmp_vintage = carbon_vintages[index].clone();
                if tmp_vintage.vintage == token_id.into() {
                    found_vintage = carbon_vintages[index].clone();
                }
                index += 1;
            };

            return found_vintage;
        }

        fn get_cc_decimals(self: @ComponentState<TContractState>) -> u8 {
            CC_DECIMALS
        }

        fn update_vintage_status(
            ref self: ComponentState<TContractState>, token_id: u64, status: u8
        ) {
            let mut carbon_vintages: List<CarbonVintage> = self.Absorber_vintage_cc.read();
            let mut index = 0;

            loop {
                if index == carbon_vintages.len() {
                    break ();
                }

                let mut tmp_vintage: CarbonVintage = self.Absorber_vintage_cc.read()[index];
                if tmp_vintage.vintage == token_id.into() {
                    let new_status: CarbonVintageType = match status {
                        0 => CarbonVintageType::Unset,
                        1 => CarbonVintageType::Projected,
                        2 => CarbonVintageType::Confirmed,
                        3 => CarbonVintageType::Audited,
                        _ => CarbonVintageType::Unset,
                    };

                    tmp_vintage.status = new_status;
                    let _ = carbon_vintages.set(index, tmp_vintage);
                }
                index += 1;
            };

            self.Absorber_vintage_cc.write(carbon_vintages);
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
            let mut stored_vintages: List<CarbonVintage> = self.Absorber_vintage_cc.read();
            stored_vintages.len = 0;

            // [Storage] Store new starting year
            assert(starting_year > 0, Errors::INVALID_STARTING_YEAR);
            self.Absorber_starting_year.write(starting_year);

            // [Storage] Store new vintages
            let mut index = 0;
            let _ = stored_vintages
                .append(
                    CarbonVintage {
                        vintage: starting_year.into(),
                        supply: 0,
                        failed: 0,
                        status: CarbonVintageType::Projected,
                    }
                );
            loop {
                index += 1;
                if index == number_of_years {
                    break;
                }
                // [Effect] Store values
                let _ = stored_vintages
                    .append(
                        CarbonVintage {
                            vintage: (starting_year + index).into(),
                            supply: 0,
                            failed: 0,
                            status: CarbonVintageType::Projected,
                        }
                    );
            };

            self.Absorber_vintage_cc.write(stored_vintages);
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

