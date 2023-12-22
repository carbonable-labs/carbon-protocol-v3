use starknet::ContractAddress;

#[starknet::interface]
trait IExternal<ContractState> {
    fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256);
    fn burn(ref self: ContractState, token_id: u256, value: u256);
}


#[starknet::contract]
mod Project {
    use core::traits::Into;
    use starknet::{get_caller_address, ContractAddress, ClassHash};

    // Ownable
    use openzeppelin::access::ownable::interface::IOwnable;
    use openzeppelin::access::ownable::ownable::Ownable;

    // Upgradable
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::upgradeable::Upgradeable;

    //SRC5
    use openzeppelin::introspection::interface::{ISRC5, ISRC5Camel};
    use openzeppelin::introspection::src5::SRC5;

    // ERC721
    use openzeppelin::token::erc721::interface::{
        IERC721, IERC721Metadata, IERC721CamelOnly, IERC721MetadataCamelOnly
    };

    // ERC1155
    use token::erc1155::interface::{IERC1155, IERC1155Metadata};
    use token::erc1155::erc1155::ERC1155;

    // Access control
    use carbon_v3::components::access::interface::{IMinter, ICertifier};
    use carbon_v3::components::access::module::Access;

    // Absorber
    use carbon_v3::components::absorber::interface::IAbsorber;
    use carbon_v3::components::absorber::module::Absorber;

    const IERC165_BACKWARD_COMPATIBLE_ID: u32 = 0x80ac58cd_u32;

    // Storage

    #[storage]
    struct Storage {}

    // Events

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnershipTransferred: OwnershipTransferred,
        Upgraded: Upgraded,
        Transfer: Transfer,
        Approval: Approval,
        ApprovalForAll: ApprovalForAll,
        ApprovalForSlot: ApprovalForSlot,
        TransferValue: TransferValue,
        ApprovalValue: ApprovalValue,
        SlotChanged: SlotChanged,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        previous_owner: ContractAddress,
        new_owner: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct Upgraded {
        class_hash: ClassHash
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        #[key]
        token_id: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        #[key]
        owner: ContractAddress,
        #[key]
        approved: ContractAddress,
        #[key]
        token_id: u256
    }

    #[derive(Drop, starknet::Event)]
    struct ApprovalForAll {
        #[key]
        owner: ContractAddress,
        #[key]
        operator: ContractAddress,
        approved: bool
    }

    #[derive(Drop, starknet::Event)]
    struct ApprovalForSlot {
        owner: ContractAddress,
        slot: u256,
        operator: ContractAddress,
        approved: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct TransferValue {
        from_token_id: u256,
        to_token_id: u256,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ApprovalValue {
        token_id: u256,
        operator: ContractAddress,
        value: u256
    }

    #[derive(Drop, starknet::Event)]
    struct SlotChanged {
        token_id: u256,
        old_slot: u256,
        new_slot: u256,
    }

    // Constructor

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        uri: felt252,
        value_decimals: u8,
        owner: ContractAddress
    ) {
        self.initializer(name, symbol, uri, value_decimals, owner);
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

    #[external(v0)]
    impl MinterImpl of IMinter<ContractState> {
        fn get_minters(self: @ContractState) -> Span<ContractAddress> {
            let unsafe_state = Access::unsafe_new_contract_state();
            Access::MinterImpl::get_minters(@unsafe_state)
        }

        fn add_minter(ref self: ContractState, user: ContractAddress) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Add minter
            let mut unsafe_state = Access::unsafe_new_contract_state();
            Access::MinterImpl::add_minter(ref unsafe_state, user)
        }

        fn revoke_minter(ref self: ContractState, user: ContractAddress) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Revoke minter
            let mut unsafe_state = Access::unsafe_new_contract_state();
            Access::MinterImpl::revoke_minter(ref unsafe_state, user)
        }
    }

    #[external(v0)]
    impl CertifierImpl of ICertifier<ContractState> {
        fn get_certifier(self: @ContractState) -> ContractAddress {
            let unsafe_state = Access::unsafe_new_contract_state();
            Access::CertifierImpl::get_certifier(@unsafe_state)
        }

