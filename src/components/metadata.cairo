use starknet::{ClassHash, ContractAddress};

#[starknet::interface]
trait IMetadataHandler<TContractState> {
    fn uri(self: @TContractState, token_id: u256) -> Span<felt252>;
    fn get_component_provider(self: @TContractState) -> ContractAddress;
    fn set_component_provider(ref self: TContractState, provider: ContractAddress);
    fn get_token_uri_implementation(self: @TContractState, token_id: u256) -> ClassHash;
    fn set_token_uri_implementation(
        ref self: TContractState, token_id: u256, class_hash: ClassHash
    );
}

#[starknet::interface]
trait IMetadataDescriptor<TContractState> {
    fn construct_uri(self: @TContractState, token_id: u256) -> Span<felt252>;
}

#[starknet::component]
mod MetadataComponent {
    use starknet::{ClassHash, ContractAddress};
    use super::{IMetadataDescriptorLibraryDispatcher, IMetadataDescriptorDispatcherTrait};

    #[storage]
    struct Storage {
        MetadataHandler_token_uri_implementation: LegacyMap<u256, ClassHash>,
        MetadataHandler_component_provider: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct MetadataUpgraded {
        old_class_hash: ClassHash,
        class_hash: ClassHash,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        MetadataUpgraded: MetadataUpgraded,
    }

    #[embeddable_as(CarbonV3MetadataImpl)]
    impl CarbonV3Metadata<
        TContractState, +HasComponent<TContractState>
    > of super::IMetadataHandler<ComponentState<TContractState>> {
        fn uri(self: @ComponentState<TContractState>, token_id: u256) -> Span<felt252> {
            let class_hash = self.MetadataHandler_token_uri_implementation.read(token_id);
            let uri_lib = IMetadataDescriptorLibraryDispatcher { class_hash };
            uri_lib.construct_uri(token_id)
        }

        fn set_token_uri_implementation(
            ref self: ComponentState<TContractState>, token_id: u256, class_hash: ClassHash,
        ) {
            assert(!class_hash.is_zero(), 'URI class hash cannot be zero');
            let old_class_hash = self.MetadataHandler_token_uri_implementation.read(token_id);
            self.emit(MetadataUpgraded { old_class_hash, class_hash });
            self.MetadataHandler_token_uri_implementation.write(token_id, class_hash);
        }

        fn get_component_provider(self: @ComponentState<TContractState>) -> ContractAddress {
            self.MetadataHandler_component_provider.read()
        }

        fn set_component_provider(
            ref self: ComponentState<TContractState>, provider: ContractAddress
        ) {
            self.MetadataHandler_component_provider.write(provider);
        }

        fn get_token_uri_implementation(
            self: @ComponentState<TContractState>, token_id: u256
        ) -> ClassHash {
            self.MetadataHandler_token_uri_implementation.read(token_id)
        }
    }
}

#[cfg(test)]
mod TestMetadataComponent {
    use starknet::ClassHash;
    use super::MetadataComponent;
    use super::{IMetadataHandlerDispatcherTrait, IMetadataHandlerDispatcher};
    use carbon_v3::mock::metadata::TestMetadata;
    use snforge_std::{declare, ContractClassTrait};

    #[test]
    fn test_metadata() {
        let class = declare("TestContract").expect('Declaration failed');
        let metadata_class = declare("TestMetadata").expect('Declaration failed');

        let (contract_address, _) = class.deploy(@array![]).expect('Deployment failed');
        let dispatcher = IMetadataHandlerDispatcher { contract_address };

        dispatcher.set_token_uri_implementation(0_u256, metadata_class.class_hash);
    }
}
