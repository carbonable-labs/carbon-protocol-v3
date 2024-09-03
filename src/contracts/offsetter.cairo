use starknet::ContractAddress;

#[starknet::contract]
mod Offsetter {
    use starknet::{ContractAddress, ClassHash};

    // Constants
    const OWNER_ROLE: felt252 = selector!("Owner");

    // Ownable
    use openzeppelin::access::ownable::OwnableComponent;
    // Upgradable
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    //SRC5
    use openzeppelin::introspection::src5::SRC5Component;
    // Offsetter
    use carbon_v3::components::offsetter::offset_handler::OffsetComponent;
    // Access Control - RBAC
    use openzeppelin::access::accesscontrol::AccessControlComponent;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OffsetComponent, storage: offsetter, event: OffsetEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);

    // ABI
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl =
        OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl OffsetImpl = OffsetComponent::OffsetHandlerImpl<ContractState>;
    // #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    // Access Control
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl OffsetInternalImpl = OffsetComponent::InternalImpl<ContractState>;
    // impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        offsetter: OffsetComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OffsetEvent: OffsetComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, carbonable_project_address: ContractAddress, owner: ContractAddress
    ) {
        self.ownable.initializer(owner);
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(OWNER_ROLE, owner);
        self.offsetter.initializer(carbonable_project_address);
    }
}
