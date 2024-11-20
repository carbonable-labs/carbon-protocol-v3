use starknet::{ClassHash, ContractAddress};

#[starknet::interface]
trait IMetadataHandler<TContractState> {
    fn uri(self: @TContractState, token_id: u256) -> Span<felt252>;
    fn get_provider(self: @TContractState) -> ContractAddress;
    fn set_provider(ref self: TContractState, provider: ContractAddress);
    fn get_uri(self: @TContractState) -> ClassHash;
    fn set_uri(ref self: TContractState, class_hash: ClassHash);
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
        MetadataHandler_uri_implementation: ClassHash,
        MetadataHandler_provider: ContractAddress,
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
            let class_hash = self.MetadataHandler_uri_implementation.read();
            let uri_lib = IMetadataDescriptorLibraryDispatcher { class_hash };
            uri_lib.construct_uri(token_id)
        }

        fn get_provider(self: @ComponentState<TContractState>) -> ContractAddress {
            self.MetadataHandler_provider.read()
        }

        fn set_provider(ref self: ComponentState<TContractState>, provider: ContractAddress) {
            self.MetadataHandler_provider.write(provider);
        }

        fn get_uri(self: @ComponentState<TContractState>,) -> ClassHash {
            self.MetadataHandler_uri_implementation.read()
        }

        fn set_uri(ref self: ComponentState<TContractState>, class_hash: ClassHash,) {
            assert(!class_hash.is_zero(), 'URI class hash cannot be zero');
            let old_class_hash = self.MetadataHandler_uri_implementation.read();
            self.MetadataHandler_uri_implementation.write(class_hash);
            self.emit(MetadataUpgraded { old_class_hash, class_hash });
        }
    }
}

#[cfg(test)]
mod TestMetadataComponent {
    use starknet::ClassHash;
    use super::MetadataComponent;
    use super::{IMetadataHandlerDispatcherTrait, IMetadataHandlerDispatcher};
    use carbon_v3::mock::metadata::TestMetadata;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

    #[test]
    fn test_metadata() {
        let class = declare("TestContract").expect('Declaration failed').contract_class();
        let metadata_class = declare("TestMetadata").expect('Declaration failed').contract_class();

        let (contract_address, _) = class.deploy(@array![]).expect('Deployment failed');

        let dispatcher = IMetadataHandlerDispatcher { contract_address };

        dispatcher.set_uri(*metadata_class.class_hash);
        assert_eq!(@dispatcher.get_uri(), metadata_class.class_hash);
    }
}
