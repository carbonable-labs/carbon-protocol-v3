#[starknet::component]
mod AbsorberComponent {
    // Core imports
    use traits::Into;
    use array::{ArrayTrait, SpanTrait};

    // Starknet imports
    use starknet::{get_block_timestamp, get_caller_address, ContractAddress};

    // External imports
    use alexandria_numeric::interpolate::{
        interpolate_fast as interpolate, Interpolation, Extrapolation
    };
    use alexandria_storage::list::{List, ListTrait};

    // Internal imports
    use carbon_v3::components::absorber::interface::IAbsorber;

    #[storage]
    struct Storage {
        Absorber_ton_equivalent: u64,
        Absorber_project_value: u256,
        Absorber_times: List<u64>,
        Absorber_absorptions: List<u64>,
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
            self.Absorber_times.read().array().span()
        }
        fn get_absorptions(self: @ComponentState<TContractState>) -> Span<u64> {
            self.Absorber_absorptions.read().array().span()
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
        fn get_project_value(self: @ComponentState<TContractState>) -> u256 {
            self.Absorber_project_value.read()
        }
        fn get_ton_equivalent(self: @ComponentState<TContractState>) -> u64 {
            self.Absorber_ton_equivalent.read()
        }
        fn is_setup(self: @ComponentState<TContractState>) -> bool {
            self.Absorber_project_value.read()
                * self.Absorber_times.read().len().into()
                * self.Absorber_absorptions.read().len().into()
                * self.Absorber_ton_equivalent.read().into() != 0
        }
        fn set_absorptions(
            ref self: ComponentState<TContractState>,
            times: Span<u64>,
            absorptions: Span<u64>,
            ton_equivalent: u64
        ) {
            // [Check] Times and prices are defined
            assert(times.len() == absorptions.len(), 'Times and absorptions mismatch');
            assert(times.len() > 0, 'Inputs cannot be empty');
            assert(ton_equivalent > 0, 'Ton equivalent must be positive');

            // [Effect] Clean times and absorptions
            let mut stored_times: List<u64> = self.Absorber_times.read();
            stored_times.len = 0;
            let mut stored_absorptions: List<u64> = self.Absorber_absorptions.read();
            stored_absorptions.len = 0;

            // [Effect] Store new times and absorptions
            let mut index = 0;
            stored_times.append(*times[index]);
            stored_absorptions.append(*absorptions[index]);
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
                stored_times.append(*times[index]);
                stored_absorptions.append(*absorptions[index]);
            };

            // [Effect] Store new ton equivalent
            self.Absorber_ton_equivalent.write(ton_equivalent);

            // [Event] Emit event
            let current_time = get_block_timestamp();
            self.emit(AbsorptionUpdate { time: current_time });
        }
        fn set_project_value(ref self: ComponentState<TContractState>, project_value: u256) {
            // [Event] Update storage
            self.Absorber_project_value.write(project_value);

            // [Event] Emit event
            self.emit(Event::ProjectValueUpdate(ProjectValueUpdate { value: project_value }));
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of InternalTrait<TContractState> {
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
    }
}

