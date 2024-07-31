// Carbon Credits amount, equals to tons of CO2 equivalent, is here expressed in grams of CO2 equivalent, with 2 decimals after the comma.
// Example: If Bob wants to buy 1.5 carbon credits, the input should be 1.5*CC_DECIMALS_MULTIPLIER = 150000000000000.

const CC_DECIMALS_MULTIPLIER: u256 = 1_000_000_000_000_000_000;
const MULTIPLIER_TONS_TO_MGRAMS: u256 = 1_000_000_000;
const CC_DECIMALS: u8 = 8;
