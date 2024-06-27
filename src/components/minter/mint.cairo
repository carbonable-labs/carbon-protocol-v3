#[starknet::component]
mod MintComponent {
    // Core imports

    use zeroable::Zeroable;
    use traits::{Into, TryInto};
    use option::OptionTrait;
    use array::{Array, ArrayTrait};
    use hash::HashStateTrait;
    use poseidon::PoseidonTrait;
    use debug::PrintTrait;

    // Starknet imports

    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};

    // External imports
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};

    // Internal imports

    use carbon_v3::components::minter::interface::IMint;
    use carbon_v3::components::minter::booking::{Booking, BookingStatus, BookingTrait};
    use carbon_v3::components::absorber::interface::{IAbsorberDispatcher, IAbsorberDispatcherTrait};
    use carbon_v3::components::absorber::interface::{
        ICarbonCreditsHandlerDispatcher, ICarbonCreditsHandlerDispatcherTrait
    };
    use carbon_v3::contracts::project::{
        IExternalDispatcher as IProjectDispatcher,
        IExternalDispatcherTrait as IProjectDispatcherTrait
    };
    use carbon_v3::data::carbon_vintage::{CarbonVintage, CarbonVintageType};

    // Constants

    const CC_DECIMALS_MULTIPLIER: u256 = 100_000_000_000_000;

    #[storage]
    struct Storage {
        Mint_carbonable_project_address: ContractAddress,
        Mint_payment_token_address: ContractAddress,
        Mint_public_sale_open: bool,
        Mint_max_money_amount: u256,
        Mint_min_money_amount_per_tx: u256,
        Mint_unit_price: u256,
        Mint_claimed_value: LegacyMap::<ContractAddress, u256>,
        Mint_remaining_money_amount: u256,
        Mint_cancel: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PublicSaleOpen: PublicSaleOpen,
        PublicSaleClose: PublicSaleClose,
        SoldOut: SoldOut,
        Buy: Buy,
        MintCanceled: MintCanceled,
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
        cc_vintage_years: Span<u256>,
        cc_distributed: Span<u256>,
    }

    #[derive(Drop, starknet::Event)]
    struct MintCanceled {
        is_canceled: bool,
        time: u64
    }

    mod Errors {
        const INVALID_ARRAY_LENGTH: felt252 = 'Mint: invalid array length';
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

        fn get_min_money_amount_per_tx(self: @ComponentState<TContractState>) -> u256 {
            self.Mint_min_money_amount_per_tx.read()
        }

        fn is_sold_out(self: @ComponentState<TContractState>) -> bool {
            self.get_available_money_amount() == 0
        }

        fn cancel_mint(ref self: ComponentState<TContractState>, should_cancel: bool) {
            // [Effect] Cancel the mint
            self.Mint_cancel.write(should_cancel);

            // Get the current timestamp
            let current_time = get_block_timestamp();

            // [Event] Emit cancel event
            self.emit(MintCanceled { is_canceled: should_cancel, time: current_time });
        }

        fn is_canceled(self: @ComponentState<TContractState>) -> bool {
            self.Mint_cancel.read()
        }

        fn set_public_sale_open(ref self: ComponentState<TContractState>, public_sale_open: bool) {
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };
            // [Check] Caller is not zero
            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');
            // [Check] Caller is owner
            let isOwner = project.only_owner(caller_address);
            assert(isOwner, 'Caller is not the owner');

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
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };

            // [Check] Caller is not zero
            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');

            // [Check] Caller is owner
            let isOwner = project.only_owner(caller_address);
            assert(isOwner, 'Caller is not the owner');

            // [Check] Value not null
            assert(unit_price > 0, 'Invalid unit price');
            // [Effect] Store value
            self.Mint_unit_price.write(unit_price);
        }

        fn withdraw(ref self: ComponentState<TContractState>) {
            // [Compute] Balance to withdraw
            let token_address = self.Mint_payment_token_address.read();
            let erc20 = IERC20Dispatcher { contract_address: token_address };
            let contract_address = get_contract_address();
            let balance = erc20.balance_of(contract_address);

            // [Interaction] Transfer tokens
            let caller_address = get_caller_address();
            let success = erc20.transfer(caller_address, balance);
            assert(success, 'Transfer failed');
        }

        fn retrieve_amount(
            ref self: ComponentState<TContractState>,
            token_address: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            let erc20 = IERC20Dispatcher { contract_address: token_address };
            let success = erc20.transfer(recipient, amount);
            assert(success, 'Transfer failed');
        }

        fn public_buy(
            ref self: ComponentState<TContractState>, money_amount: u256, force: bool
        ) -> Span<u256> {
            // [Check] Public sale is open
            let public_sale_open = self.Mint_public_sale_open.read();
            assert(public_sale_open, 'Sale is closed');
            // [Interaction] Buy
            self._buy(money_amount, force)
        }

        fn set_min_money_amount_per_tx(
            ref self: ComponentState<TContractState>, min_money_amount_per_tx: u256
        ) {
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };

            // [Check] Caller is not zero
            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');

            // [Check] Caller is owner
            let isOwner = project.only_owner(caller_address);
            assert(isOwner, 'Caller is not the owner');

            // [Check] Value in range
            let max_money_amount_per_tx = self.Mint_max_money_amount.read();
            assert(
                max_money_amount_per_tx >= min_money_amount_per_tx,
                'Invalid min money amount per tx'
            );
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
            self.Mint_max_money_amount.write(max_money_amount);

            // [Effect] Use dedicated function to emit corresponding events
            self.Mint_public_sale_open.write(public_sale_open);
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

            // [Check] Allowed enough remaining_money
            let remaining_money_amount = self.Mint_remaining_money_amount.read();

            assert(money_amount <= remaining_money_amount, 'Not enough remaining money');
            // [Interaction] Compute share of the amount of project
            let max_money_amount = self.Mint_max_money_amount.read();
            let share = money_amount * CC_DECIMALS_MULTIPLIER / max_money_amount;

            // [Interaction] Compute the amount of cc for each vintage
            let project_address = self.Mint_carbonable_project_address.read();
            let carbon_credits = ICarbonCreditsHandlerDispatcher {
                contract_address: project_address
            };
            let cc_vintage_years: Span<u256> = carbon_credits.get_vintage_years();
            let n = cc_vintage_years.len();
            // Initially, share is the same for all the vintages
            let mut cc_shares: Array<u256> = ArrayTrait::<u256>::new();
            let mut index = 0;
            loop {
                if index >= n {
                    break;
                }
                cc_shares.append(share);
                index += 1;
            };
            let cc_shares = cc_shares.span();

            // [Interaction] Pay
            let token_address = self.Mint_payment_token_address.read();
            let erc20 = IERC20Dispatcher { contract_address: token_address };
            let minter_address = get_contract_address();

            let success = erc20.transfer(minter_address, money_amount);
            // [Check] Transfer successful
            assert(success, 'Transfer failed');

            // [Interaction] Update remaining money amount
            self.Mint_remaining_money_amount.write(remaining_money_amount - money_amount);

            // [Interaction] Mint
            let project = IProjectDispatcher { contract_address: project_address };
            project.batch_mint(caller_address, cc_vintage_years, cc_shares);

            // [Event] Emit event
            let current_time = get_block_timestamp();
            self
                .emit(
                    Event::Buy(
                        Buy {
                            address: caller_address,
                            cc_vintage_years: cc_vintage_years,
                            cc_distributed: cc_shares
                        }
                    )
                );

            // [Effect] Close the sale if sold out
            if self.is_sold_out() {
                // [Effect] Close public sale
                self.set_public_sale_open(false);

                // [Event] Emit sold out event
                self.emit(Event::SoldOut(SoldOut { time: current_time }));
            };

            // [Return] cc shares
            cc_shares
        }
    }
}
