mod components {
    mod erc1155;
    mod metadata;
    mod minter;
    mod offsetter;
    mod resale {
        mod interface;
        mod resale_handler;
    }
    mod vintage;
}

mod models {
    mod carbon_vintage;
    mod constants;
}

mod contracts {
    mod minter;
    mod offsetter;
    mod project;
    mod resale;
}

mod mock {
    mod usdcarb;
    mod metadata;
}

