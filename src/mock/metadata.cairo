#[starknet::contract]
mod TestContract {
    use starknet::ContractAddress;
    use carbon_v3::components::metadata::{MetadataComponent, IMetadataHandler};

    component!(path: MetadataComponent, storage: metadata_uri, event: MetadataEvent);

    #[abi(embed_v0)]
    impl MetadataImpl = MetadataComponent::CarbonV3MetadataImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        metadata_uri: MetadataComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MetadataEvent: MetadataComponent::Event
    }
}

#[starknet::contract]
mod TestMetadata {
    use carbon_v3::components::metadata::IMetadataDescriptor;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MetadataProviderImpl of IMetadataDescriptor<ContractState> {
        fn construct_uri(self: @ContractState, token_id: u256) -> ByteArray {
            "bla bla bla"
        }
    }
}
