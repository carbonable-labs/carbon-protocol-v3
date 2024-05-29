/// Struct for orders.
#[derive(Copy, Drop, Debug, starknet::Store, Serde, PartialEq)]
struct CarbonVintage {
    /// The vintage of the Carbon Credit, which is also the token_id.
    vintage: u256,
    /// The total supply of Carbon Credit for this vintage.
    supply: u64,
    /// The total amount of Carbon Credit that failed during audits.
    failed: u64,
    /// The status of the Carbon Credit of this Vintage. 
    status: CarbonVintageType,
}

impl DefaultCarbonVintage of Default<CarbonVintage> {
    fn default() -> CarbonVintage {
        CarbonVintage {
            vintage: 0, supply: 0, failed: 0, status: CarbonVintageType::Projected,
        }
    }
}

#[derive(Copy, Drop, Debug, starknet::Store, Serde, PartialEq)]
enum CarbonVintageType {
    ///  Projected: the Carbon Credit is not yet created and was projected during certification of the project.
    Projected,
    ///  Confirmed: the Carbon Credit is confirmed by a dMRV analyse.
    Confirmed,
    ///  Audited: the Carbon Credit is audited by a third Auditor.
    Audited,
}

impl CarbonVintageTypeInto of Into<CarbonVintageType, felt252> {
    fn into(self: CarbonVintageType) -> felt252 {
        match self {
            CarbonVintageType::Projected => 0,
            CarbonVintageType::Confirmed => 1,
            CarbonVintageType::Audited => 2,
        }
    }
}
