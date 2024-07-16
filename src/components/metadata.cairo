use starknet::ClassHash;

#[starknet::interface]
trait IMetadataHandler<TContractState> {
    fn uri(self: @TContractState, token_id: u256) -> ByteArray;
    fn set_uri(ref self: TContractState, class_hash: ClassHash);
}

#[starknet::interface]
trait IMetadataDescriptor<TContractState> {
    fn construct_uri(self: @TContractState, token_id: u256) -> ByteArray;
}

#[starknet::component]
mod MetadataComponent {
    use starknet::ClassHash;
    use super::{IMetadataDescriptorLibraryDispatcher, IMetadataDescriptorDispatcherTrait};

    #[storage]
    struct Storage {
        uri_implementation: ClassHash
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
        fn uri(self: @ComponentState<TContractState>, token_id: u256) -> ByteArray {
            let class_hash = self.uri_implementation.read();
            let uri_lib = IMetadataDescriptorLibraryDispatcher { class_hash };
            uri_lib.construct_uri(token_id)
        }

        fn set_uri(ref self: ComponentState<TContractState>, class_hash: ClassHash) {
            assert(!class_hash.is_zero(), 'URI class hash cannot be zero');
            let old_class_hash = self.uri_implementation.read();
            self.emit(MetadataUpgraded { old_class_hash, class_hash });
            self.uri_implementation.write(class_hash);
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

        dispatcher.set_uri(metadata_class.class_hash);
        let uri = dispatcher.uri(1);
        assert_eq!(uri, "bla bla bla");
    }
}
