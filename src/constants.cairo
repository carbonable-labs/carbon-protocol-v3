// Carbon Credits amount, equals to tons of CO2 equivalent, is here expressed in grams of CO2
// equivalent, with 2 decimals after the comma.
// Example: If Bob wants to buy 1.5 carbon credits, the input should be 1.5*CC_DECIMALS_MULTIPLIER =
// 150000000000000.

pub const CC_DECIMALS_MULTIPLIER: u256 = 1_000_000_000_000_000_000;
pub const MULTIPLIER_TONS_TO_MGRAMS: u256 = 1_000_000_000;
pub const CC_DECIMALS: u8 = 8;

pub const IERC165_BACKWARD_COMPATIBLE_ID: felt252 = 0x80ac58cd;
pub const OLD_IERC1155_ID: felt252 = 0xd9b67a26;
pub const MINTER_ROLE: felt252 = selector!("Minter");
pub const OFFSETTER_ROLE: felt252 = selector!("Offsetter");
pub const OWNER_ROLE: felt252 = selector!("Owner");