        fn set_certifier(ref self: ContractState, user: ContractAddress) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Set certifier
            let mut unsafe_state = Access::unsafe_new_contract_state();
            Access::CertifierImpl::set_certifier(ref unsafe_state, user)
        }
    }

    // SRC5

    #[external(v0)]
    impl SRC5Impl of ISRC5<ContractState> {
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            if interface_id == IERC165_BACKWARD_COMPATIBLE_ID.into() {
                return true;
            }
            let unsafe_state = SRC5::unsafe_new_contract_state();
            SRC5::SRC5Impl::supports_interface(@unsafe_state, interface_id)
        }
    }

    #[external(v0)]
    impl SRC5CamelImpl of ISRC5Camel<ContractState> {
        fn supportsInterface(self: @ContractState, interfaceId: felt252) -> bool {
            self.supports_interface(interfaceId)
        }
    }

    // ERC1155

    #[external(v0)]
    impl ERC1155Impl of IERC1155<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress, id: u256) -> u256 {
            let unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::ERC1155Impl::balance_of(@unsafe_state, account, id)
        }

        fn balance_of_batch(
            self: @ContractState, accounts: Array<ContractAddress>, ids: Array<u256>
        ) -> Array<u256> {
            let unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::ERC1155Impl::balance_of_batch(@unsafe_state, accounts, ids)
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            let mut unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::ERC1155Impl::set_approval_for_all(ref unsafe_state, operator, approved)
        }

        fn is_approved_for_all(
            self: @ContractState, account: ContractAddress, operator: ContractAddress
        ) -> bool {
            let unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::ERC1155Impl::is_approved_for_all(@unsafe_state, account, operator)
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            id: u256,
            amount: u256,
            data: Array<u8>
        ) {
            let mut unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::ERC1155Impl::safe_transfer_from(
                ref unsafe_state, from, to, id, amount, data
            )
        }

        fn safe_batch_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            ids: Array<u256>,
            amounts: Array<u256>,
            data: Array<u8>
        ) {
            let mut unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::ERC1155Impl::safe_batch_transfer_from(
                ref unsafe_state, from, to, ids, amounts, data
            )
        }
    }

    // Absorber

    #[external(v0)]
    impl AbsorberImpl of IAbsorber<ContractState> {
        fn get_start_time(self: @ContractState) -> u64 {
            let unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::get_start_time(@unsafe_state)
        }

        fn get_final_time(self: @ContractState) -> u64 {
            let unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::get_final_time(@unsafe_state)
        }

        fn get_times(self: @ContractState) -> Span<u64> {
            let unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::get_times(@unsafe_state)
        }

        fn get_absorptions(self: @ContractState) -> Span<u64> {
            let unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::get_absorptions(@unsafe_state)
        }

        fn get_absorption(self: @ContractState, time: u64) -> u64 {
            let unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::get_absorption(@unsafe_state, time)
        }

        fn get_current_absorption(self: @ContractState) -> u64 {
            let unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::get_current_absorption(@unsafe_state)
        }

        fn get_final_absorption(self: @ContractState) -> u64 {
            let unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::get_final_absorption(@unsafe_state)
        }

        fn get_project_value(self: @ContractState) -> u256 {
            let unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::get_project_value(@unsafe_state)
        }

        fn get_ton_equivalent(self: @ContractState) -> u64 {
            let unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::get_ton_equivalent(@unsafe_state)
        }

        fn is_setup(self: @ContractState) -> bool {
            let unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::is_setup(@unsafe_state)
        }

        fn set_absorptions(
            ref self: ContractState,
            times: Span<u64>,
            absorptions: Span<u64>,
            ton_equivalent: u64
        ) {
            // [Check] Only certifier
            let unsafe_state = Access::unsafe_new_contract_state();
            let certifier = Access::InternalImpl::assert_only_certifier(@unsafe_state);
            // [Effect] Set absorptions
            let mut unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::set_absorptions(
                ref unsafe_state, times, absorptions, ton_equivalent
            )
        }

        fn set_project_value(ref self: ContractState, project_value: u256) {
            // [Check] Only owner
            let unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@unsafe_state);
            // [Effect] Set project value
            let mut unsafe_state = Absorber::unsafe_new_contract_state();
            Absorber::AbsorberImpl::set_project_value(ref unsafe_state, project_value)
        }
    }

    #[external(v0)]
    impl ERC1155MetadataImpl of IERC1155Metadata<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            let unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::ERC1155MetadataImpl::name(@unsafe_state)
        }

        fn symbol(self: @ContractState) -> felt252 {
            let unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::ERC1155MetadataImpl::symbol(@unsafe_state)
        }

        fn uri(self: @ContractState, token_id: u256) -> felt252 {
            let unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::ERC1155MetadataImpl::uri(@unsafe_state, token_id)
        }
    }

    // Externals

    #[external(v0)]
    impl ExternalImpl of super::IExternal<ContractState> {

        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256, value: u256) {
            let mut unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::InternalImpl::_mint(ref unsafe_state, to, token_id, value)
        }

        fn burn(ref self: ContractState, token_id: u256, value: u256) {
            let mut unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::InternalImpl::_burn(ref unsafe_state, token_id, value)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn initializer(
            ref self: ContractState,
            name: felt252,
            symbol: felt252,
            uri: felt252,
            value_decimals: u8,
            owner: ContractAddress
        ) {
            // ERC721 & ERC3525
            let mut unsafe_state = ERC1155::unsafe_new_contract_state();
            ERC1155::InternalImpl::initializer(ref unsafe_state, name, symbol, uri);
            // Access control
            let mut unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::initializer(ref unsafe_state, owner);
            let mut unsafe_state = Access::unsafe_new_contract_state();
            Access::InternalImpl::initializer(ref unsafe_state);
        }
    }
}
