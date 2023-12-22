use starknet::ContractAddress;

#[starknet::contract]
mod Minter {
    use starknet::{get_caller_address, ContractAddress, ClassHash};

    // Ownable
    use openzeppelin::access::ownable::interface::IOwnable;
    use openzeppelin::access::ownable::ownable::Ownable;

    // Upgradable
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::upgradeable::Upgradeable;

    // Mint
    use carbon_v3::components::mint::interface::{IMint};
    use carbon_v3::components::mint::module::Mint;

    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(
        ref self: ContractState,
        carbonable_project_address: ContractAddress,
        carbonable_project_slot: u256,
        payment_token_address: ContractAddress,
        public_sale_open: bool,
        max_value_per_tx: u256,
        min_value_per_tx: u256,
        max_value: u256,
        unit_price: u256,
        reserved_value: u256,
        owner: ContractAddress
    ) {
        self
            .initializer(
                carbonable_project_address,
                carbonable_project_slot,
                payment_token_address,
                public_sale_open,
                max_value_per_tx,
                min_value_per_tx,
                max_value,
                unit_price,
                reserved_value,
                owner
            );
    }

    // Upgradable

    #[external(v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Upgrade
            let mut unsafe_state = Upgradeable::unsafe_new_contract_state();
            Upgradeable::InternalImpl::_upgrade(ref unsafe_state, new_class_hash)
        }
    }

    // Access control

    #[external(v0)]
    impl OwnableImpl of IOwnable<ContractState> {
        fn owner(self: @ContractState) -> ContractAddress {
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::OwnableImpl::owner(@unsafe_state)
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let mut unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::OwnableImpl::transfer_ownership(ref unsafe_state, new_owner)
        }

        fn renounce_ownership(ref self: ContractState) {
            let mut unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::OwnableImpl::renounce_ownership(ref unsafe_state)
        }
    }

    // Externals

    #[external(v0)]
    impl MintImpl of IMint<ContractState> {
        fn get_carbonable_project_address(self: @ContractState) -> ContractAddress {
            let unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::get_carbonable_project_address(@unsafe_state)
        }


        fn get_payment_token_address(self: @ContractState) -> ContractAddress {
            let unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::get_payment_token_address(@unsafe_state)
        }


        fn is_public_sale_open(self: @ContractState) -> bool {
            let unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::is_public_sale_open(@unsafe_state)
        }

        fn get_unit_price(self: @ContractState) -> u256 {
            let unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::get_unit_price(@unsafe_state)
        }

        fn get_available_value(self: @ContractState) -> u256 {
            let unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::get_available_value(@unsafe_state)
        }

        fn get_claimed_value(self: @ContractState, account: ContractAddress) -> u256 {
            let unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::get_claimed_value(@unsafe_state, account)
        }

        fn is_sold_out(self: @ContractState) -> bool {
            let unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::is_sold_out(@unsafe_state)
        }

        fn is_canceled(self: @ContractState) -> bool {
            let unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::is_canceled(@unsafe_state)
        }

        fn set_public_sale_open(ref self: ContractState, public_sale_open: bool) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Set public sale open
            let mut unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::set_public_sale_open(ref unsafe_state, public_sale_open)
        }

        fn set_unit_price(ref self: ContractState, unit_price: u256) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Set unit price
            let mut unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::set_unit_price(ref unsafe_state, unit_price)
        }

        fn withdraw(ref self: ContractState) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Withdraw
            let mut unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::withdraw(ref unsafe_state)
        }

        fn transfer(
            ref self: ContractState,
            token_address: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Transfer
            let mut unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::transfer(ref unsafe_state, token_address, recipient, amount)
        }

        fn book(ref self: ContractState, value: u256, force: bool) {
            let mut unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::book(ref unsafe_state, value, force)
        }

        fn claim(ref self: ContractState, user_address: ContractAddress, id: u32) {
            let mut unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::claim(ref unsafe_state, user_address, id)
        }

        fn refund(ref self: ContractState, user_address: ContractAddress, id: u32) {
            let mut unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::refund(ref unsafe_state, user_address, id)
        }

        fn refund_to(
            ref self: ContractState, to: ContractAddress, user_address: ContractAddress, id: u32
        ) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Refund to address
            let mut unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::refund_to(ref unsafe_state, to, user_address, id)
        }

        fn cancel(ref self: ContractState) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Cancel the mint
            let mut unsafe_state = Mint::unsafe_new_contract_state();
            Mint::MintImpl::cancel(ref unsafe_state)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn initializer(
            ref self: ContractState,
            carbonable_project_address: ContractAddress,
            carbonable_project_slot: u256,
            payment_token_address: ContractAddress,
            public_sale_open: bool,
            max_value_per_tx: u256,
            min_value_per_tx: u256,
            max_value: u256,
            unit_price: u256,
            reserved_value: u256,
            owner: ContractAddress
        ) {
            // Access control
            let mut unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::initializer(ref unsafe_state, owner);

            // Mint
            let mut unsafe_state = Mint::unsafe_new_contract_state();
            Mint::InternalImpl::initializer(
                ref unsafe_state,
                carbonable_project_address,
                payment_token_address,
                public_sale_open,
                max_value,
                unit_price
            );
        }
    }
}
