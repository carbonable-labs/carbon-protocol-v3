#[starknet::component]
mod MintComponent {
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
    use openzeppelin::token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};

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
        Mint_carbonable_project_address: ContractAddress,
        Mint_carbonable_project_slot: u256,
        Mint_payment_token_address: ContractAddress,
        Mint_public_sale_open: bool,
        Mint_max_value: u256,
        Mint_unit_price: u256,
        Mint_claimed_value: LegacyMap<ContractAddress, u256>,
        Mint_remaining_value: u256,
        Mint_count: LegacyMap::<ContractAddress, u32>,
        Mint_booked_values: LegacyMap::<(ContractAddress, u32), Booking>,
        Mint_cancel: bool,
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

    #[embeddable_as(MintImpl)]
    impl Mint<
        TContractState,
        +HasComponent<TContractState>,    
        +Drop<TContractState>
    > of IMint<ComponentState<TContractState>> {
        fn get_carbonable_project_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Mint_carbonable_project_address.read()
        }

        fn get_payment_token_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.Mint_payment_token_address.read()
        }

        fn is_public_sale_open(self: @ComponentState<TContractState>) -> bool {
            self.Mint_public_sale_open.read()
        }

        fn get_unit_price(self: @ComponentState<TContractState>) -> u256 {
            self.Mint_unit_price.read()
        }

        fn get_available_value(self: @ComponentState<TContractState>) -> u256 {
            self.Mint_remaining_value.read()
        }

        fn get_claimed_value(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            self.Mint_claimed_value.read(account)
        }

        fn is_sold_out(self: @ComponentState<TContractState>) -> bool {
            self.get_available_value() == 0
        }

        fn is_canceled(self: @ComponentState<TContractState>) -> bool {
            self.Mint_cancel.read()
        }

        fn set_public_sale_open(ref self: ComponentState<TContractState>, public_sale_open: bool) {
            // [Effect] Update storage
            self.Mint_public_sale_open.write(public_sale_open);

            // [Event] Emit event
            let current_time = get_block_timestamp();
            if public_sale_open {
                self.emit(PublicSaleOpen { time: current_time });
            } else {
                self.emit(PublicSaleClose { time: current_time });
            };
        }

        fn set_unit_price(ref self: ComponentState<TContractState>, unit_price: u256) {
            // [Check] Value not null
            assert(unit_price > 0, 'Invalid unit price');
            // [Effect] Store value
            self.Mint_unit_price.write(unit_price);
        }

        fn withdraw(ref self: ComponentState<TContractState>) {
            // [Compute] Balance to withdraw
            let token_address = self.Mint_payment_token_address.read();
            let erc20 = IERC20CamelDispatcher { contract_address: token_address };
            let contract_address = get_contract_address();
            let balance = erc20.balanceOf(contract_address);

            // [Interaction] Transfer tokens
            let caller_address = get_caller_address();
            let success = erc20.transfer(caller_address, balance);
            assert(success, 'Transfer failed');
        }

        fn transfer(
            ref self: ComponentState<TContractState>,
            token_address: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            let erc20 = IERC20CamelDispatcher { contract_address: token_address };
            let success = erc20.transfer(recipient, amount);
            assert(success, 'Transfer failed');
        }

        fn book(ref self: ComponentState<TContractState>, value: u256, force: bool) {
            // [Check] Public sale is open
            let public_sale_open = self.Mint_public_sale_open.read();
            assert(public_sale_open, 'Sale is closed');

            // [Interaction] Buy
            self._safe_book(value, force);
        }

        fn claim(ref self: ComponentState<TContractState>, user_address: ContractAddress, id: u32) {
            // [Check] Project is sold out
            assert(self.is_sold_out(), 'Mint not sold out');

            // [Check] Project is not canceled
            assert(!self.is_canceled(), 'Mint canceled');

            // [Check] Booking
            let mut booking = self.Mint_booked_values.read((user_address, id));
            assert(booking.is_status(BookingStatus::Booked), 'Booking not found');

            // [Effect] Update Booking status
            booking.set_status(BookingStatus::Minted);
            self.Mint_booked_values.write((user_address.into(), id), booking);

            // [Interaction] Mint
            // TODO : define the vintage
            let projects_contract = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: projects_contract };
            project.mint_specific_cc(user_address.into(), 1, booking.value);

            // [Event] Emit
            self.emit(BookingClaimed { address: user_address, id, value: booking.value, });
        }

        fn refund(ref self: ComponentState<TContractState>, user_address: ContractAddress, id: u32) {
            // [Check] Booking
            let mut booking = self.Mint_booked_values.read((user_address, id));
            assert(
                booking.is_status(BookingStatus::Failed) || self.is_canceled(),
                'Booking not refundable'
            );

            // [Effect] Update Booking status
            booking.set_status(BookingStatus::Refunded);
            self.Mint_booked_values.write((user_address.into(), id), booking);

            // [Interaction] Refund
            let token_address = self.Mint_payment_token_address.read();
            let erc20 = IERC20CamelDispatcher { contract_address: token_address };
            let contract_address = get_contract_address();
            let success = erc20.transfer(user_address, booking.value);
            assert(success, 'Transfer failed');

            // [Event] Emit
            self.emit(BookingRefunded { address: user_address, id, value: booking.value, });
        }

        fn refund_to(
            ref self: ComponentState<TContractState>, to: ContractAddress, user_address: ContractAddress, id: u32
        ) {
            // [Check] To address connot be zero
            assert(!to.is_zero(), 'Invalid to address');

            // [Check] Booking
            let mut booking = self.Mint_booked_values.read((user_address, id));
            assert(
                booking.is_status(BookingStatus::Failed) || self.is_canceled(),
                'Booking not refundable'
            );

            // [Effect] Update Booking status
            booking.set_status(BookingStatus::Refunded);
            self.Mint_booked_values.write((user_address.into(), id), booking);

            // [Interaction] Refund
            let token_address = self.Mint_payment_token_address.read();
            let erc20 = IERC20CamelDispatcher { contract_address: token_address };
            let contract_address = get_contract_address();
            let success = erc20.transfer(to, booking.value);
            assert(success, 'Transfer failed');

            // [Event] Emit
            self.emit(BookingRefunded { address: user_address, id, value: booking.value, });
        }

        fn cancel(ref self: ComponentState<TContractState>) {
            // [Check] Mint is not already canceled
            assert(!self.is_canceled(), 'Mint already canceled');

            // [Effect] Update storage
            self.Mint_cancel.write(true);

            // [Event] Emit
            let current_time = get_block_timestamp();
            self.emit(Cancel { time: current_time });
        }
    }

    #[generate_trait]
    impl InternalImpl<
         TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>       
    > of InternalTrait<TContractState> {
        fn initializer(
            ref self: ComponentState<TContractState>,
            carbonable_project_address: ContractAddress,
            payment_token_address: ContractAddress,
            public_sale_open: bool,
            max_value: u256,
            unit_price: u256,
        ) {
            // [Check] Input consistency
            assert(unit_price > 0, 'Invalid unit price');

            // [Effect] Update storage
            self.Mint_carbonable_project_address.write(carbonable_project_address);

            // [Effect] Update storage
            self.Mint_payment_token_address.write(payment_token_address);
            self.Mint_unit_price.write(unit_price);
            self.Mint_remaining_value.write(max_value);

            // [Effect] Use dedicated function to emit corresponding events
            self.set_public_sale_open(public_sale_open);
        }

        fn _safe_book(ref self: ComponentState<TContractState>, value: u256, force: bool) -> u256 {
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
            let unit_price = self.Mint_unit_price.read();
            let amount = value * unit_price;
            let token_address = self.Mint_payment_token_address.read();
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
            ref self: ComponentState<TContractState>,
            user_address: ContractAddress,
            amount: u256,
            value: u256,
            status: BookingStatus
        ) {
            // [Effect] Compute and update user mint count
            let Mint_id = self.Mint_count.read(user_address) + 1_u32;
            self.Mint_count.write(user_address, Mint_id);

            // [Effect] Update remaining value if booked
            let mut booking = BookingTrait::new(value, amount, status);
            if booking.is_status(BookingStatus::Booked) {
                self.Mint_remaining_value.write(self.Mint_remaining_value.read() - value);
            };

            // [Effect] Store booking
            self.Mint_booked_values.write((user_address, Mint_id), booking);

            // [Event] Emit event
            self.emit(BookingHandled { address: user_address, id: Mint_id, value });

            // [Effect] Close the sale if sold out
            if self.is_sold_out() {
                // [Effect] Close public sale
                self.set_public_sale_open(false);

                // [Event] Emit sold out event
                self.emit(SoldOut { time: get_block_timestamp() });
            };
        }

        fn _available_public_value(self: @ComponentState<TContractState>) -> u256 {
            // [Compute] Available value
            let remaining_value = self.Mint_remaining_value.read();
            remaining_value
        }
    }
}

