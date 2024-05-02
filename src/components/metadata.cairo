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
mod metadata_component {
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

    #[embeddable_as(CarbonV3Metadata)]
    impl MetadataImpl<
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
mod unit_test {
    use starknet::ClassHash;
    use super::metadata_component;
    use super::{IMetadataHandlerDispatcherTrait, IMetadataHandlerLibraryDispatcher};


    #[starknet::contract]
    mod TestContract {
        use starknet::ContractAddress;
        use carbon_v3::components::metadata::{metadata_component, IMetadataHandler};

        component!(path: super::metadata_component, storage: metadata_uri, event: MetadataEvent);

        #[abi(embed_v0)]
        impl MetadataComponent =
            metadata_component::CarbonV3Metadata<ContractState>;

        #[storage]
        struct Storage {
            #[substorage(v0)]
            metadata_uri: metadata_component::Storage
        }

        #[event]
        #[derive(Drop, starknet::Event)]
        enum Event {
            MetadataEvent: metadata_component::Event
        }
    }

    #[starknet::contract]
    mod TestMetadata {
        use carbon_v3::components::metadata::{IMetadataDescriptor};
        #[storage]
        struct Storage {}

        #[abi(embed_v0)]
        impl MetadataProviderImpl of IMetadataDescriptor<ContractState> {
            fn construct_uri(self: @ContractState, token_id: u256) -> ByteArray {
                "bla bla bla"
            }
        }
    }

    #[test]
    fn test_metadata() {
        let class_hash: ClassHash = TestContract::TEST_CLASS_HASH.try_into().unwrap();
        let contract = IMetadataHandlerLibraryDispatcher { class_hash };
        contract.set_uri(TestMetadata::TEST_CLASS_HASH.try_into().unwrap());
        let uri = contract.uri(1);
        assert_eq!(uri, "bla bla bla");
    }
}

