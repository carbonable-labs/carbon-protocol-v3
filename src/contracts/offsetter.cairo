use starknet::ContractAddress;

#[starknet::contract]
mod Offsetter {
    use starknet::{get_caller_address, ContractAddress, ClassHash};

    // Ownable
    use openzeppelin::access::ownable::OwnableComponent;
    // Upgradable
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    // Offsetter
    use carbon_v3::components::offsetter::offset_handler::OffsetComponent;


    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: OffsetComponent, storage: offsetter, event: OffsetEvent);

    // ABI
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl =
        OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl MintImpl = OffsetComponent::OffsetHandlerImpl<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl MintInternalImpl = OffsetComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        offsetter: OffsetComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        OffsetEvent: OffsetComponent::Event
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, carbonable_project_address: ContractAddress, owner: ContractAddress
    ) {
        self.ownable.initializer(owner);
        self.offsetter.initializer(carbonable_project_address);
    }
}
