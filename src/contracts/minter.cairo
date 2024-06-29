use starknet::ContractAddress;

#[starknet::contract]
mod Minter {
    use starknet::{get_caller_address, ContractAddress, ClassHash};

    // Ownable
    use openzeppelin::access::ownable::OwnableComponent;
    // Upgradable
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    // Mint
    use carbon_v3::components::minter::mint::MintComponent;
    // RBAC interface
    use openzeppelin::access::accesscontrol::interface::IAccessControl;


    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: MintComponent, storage: mint, event: MintEvent);

    // ABI
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl =
        OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl MintImpl = MintComponent::MintImpl<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl MintInternalImpl = MintComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        mint: MintComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        MintEvent: MintComponent::Event
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        carbonable_project_address: ContractAddress,
        payment_token_address: ContractAddress,
        public_sale_open: bool,
        max_value: u256,
        unit_price: u256,
        owner: ContractAddress
    ) {
        self.ownable.initializer(owner);
        self
            .mint
            .initializer(
                carbonable_project_address,
                payment_token_address,
                public_sale_open,
                max_value,
                unit_price
            );
    }
}
