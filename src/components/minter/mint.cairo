#[starknet::component]
mod MintComponent {
    // Starknet imports

    use openzeppelin::token::erc20::interface::ERC20ABIDispatcherTrait;
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};

    // External imports
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};

    // Internal imports

    use carbon_v3::components::minter::interface::IMint;
    use carbon_v3::components::minter::booking::{Booking, BookingStatus, BookingTrait};
    use carbon_v3::components::vintage::interface::{IVintageDispatcher, IVintageDispatcherTrait};
    use carbon_v3::contracts::project::{
        IExternalDispatcher as IProjectDispatcher,
        IExternalDispatcherTrait as IProjectDispatcherTrait
    };
    use carbon_v3::models::carbon_vintage::{CarbonVintage, CarbonVintageType};
    use carbon_v3::contracts::project::Project::{OWNER_ROLE};

    // Constants

    use carbon_v3::models::constants::{MULTIPLIER_TONS_TO_MGRAMS};

    #[storage]
    struct Storage {
        Mint_carbonable_project_address: ContractAddress,
        Mint_payment_token_address: ContractAddress,
        Mint_public_sale_open: bool,
        Mint_min_money_amount_per_tx: u256,
        Mint_unit_price: u256,
        Mint_claimed_value: LegacyMap::<ContractAddress, u256>,
        Mint_max_mintable_cc: u256,
        Mint_remaining_mintable_cc: u256,
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
        UnitPriceUpdated: UnitPriceUpdated,
        Withdraw: Withdraw,
        AmountRetrieved: AmountRetrieved,
        MinMoneyAmountPerTxUpdated: MinMoneyAmountPerTxUpdated,
        RemainingMintableCCUpdated: RemainingMintableCCUpdated,
        MaxMintableCCUpdated: MaxMintableCCUpdated,
        RedeemInvestment: RedeemInvestment,
    }

    #[derive(Drop, starknet::Event)]
    struct PublicSaleOpen {
        old_value: bool,
        new_value: bool
    }

    #[derive(Drop, starknet::Event)]
    struct PublicSaleClose {
        old_value: bool,
        new_value: bool
    }

    #[derive(Drop, starknet::Event)]
    struct SoldOut {
        sold_out: bool
    }

    #[derive(Drop, starknet::Event)]
    struct Buy {
        #[key]
        address: ContractAddress,
        cc_amount: u256,
        vintages: Span<u256>,
    }

    #[derive(Drop, starknet::Event)]
    struct MintCanceled {
        is_canceled: bool
    }

    #[derive(Drop, starknet::Event)]
    struct UnitPriceUpdated {
        old_price: u256,
        new_price: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        recipient: ContractAddress,
        amount: u256,
    }


    #[derive(Drop, starknet::Event)]
    struct AmountRetrieved {
        token_address: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct MinMoneyAmountPerTxUpdated {
        old_amount: u256,
        new_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct MaxMintableCCUpdated {
        old_value: u256,
        new_value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RemainingMintableCCUpdated {
        old_value: u256,
        new_value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RedeemInvestment {
        address: ContractAddress,
        amount: u256,
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

        fn get_remaining_mintable_cc(self: @ComponentState<TContractState>) -> u256 {
            self.Mint_remaining_mintable_cc.read()
        }

        fn get_max_mintable_cc(self: @ComponentState<TContractState>) -> u256 {
            self.Mint_max_mintable_cc.read()
        }

        fn get_min_money_amount_per_tx(self: @ComponentState<TContractState>) -> u256 {
            self.Mint_min_money_amount_per_tx.read()
        }

        fn is_sold_out(self: @ComponentState<TContractState>) -> bool {
            self.get_remaining_mintable_cc() == 0
        }

        fn cancel_mint(ref self: ComponentState<TContractState>) {
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };

            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');
            let isOwner = project.only_owner(caller_address);
            assert(isOwner, 'Caller is not the owner');

            let is_canceled = self.Mint_cancel.read();
            assert(!is_canceled, 'Mint is already canceled');

            self.Mint_public_sale_open.write(false);
            self.Mint_cancel.write(true);

            self.emit(MintCanceled { is_canceled: true });
        }

        fn is_canceled(self: @ComponentState<TContractState>) -> bool {
            self.Mint_cancel.read()
        }

        fn set_max_mintable_cc(ref self: ComponentState<TContractState>, max_mintable_cc: u256) {
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };

            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');
            let isOwner = project.only_owner(caller_address);
            assert(isOwner, 'Caller is not the owner');

            let public_sale_open = self.Mint_public_sale_open.read();
            assert(public_sale_open, 'Sale is closed');

            let old_value_remaining = self.Mint_remaining_mintable_cc.read();
            let old_value_max = self.Mint_max_mintable_cc.read();

            let remaining_mintable_cc = old_value_remaining + max_mintable_cc - old_value_max;
            self.Mint_remaining_mintable_cc.write(remaining_mintable_cc);

            self.Mint_max_mintable_cc.write(max_mintable_cc);

            self
                .emit(
                    RemainingMintableCCUpdated {
                        old_value: old_value_remaining, new_value: remaining_mintable_cc
                    }
                );
            self
                .emit(
                    MaxMintableCCUpdated { old_value: old_value_max, new_value: max_mintable_cc }
                );
        }

        fn set_public_sale_open(ref self: ComponentState<TContractState>, public_sale_open: bool) {
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };

            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');
            let isOwner = project.only_owner(caller_address);
            assert(isOwner, 'Caller is not the owner');

            let is_canceled = self.Mint_cancel.read();
            assert(!is_canceled, 'Mint is canceled');

            let old_value = self.Mint_public_sale_open.read();
            self.Mint_public_sale_open.write(public_sale_open);

            self.emit(PublicSaleOpen { old_value: old_value, new_value: public_sale_open });
        }

        fn set_unit_price(ref self: ComponentState<TContractState>, unit_price: u256) {
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };

            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');
            let isOwner = project.only_owner(caller_address);
            assert(isOwner, 'Caller is not the owner');
            assert(unit_price > 0, 'Invalid unit price');

            let old_price = self.Mint_unit_price.read();
            self.Mint_unit_price.write(unit_price);

            self.emit(UnitPriceUpdated { old_price: old_price, new_price: unit_price });
        }

        fn withdraw(ref self: ComponentState<TContractState>) {
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };

            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');
            let isOwner = project.only_owner(caller_address);
            assert(isOwner, 'Caller is not the owner');

            let token_address = self.Mint_payment_token_address.read();
            let erc20 = IERC20Dispatcher { contract_address: token_address };
            let contract_address = get_contract_address();
            let balance = erc20.balance_of(contract_address);

            let success = erc20.transfer(caller_address, balance);
            assert(success, 'Transfer failed');

            self.emit(Withdraw { recipient: caller_address, amount: balance });
        }

        fn retrieve_amount(
            ref self: ComponentState<TContractState>,
            token_address: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };

            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');
            let isOwner = project.only_owner(caller_address);
            assert(isOwner, 'Caller is not the owner');

            let erc20 = IERC20Dispatcher { contract_address: token_address };
            let success = erc20.transfer(recipient, amount);
            assert(success, 'Transfer failed');

            self
                .emit(
                    AmountRetrieved {
                        token_address: token_address, recipient: recipient, amount: amount
                    }
                );
        }

        fn redeem_investment(ref self: ComponentState<TContractState>) {
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };
            let vintages = IVintageDispatcher { contract_address: project_address };

            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');

            let is_canceled = self.Mint_cancel.read();
            assert(is_canceled, 'Mint is not canceled');
            let is_open = self.Mint_public_sale_open.read();
            assert(!is_open, 'Sale is open');

            let mut total_cc_balance = 0;
            let num_vintages: usize = vintages.get_num_vintages();
            let mut index = 0;
            loop {
                if index >= num_vintages {
                    break;
                }
                let token_id = (index + 1).into();
                let balance = project.balance_of(caller_address, token_id);
                // Send cc of the vintage to minter to burn it
                project
                    .safe_transfer_from(
                        caller_address, get_contract_address(), token_id, balance, array![].span()
                    );
                total_cc_balance += balance;
                index += 1;
            };

            let unit_price = self.Mint_unit_price.read();
            let money_amount = total_cc_balance * unit_price / MULTIPLIER_TONS_TO_MGRAMS;

            let token_address = self.Mint_payment_token_address.read();
            let erc20 = IERC20Dispatcher { contract_address: token_address };
            let success = erc20.transfer(caller_address, money_amount);
            assert(success, 'Transfer failed');

            let initial_remaining_mintable_cc = self.Mint_remaining_mintable_cc.read();
            let remaining_mintable_cc = initial_remaining_mintable_cc + total_cc_balance;
            self.Mint_remaining_mintable_cc.write(remaining_mintable_cc);

            self
                .emit(
                    RemainingMintableCCUpdated {
                        old_value: initial_remaining_mintable_cc, new_value: remaining_mintable_cc
                    }
                );
            self.emit(RedeemInvestment { address: caller_address, amount: money_amount });
        }

        fn public_buy(ref self: ComponentState<TContractState>, cc_amount: u256) {
            let public_sale_open = self.Mint_public_sale_open.read();
            assert(public_sale_open, 'Sale is closed');

            self._buy(cc_amount);
        }

        fn set_min_money_amount_per_tx(
            ref self: ComponentState<TContractState>, min_money_amount_per_tx: u256
        ) {
            let project_address = self.Mint_carbonable_project_address.read();
            let project = IProjectDispatcher { contract_address: project_address };

            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');
            let isOwner = project.only_owner(caller_address);
            assert(isOwner, 'Caller is not the owner');

            let old_amount = self.Mint_min_money_amount_per_tx.read();
            self.Mint_min_money_amount_per_tx.write(min_money_amount_per_tx);
            self
                .emit(
                    MinMoneyAmountPerTxUpdated {
                        old_amount: old_amount, new_amount: min_money_amount_per_tx,
                    }
                );
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
            max_mintable_cc: u256,
            unit_price: u256,
        ) {
            assert(unit_price > 0, 'Invalid unit price');
            self.Mint_carbonable_project_address.write(carbonable_project_address);
            self.Mint_payment_token_address.write(payment_token_address);
            self.Mint_unit_price.write(unit_price);
            self.Mint_max_mintable_cc.write(max_mintable_cc);
            self.Mint_remaining_mintable_cc.write(max_mintable_cc);
            self.Mint_public_sale_open.write(public_sale_open);
        }

        fn _buy(ref self: ComponentState<TContractState>, cc_amount: u256) {
            assert(cc_amount > 0, 'Invalid carbon credit amount');

            let caller_address = get_caller_address();
            assert(!caller_address.is_zero(), 'Invalid caller');

            let unit_price = self.Mint_unit_price.read();
            // If user wants to buy 1 carbon credit, the input should be 1*MULTIPLIER_TONS_TO_MGRAMS
            let money_amount = cc_amount * unit_price / MULTIPLIER_TONS_TO_MGRAMS;
            // let min_money_amount_per_tx = 1;
            assert(money_amount >= 1, 'Value too low');

            let remaining_mintable_cc = self.Mint_remaining_mintable_cc.read();
            assert(remaining_mintable_cc >= cc_amount, 'Minting limit reached');

            // [Interaction] Compute the amount of cc for each vintage
            let project_address = self.Mint_carbonable_project_address.read();
            let vintages = IVintageDispatcher { contract_address: project_address };
            let num_vintages: usize = vintages.get_num_vintages();

            let mut tokens_ids: Array<u256> = Default::default();
            let mut values_cc: Array<u256> = Default::default();
            let mut index = 0;
            loop {
                if index >= num_vintages {
                    break;
                }
                values_cc.append(cc_amount.into());
                let token_id = (index + 1).into();
                tokens_ids.append(token_id);
                index += 1;
            };
            // [Interaction] Pay
            let token_address = self.Mint_payment_token_address.read();
            let erc20 = IERC20Dispatcher { contract_address: token_address };
            let minter_address = get_contract_address();

            let success = erc20.transfer_from(caller_address, minter_address, money_amount);
            // [Check] Transfer successful
            assert(success, 'Transfer failed');

            // [Interaction] Update remaining mintable cc
            self.Mint_remaining_mintable_cc.write(remaining_mintable_cc - cc_amount);

            // [Interaction] Mint
            let project = IProjectDispatcher { contract_address: project_address };
            project.batch_mint(caller_address, tokens_ids.span(), values_cc.span());

            // [Event] Emit event
            self
                .emit(
                    Event::Buy(
                        Buy {
                            address: caller_address,
                            vintages: tokens_ids.span(),
                            cc_amount: cc_amount,
                        }
                    )
                );

            self
                .emit(
                    RemainingMintableCCUpdated {
                        old_value: remaining_mintable_cc,
                        new_value: remaining_mintable_cc - cc_amount,
                    }
                );

            if self.is_sold_out() {
                self.Mint_public_sale_open.write(false);
                self
                    .emit(
                        Event::PublicSaleClose(
                            PublicSaleClose { old_value: true, new_value: false }
                        )
                    );
                self.emit(Event::SoldOut(SoldOut { sold_out: true }));
            };
        }
    }
}
