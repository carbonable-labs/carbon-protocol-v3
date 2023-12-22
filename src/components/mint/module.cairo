#[starknet::contract]
mod Mint {
    // Core imports

    use zeroable::Zeroable;
    use traits::{Into, TryInto};
    use option::OptionTrait;
    use array::{Array, ArrayTrait};
    use hash::HashStateTrait;
    use poseidon::PoseidonTrait;

    // Starknet imports

    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};

    // External imports
    use openzeppelin::token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
    use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};

    // Internal imports

    use carbon_v3::components::mint::interface::IMint;
    use carbon_v3::components::mint::booking::{Booking, BookingStatus, BookingTrait};
    use carbon_v3::components::absorber::interface::{IAbsorberDispatcher, IAbsorberDispatcherTrait};
    use carbon_v3::contracts::project::{
        IExternalDispatcher as IProjectDispatcher,
        IExternalDispatcherTrait as IProjectDispatcherTrait
    };

    #[storage]
    struct Storage {
        mint_carbonable_project_address: ContractAddress,
        mint_carbonable_project_slot: u256,
        mint_payment_token_address: ContractAddress,
        mint_public_sale_open: bool,
        mint_max_value: u256,
        mint_unit_price: u256,
        mint_claimed_value: LegacyMap<ContractAddress, u256>,
        mint_remaining_value: u256,
        mint_count: LegacyMap::<ContractAddress, u32>,
        mint_booked_values: LegacyMap::<(ContractAddress, u32), Booking>,
        mint_cancel: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PublicSaleOpen: PublicSaleOpen,
        PublicSaleClose: PublicSaleClose,
        SoldOut: SoldOut,
        BookingHandled: BookingHandled,
        BookingClaimed: BookingClaimed,
        BookingRefunded: BookingRefunded,
        Cancel: Cancel,
    }

    #[derive(Drop, starknet::Event)]
    struct PublicSaleOpen {
        time: u64
    }

    #[derive(Drop, starknet::Event)]
    struct PublicSaleClose {
        time: u64
    }

    #[derive(Drop, starknet::Event)]
    struct SoldOut {
        time: u64
    }

    #[derive(Drop, starknet::Event)]
    struct BookingHandled {
        address: ContractAddress,
        id: u32,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct BookingClaimed {
        address: ContractAddress,
        id: u32,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct BookingRefunded {
        address: ContractAddress,
        id: u32,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Cancel {
        time: u64
    }

    impl MintImpl of IMint<ContractState> {
        fn get_carbonable_project_address(self: @ContractState) -> ContractAddress {
            self.mint_carbonable_project_address.read()
        }

        fn get_payment_token_address(self: @ContractState) -> ContractAddress {
            self.mint_payment_token_address.read()
        }

        fn is_public_sale_open(self: @ContractState) -> bool {
            self.mint_public_sale_open.read()
        }

        fn get_unit_price(self: @ContractState) -> u256 {
            self.mint_unit_price.read()
        }

        fn get_available_value(self: @ContractState) -> u256 {
            self.mint_remaining_value.read()
        }

        fn get_claimed_value(self: @ContractState, account: ContractAddress) -> u256 {
            self.mint_claimed_value.read(account)
        }

        fn is_sold_out(self: @ContractState) -> bool {
            self.get_available_value() == 0
        }

        fn is_canceled(self: @ContractState) -> bool {
            self.mint_cancel.read()
        }

        fn set_public_sale_open(ref self: ContractState, public_sale_open: bool) {
            // [Effect] Update storage
            self.mint_public_sale_open.write(public_sale_open);

            // [Event] Emit event
            let current_time = get_block_timestamp();
            if public_sale_open {
                self.emit(PublicSaleOpen { time: current_time });
            } else {
                self.emit(PublicSaleClose { time: current_time });
            };
        }

        fn set_unit_price(ref self: ContractState, unit_price: u256) {
            // [Check] Value not null
            assert(unit_price > 0, 'Invalid unit price');
            // [Effect] Store value
            self.mint_unit_price.write(unit_price);
        }

        fn withdraw(ref self: ContractState) {
            // [Compute] Balance to withdraw
            let token_address = self.mint_payment_token_address.read();
            let erc20 = IERC20CamelDispatcher { contract_address: token_address };
            let contract_address = get_contract_address();
            let balance = erc20.balanceOf(contract_address);

            // [Interaction] Transfer tokens
            let caller_address = get_caller_address();
            let success = erc20.transfer(caller_address, balance);
            assert(success, 'Transfer failed');
        }

        fn transfer(
            ref self: ContractState,
            token_address: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            let erc20 = IERC20CamelDispatcher { contract_address: token_address };
            let success = erc20.transfer(recipient, amount);
            assert(success, 'Transfer failed');
        }

        fn book(ref self: ContractState, value: u256, force: bool) {
            // [Check] Public sale is open
            let public_sale_open = self.mint_public_sale_open.read();
            assert(public_sale_open, 'Sale is closed');

            // [Interaction] Buy
            self._safe_book(value, force);
        }

        fn claim(ref self: ContractState, user_address: ContractAddress, id: u32) {
            // [Check] Project is sold out
            assert(self.is_sold_out(), 'Mint not sold out');

            // [Check] Project is not canceled
            assert(!self.is_canceled(), 'Mint canceled');

            // [Check] Booking
            let mut booking = self.mint_booked_values.read((user_address, id));
            assert(booking.is_status(BookingStatus::Booked), 'Booking not found');

            // [Effect] Update Booking status
            booking.set_status(BookingStatus::Minted);
            self.mint_booked_values.write((user_address.into(), id), booking);

            // [Interaction] Mint
            // TODO : define the vintage
            let projects_contract = self.mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: projects_contract };
            project.mint(user_address.into(), 1, booking.value);

            // [Event] Emit
            self.emit(BookingClaimed { address: user_address, id, value: booking.value, });
        }

        fn refund(ref self: ContractState, user_address: ContractAddress, id: u32) {
            // [Check] Booking
            let mut booking = self.mint_booked_values.read((user_address, id));
            assert(
                booking.is_status(BookingStatus::Failed) || self.is_canceled(),
                'Booking not refundable'
            );

            // [Effect] Update Booking status
            booking.set_status(BookingStatus::Refunded);
            self.mint_booked_values.write((user_address.into(), id), booking);

            // [Interaction] Refund
            let token_address = self.mint_payment_token_address.read();
            let erc20 = IERC20CamelDispatcher { contract_address: token_address };
            let contract_address = get_contract_address();
            let success = erc20.transfer(user_address, booking.value);
            assert(success, 'Transfer failed');

            // [Event] Emit
            self.emit(BookingRefunded { address: user_address, id, value: booking.value, });
        }

        fn refund_to(
            ref self: ContractState, to: ContractAddress, user_address: ContractAddress, id: u32
        ) {
            // [Check] To address connot be zero
            assert(!to.is_zero(), 'Invalid to address');

            // [Check] Booking
            let mut booking = self.mint_booked_values.read((user_address, id));
            assert(
                booking.is_status(BookingStatus::Failed) || self.is_canceled(),
                'Booking not refundable'
            );

            // [Effect] Update Booking status
            booking.set_status(BookingStatus::Refunded);
            self.mint_booked_values.write((user_address.into(), id), booking);

            // [Interaction] Refund
            let token_address = self.mint_payment_token_address.read();
            let erc20 = IERC20CamelDispatcher { contract_address: token_address };
            let contract_address = get_contract_address();
            let success = erc20.transfer(to, booking.value);
            assert(success, 'Transfer failed');

            // [Event] Emit
            self.emit(BookingRefunded { address: user_address, id, value: booking.value, });
        }

        fn cancel(ref self: ContractState) {
            // [Check] Mint is not already canceled
            assert(!self.is_canceled(), 'Mint already canceled');

            // [Effect] Update storage
            self.mint_cancel.write(true);

            // [Event] Emit
            let current_time = get_block_timestamp();
            self.emit(Cancel { time: current_time });
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn initializer(
            ref self: ContractState,
            carbonable_project_address: ContractAddress,
            payment_token_address: ContractAddress,
            public_sale_open: bool,
            max_value: u256,
            unit_price: u256,
        ) {
            // [Check] Input consistency
            assert(unit_price > 0, 'Invalid unit price');

            // [Effect] Update storage
            self.mint_carbonable_project_address.write(carbonable_project_address);

            // [Effect] Update storage
            self.mint_payment_token_address.write(payment_token_address);
            self.mint_unit_price.write(unit_price);
            self.mint_remaining_value.write(max_value);

            // [Effect] Use dedicated function to emit corresponding events
            self.set_public_sale_open(public_sale_open);
        }

        fn _safe_book(ref self: ContractState, value: u256, force: bool) -> u256 {
            // [Check] Project is not canceled
            assert(!self.is_canceled(), 'Mint canceled');

            // [Check] Value not null
            assert(value > 0, 'Invalid value');

            // [Check] Caller is not zero
            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');

            // [Compute] If available value is lower than specified value and force is enabled
            // Then replace the specified value by the remaining value otherwize keep the value unchanged
            let available_value = self._available_public_value();
            let value = if available_value < value && force {
                available_value
            } else {
                value
            };

            // [Check] Value after buy
            assert(value <= available_value, 'Not enough available value');

            // [Interaction] Pay
            let unit_price = self.mint_unit_price.read();
            let amount = value * unit_price;
            let token_address = self.mint_payment_token_address.read();
            let erc20 = IERC20CamelDispatcher { contract_address: token_address };
            let contract_address = get_contract_address();
            let success = erc20.transferFrom(caller_address, contract_address, amount);

            // [Check] Transfer successful
            assert(success, 'Transfer failed');

            // [Effect] Book
            self._book(caller_address, amount, value, BookingStatus::Booked);

            // [Return] Value
            value
        }

        fn _book(
            ref self: ContractState,
            user_address: ContractAddress,
            amount: u256,
            value: u256,
            status: BookingStatus
        ) {
            // [Effect] Compute and update user mint count
            let mint_id = self.mint_count.read(user_address) + 1_u32;
            self.mint_count.write(user_address, mint_id);

            // [Effect] Update remaining value if booked
            let mut booking = BookingTrait::new(value, amount, status);
            if booking.is_status(BookingStatus::Booked) {
                self.mint_remaining_value.write(self.mint_remaining_value.read() - value);
            };

            // [Effect] Store booking
            self.mint_booked_values.write((user_address, mint_id), booking);

            // [Event] Emit event
            self.emit(BookingHandled { address: user_address, id: mint_id, value });

            // [Effect] Close the sale if sold out
            if self.is_sold_out() {
                // [Effect] Close public sale
                self.set_public_sale_open(false);

                // [Event] Emit sold out event
                self.emit(SoldOut { time: get_block_timestamp() });
            };
        }

        fn _available_public_value(self: @ContractState) -> u256 {
            // [Compute] Available value
            let remaining_value = self.mint_remaining_value.read();
            remaining_value
        }
    }
}


#[cfg(test)]
mod Test {
    // Core imports

    use array::{ArrayTrait, SpanTrait};
    use traits::TryInto;
    use poseidon::PoseidonTrait;
    use hash::HashStateTrait;
    use debug::PrintTrait;

    // Starknet imports

    use starknet::{ContractAddress, get_contract_address, get_block_timestamp};
    use starknet::testing::{set_block_timestamp, set_caller_address, set_contract_address};

    // External imports

    use alexandria_data_structures::merkle_tree::{
        Hasher, MerkleTree, poseidon::PoseidonHasherImpl, MerkleTreeTrait,
    };

    // Internal imports

    use super::Mint;
    use super::Mint::mint_carbonable_project_address::InternalContractMemberStateTrait as MintProjectAddressTrait;
    use super::Mint::mint_remaining_value::InternalContractMemberStateTrait as MintRemainingValueTrait;
    use super::Mint::mint_payment_token_address::InternalContractMemberStateTrait as MintPaymentTokenAddressTrait;

    // Constants

    const UNIT_PRICE: u256 = 10;
    const ALLOCATION: felt252 = 5;
    const PROOF: felt252 = 0x58f605c335d6edee10b834aedf74f8ed903311799ecde69461308439a4537c7;
    const BILION: u256 = 1000000000;

    fn STATE() -> Mint::ContractState {
        Mint::contract_state_for_testing()
    }

    fn ACCOUNT() -> ContractAddress {
        starknet::contract_address_const::<1001>()
    }

    fn ZERO() -> ContractAddress {
        starknet::contract_address_const::<0>()
    }

    // Mocks

    #[starknet::contract]
    mod ProjectMock {
        use starknet::ContractAddress;

        #[storage]
        struct Storage {}

        #[generate_trait]
        #[external(v0)]
        impl MockImpl of MockTrait {
            fn get_project_value(self: @ContractState, slot: u256) -> u256 {
                super::BILION
            }
            fn total_value(self: @ContractState, slot: u256) -> u256 {
                0
            }
            fn mint(ref self: ContractState, to: ContractAddress, slot: u256, value: u256) -> u256 {
                0
            }
        }
    }

    #[starknet::contract]
    mod ERC20Mock {
        use starknet::ContractAddress;

        #[storage]
        struct Storage {}

        #[generate_trait]
        #[external(v0)]
        impl ERC20Impl of ERC20Trait {
            fn balanceOf(self: @ContractState, owner: ContractAddress) -> u256 {
                100
            }
            fn transferFrom(
                ref self: ContractState, from: ContractAddress, to: ContractAddress, value: u256
            ) -> bool {
                true
            }
            fn transfer(ref self: ContractState, to: ContractAddress, value: u256) -> bool {
                true
            }
        }
    }

    fn project_mock() -> ContractAddress {
        // [Deploy]
        let class_hash = ProjectMock::TEST_CLASS_HASH.try_into().unwrap();
        let (address, _) = starknet::deploy_syscall(class_hash, 0, array![].span(), false)
            .expect('Project deploy failed');
        address
    }

    fn erc20_mock() -> ContractAddress {
        // [Deploy]
        let class_hash = ERC20Mock::TEST_CLASS_HASH.try_into().unwrap();
        let (address, _) = starknet::deploy_syscall(class_hash, 0, array![].span(), false)
            .expect('ERC20 deploy failed');
        address
    }

    #[test]
    #[available_gas(20_000_000)]
    fn testmint_public_sale() {
        // [Setup]
        let mut state = STATE();
        Mint::MintImpl::set_public_sale_open(ref state, true);
        // [Assert] Storage
        let public_sale_open = Mint::MintImpl::is_public_sale_open(@state);
        assert(public_sale_open, 'Public sale is not open');
    }

    #[test]
    #[available_gas(20_000_000)]
    fn testmint_unit_price() {
        // [Setup]
        let mut state = STATE();
        Mint::MintImpl::set_unit_price(ref state, UNIT_PRICE);
        // [Assert] Storage
        let unit_price = Mint::MintImpl::get_unit_price(@state);
        assert(unit_price == UNIT_PRICE, 'Invalid unit price');
    }

    #[test]
    #[available_gas(20_000_000)]
    #[should_panic(expected: ('Sale is closed',))]
    fn testmint_book_revert_sale_closed() {
        // [Setup]
        let mut state = STATE();
        // [Assert] Book
        Mint::MintImpl::book(ref state, 10, false);
    }

    #[test]
    #[available_gas(20_000_000)]
    #[should_panic(expected: ('Invalid caller',))]
    fn testmint_book_revert_invalid_caller() {
        // [Setup]
        let mut state = STATE();
        Mint::MintImpl::set_public_sale_open(ref state, true);
        // [Assert] Book
        Mint::MintImpl::book(ref state, 10, false);
    }

    #[test]
    #[available_gas(20_000_000)]
    #[should_panic(expected: ('Value too high',))]
    fn testmint_book_value_too_high() {
        // [Setup]
        let mut state = STATE();
        Mint::MintImpl::set_unit_price(ref state, UNIT_PRICE);
        Mint::MintImpl::set_public_sale_open(ref state, true);
        // [Assert] Book
        set_caller_address(ACCOUNT());
        Mint::MintImpl::book(ref state, 10, false);
    }

    #[test]
    #[available_gas(20_000_000)]
    #[should_panic(expected: ('Mint canceled',))]
    fn testmint_book_revert_canceled() {
        // [Setup]
        let mut state = STATE();
        state.mint_carbonable_project_address.write(project_mock());
        state.mint_payment_token_address.write(erc20_mock());
        state.mint_remaining_value.write(1000);
        Mint::MintImpl::set_unit_price(ref state, UNIT_PRICE);
        Mint::MintImpl::set_public_sale_open(ref state, true);
        // [Assert] Cancel mint
        Mint::MintImpl::cancel(ref state);
        // [Assert] Book
        set_caller_address(ACCOUNT());
        let value: u256 = 10;
        Mint::MintImpl::book(ref state, value, false);
    }

    #[test]
    #[available_gas(20_000_000)]
    fn testmint_book() {
        // [Setup]
        let mut state = STATE();
        state.mint_carbonable_project_address.write(project_mock());
        state.mint_payment_token_address.write(erc20_mock());
        state.mint_remaining_value.write(1000);
        Mint::MintImpl::set_unit_price(ref state, UNIT_PRICE);
        Mint::MintImpl::set_public_sale_open(ref state, true);
        // [Assert] Book
        set_caller_address(ACCOUNT());
        let value: u256 = 10;
        Mint::MintImpl::book(ref state, value, false);
        // [Assert] Cancel mint
        Mint::MintImpl::cancel(ref state);
        // [Assert] Not sold out
        assert(!Mint::MintImpl::is_sold_out(@state), 'Mint sold out');
        // [Assert] Events
        let contract = get_contract_address();
        let event = starknet::testing::pop_log::<Mint::PublicSaleOpen>(contract).unwrap();
        assert(event.time == get_block_timestamp(), 'Wrong event timestamp');
        let event = starknet::testing::pop_log::<Mint::BookingHandled>(contract).unwrap();
        assert(event.address == ACCOUNT(), 'Wrong event address');
        assert(event.id == 1, 'Wrong event id');
        assert(event.value == value, 'Wrong event value');
        let event = starknet::testing::pop_log::<Mint::Cancel>(contract).unwrap();
        assert(event.time == get_block_timestamp(), 'Wrong event timestamp');
    }

    #[test]
    #[available_gas(20_000_000)]
    fn testmint_refund_canceled() {
        // [Setup]
        let mut state = STATE();
        state.mint_carbonable_project_address.write(project_mock());
        state.mint_payment_token_address.write(erc20_mock());
        state.mint_remaining_value.write(1000);
        Mint::MintImpl::set_unit_price(ref state, UNIT_PRICE);
        Mint::MintImpl::set_public_sale_open(ref state, true);
        // [Assert] Book
        set_caller_address(ACCOUNT());
        let value: u256 = 10;
        Mint::MintImpl::book(ref state, value, false);
        // [Assert] Cancel mint
        Mint::MintImpl::cancel(ref state);
        // [Assert] Not sold out
        assert(!Mint::MintImpl::is_sold_out(@state), 'Mint sold out');
        // [Assert] Refund
        Mint::MintImpl::refund(ref state, ACCOUNT(), 1);
        // [Assert] Events
        let contract = get_contract_address();
        let event = starknet::testing::pop_log::<Mint::PublicSaleOpen>(contract).unwrap();
        assert(event.time == get_block_timestamp(), 'Wrong event timestamp');
        let event = starknet::testing::pop_log::<Mint::BookingHandled>(contract).unwrap();
        assert(event.address == ACCOUNT(), 'Wrong event address');
        assert(event.id == 1, 'Wrong event id');
        assert(event.value == value, 'Wrong event value');
        let event = starknet::testing::pop_log::<Mint::Cancel>(contract).unwrap();
        assert(event.time == get_block_timestamp(), 'Wrong event timestamp');
        let event = starknet::testing::pop_log::<Mint::BookingRefunded>(contract).unwrap();
        assert(event.address == ACCOUNT(), 'Wrong event address');
        assert(event.id == 1, 'Wrong event id');
        assert(event.value == value, 'Wrong event value');
    }

    #[test]
    #[available_gas(20_000_000)]
    fn testmint_claim() {
        // [Setup]
        let mut state = STATE();
        state.mint_carbonable_project_address.write(project_mock());
        state.mint_payment_token_address.write(erc20_mock());
        state.mint_remaining_value.write(1000);
        Mint::MintImpl::set_unit_price(ref state, UNIT_PRICE);
        Mint::MintImpl::set_public_sale_open(ref state, true);
        // [Assert] Book
        set_caller_address(ACCOUNT());
        let value: u256 = 1000;
        Mint::MintImpl::book(ref state, value, true);
        // [Assert] Sold out
        assert(Mint::MintImpl::is_sold_out(@state), 'Contract not sold out');
        // [Assert] Claim
        Mint::MintImpl::claim(ref state, ACCOUNT(), 1);
        // [Assert] Events
        let contract = get_contract_address();
        let event = starknet::testing::pop_log::<Mint::PublicSaleOpen>(contract).unwrap();
        assert(event.time == get_block_timestamp(), 'Wrong event timestamp');
        let event = starknet::testing::pop_log::<Mint::BookingHandled>(contract).unwrap();
        assert(event.address == ACCOUNT(), 'Wrong event address');
        assert(event.id == 1, 'Wrong event id');
        assert(event.value == value, 'Wrong event value');
        let event = starknet::testing::pop_log::<Mint::PublicSaleClose>(contract).unwrap();
        assert(event.time == get_block_timestamp(), 'Wrong event timestamp');
        let event = starknet::testing::pop_log::<Mint::SoldOut>(contract).unwrap();
        assert(event.time == get_block_timestamp(), 'Wrong event timestamp');
        let event = starknet::testing::pop_log::<Mint::BookingClaimed>(contract).unwrap();
        assert(event.address == ACCOUNT(), 'Wrong event address');
        assert(event.id == 1, 'Wrong event id');
        assert(event.value == value, 'Wrong event value');
    }

    #[test]
    #[available_gas(20_000_000)]
    #[should_panic(expected: ('Booking not found',))]
    fn testmint_claim_twice_revert_not_found() {
        // [Setup]
        let mut state = STATE();
        state.mint_carbonable_project_address.write(project_mock());
        state.mint_payment_token_address.write(erc20_mock());
        state.mint_remaining_value.write(1000);
        Mint::MintImpl::set_unit_price(ref state, UNIT_PRICE);
        Mint::MintImpl::set_public_sale_open(ref state, true);
        // [Assert] Book
        set_caller_address(ACCOUNT());
        Mint::MintImpl::book(ref state, 1000, true);
        // [Assert] Sold out
        assert(Mint::MintImpl::is_sold_out(@state), 'Contract not sold out');
        // [Assert] Claim
        Mint::MintImpl::claim(ref state, ACCOUNT(), 1);
        Mint::MintImpl::claim(ref state, ACCOUNT(), 1);
    }

    #[test]
    #[available_gas(20_000_000)]
    #[should_panic(expected: ('Mint canceled',))]
    fn testmint_claim_revert_canceled() {
        // [Setup]
        let mut state = STATE();
        state.mint_carbonable_project_address.write(project_mock());
        state.mint_payment_token_address.write(erc20_mock());
        state.mint_remaining_value.write(1000);
        Mint::MintImpl::set_unit_price(ref state, UNIT_PRICE);
        Mint::MintImpl::set_public_sale_open(ref state, true);
        Mint::MintImpl::cancel(ref state);
        // [Assert] Book
        set_caller_address(ACCOUNT());
        Mint::MintImpl::book(ref state, 1000, true);
    }
}
