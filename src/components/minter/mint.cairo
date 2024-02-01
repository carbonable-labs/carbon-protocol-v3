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

    use carbon_v3::components::minter::interface::IMint;
    use carbon_v3::components::minter::booking::{Booking, BookingStatus, BookingTrait};
    use carbon_v3::components::absorber::interface::{IAbsorberDispatcher, IAbsorberDispatcherTrait};
    use carbon_v3::components::absorber::interface::{
        ICarbonCreditsDispatcher, ICarbonCreditsDispatcherTrait
    };
    use carbon_v3::contracts::project::{
        IExternalDispatcher as IProjectDispatcher,
        IExternalDispatcherTrait as IProjectDispatcherTrait
    };

    // Constants

    const MULT_ACCURATE_SHARE: u256 = 1_000_000;

    #[storage]
    struct Storage {
        Mint_carbonable_project_address: ContractAddress,
        Mint_carbonable_project_slot: u256,
        Mint_payment_token_address: ContractAddress,
        Mint_public_sale_open: bool,
        Mint_max_money_amount: u256,
        Mint_max_money_amount_per_tx: u256,
        Mint_min_money_amount_per_tx: u256,
        Mint_unit_price: u256,
        Mint_claimed_value: LegacyMap::<ContractAddress, u256>,
        Mint_remaining_money_amount: u256,
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
        Buy: Buy,
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
    struct Buy {
        #[key]
        address: ContractAddress,
        cc_vintage: Span<u256>,
        cc_distributed: Span<u256>,
    }

    mod Errors {
        const INVALID_ARRAY_LENGTH: felt252 = 'ERC1155: invalid array length';
    }

    #[embeddable_as(MintImpl)]
    impl Mint<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of IMint<ComponentState<TContractState>> {
        fn get_carbonable_project_address(
            self: @ComponentState<TContractState>
        ) -> ContractAddress {
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

        fn get_available_money_amount(self: @ComponentState<TContractState>) -> u256 {
            self.Mint_remaining_money_amount.read()
        }

        fn get_claimed_value(
            self: @ComponentState<TContractState>, account: ContractAddress
        ) -> u256 {
            self.Mint_claimed_value.read(account)
        }

        fn is_sold_out(self: @ComponentState<TContractState>) -> bool {
            self.get_available_money_amount() == 0
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

        fn public_buy(
            ref self: ComponentState<TContractState>, value: u256, force: bool
        ) -> Span<u256> {
            // [Check] Public sale is open
            let public_sale_open = self.Mint_public_sale_open.read();
            assert(public_sale_open, 'Sale is closed');

            // [Interaction] Buy
            self._buy(value, force)
        }

        fn set_max_money_amount_per_tx(
            ref self: ComponentState<TContractState>, max_money_amount_per_tx: u256
        ) {
            // [Check] Value in range
            let max_money_amount = self.Mint_max_money_amount.read();
            assert(max_money_amount_per_tx <= max_money_amount, 'Invalid max value per tx');
            let min_money_amount_per_tx = self.Mint_min_money_amount_per_tx.read();
            assert(max_money_amount_per_tx >= min_money_amount_per_tx, 'Invalid max value per tx');
            // [Effect] Store value
            self.Mint_max_money_amount_per_tx.write(max_money_amount_per_tx);
        }

        fn set_min_money_amount_per_tx(
            ref self: ComponentState<TContractState>, min_money_amount_per_tx: u256
        ) {
            // [Check] Value in range
            let max_money_amount_per_tx = self.Mint_max_money_amount_per_tx.read();
            assert(max_money_amount_per_tx >= min_money_amount_per_tx, 'Invalid min value per tx');
            // [Effect] Store value
            self.Mint_min_money_amount_per_tx.write(min_money_amount_per_tx);
        }

        fn get_max_money_amount(self: @ComponentState<TContractState>) -> u256 {
            self.Mint_max_money_amount.read()
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(
            ref self: ComponentState<TContractState>,
            carbonable_project_address: ContractAddress,
            payment_token_address: ContractAddress,
            public_sale_open: bool,
            max_money_amount: u256,
            unit_price: u256,
        ) {
            // [Check] Input consistency
            assert(unit_price > 0, 'Invalid unit price');

            // [Effect] Update storage
            self.Mint_carbonable_project_address.write(carbonable_project_address);

            // [Effect] Update storage
            self.Mint_payment_token_address.write(payment_token_address);
            self.Mint_unit_price.write(unit_price);
            self.Mint_remaining_money_amount.write(max_money_amount);

            // [Effect] Use dedicated function to emit corresponding events
            self.set_public_sale_open(public_sale_open);
        }

        fn _buy(
            ref self: ComponentState<TContractState>, money_amount: u256, force: bool
        ) -> Span<u256> {
            // [Check] Value not null
            assert(money_amount > 0, 'Invalid amount of money');

            // [Check] Caller is not zero
            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');

            // [Check] Allowed value
            let min_money_amount_per_tx = self.Mint_min_money_amount_per_tx.read();
            assert(money_amount >= min_money_amount_per_tx, 'Value too low');
            let max_money_amount_per_tx = self.Mint_max_money_amount_per_tx.read();
            assert(money_amount <= max_money_amount_per_tx, 'Value too high');

            // [Interaction] Comput share of the amount of project
            let max_money_amount = self.Mint_max_money_amount.read();
            let share = money_amount * MULT_ACCURATE_SHARE / max_money_amount;

            // [Interaction] Comput the amount of cc for each vintage
            let project_address = self.Mint_carbonable_project_address.read();
            let carbon_credits = ICarbonCreditsDispatcher { contract_address: project_address };
            let cc_distribution: Span<u256> = carbon_credits.compute_cc_distribution(share);
            let cc_vintage: Span<u256> = carbon_credits.get_cc_vintages();

            // [Interaction] Pay
            // TODO : verify why multiply with unit_price
            let unit_price = self.Mint_unit_price.read();
            let amount = money_amount * unit_price;
            let token_address = self.Mint_payment_token_address.read();
            let erc20 = IERC20CamelDispatcher { contract_address: token_address };
            let contract_address = get_contract_address();

            let success = erc20.transferFrom(caller_address, contract_address, amount);

            // [Check] Transfer successful
            assert(success, 'Transfer failed');

            // [Interaction] Mint
            let project = IProjectDispatcher { contract_address: project_address };
            project.batch_mint(caller_address, cc_vintage, cc_distribution);

            // [Event] Emit event
            let current_time = get_block_timestamp();
            self
                .emit(
                    Event::Buy(
                        Buy { address: caller_address, cc_vintage, cc_distributed: cc_distribution }
                    )
                );

            // [Effect] Close the sale if sold out
            if self.is_sold_out() {
                // [Effect] Close public sale
                self.set_public_sale_open(false);

                // [Event] Emit sold out event
                self.emit(Event::SoldOut(SoldOut { time: current_time }));
            };

            // [Return] cc distribution
            cc_distribution
        }

        fn _available_public_money_amount(self: @ComponentState<TContractState>) -> u256 {
            // [Compute] Available value
            let remaining_money_amount = self.Mint_remaining_money_amount.read();
            remaining_money_amount
        }
    }
}
