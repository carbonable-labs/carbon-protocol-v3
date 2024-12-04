pub mod components {
    pub mod erc1155 {
        pub mod interface;
        pub mod erc1155;
        pub mod erc1155_receiver;
    }
    pub mod metadata;
    pub mod minter {
        pub mod booking;
        pub mod interface;
        pub mod mint;
    }
    pub mod offsetter {
        pub mod interface;
        pub mod offset_handler;
    }
    pub mod resale {
        pub mod interface;
        pub mod resale_handler;
    }
    pub mod vintage {
        pub mod interface;
        pub mod vintage;
    }
}

pub mod models;
pub mod constants;

pub mod contracts {
    pub mod minter;
    pub mod offsetter;
    pub mod project;
    pub mod resale;
}

pub mod mock {
    pub mod usdcarb;
    pub mod metadata;
}

