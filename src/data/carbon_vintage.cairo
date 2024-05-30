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
        CarbonVintage { vintage: 0, supply: 0, failed: 0, status: CarbonVintageType::Unset, }
    }
}

#[derive(Copy, Drop, Debug, starknet::Store, Serde, PartialEq)]
enum CarbonVintageType {
    /// Unset: the Carbon Credit is not yet created nor projected.
    Unset,
    ///  Projected: the Carbon Credit is not yet created and was projected during certification of the project.
    Projected,
    ///  Confirmed: the Carbon Credit is confirmed by a dMRV analyse.
    Confirmed,
    ///  Audited: the Carbon Credit is audited by a third Auditor.
    Audited,
}

impl CarbonVintageTypeInto of Into<CarbonVintageType, u8> {
    fn into(self: CarbonVintageType) -> u8 {
        let mut res: u8 = 0;
        match self {
            CarbonVintageType::Unset => { res = 0 },
            CarbonVintageType::Projected => { res = 1 },
            CarbonVintageType::Confirmed => { res = 2 },
            CarbonVintageType::Audited => { res = 3 },
            // Panic if the value is not in the enum
            _ => { assert(false, 'Invalid CarbonVintageType'); },
        };
        res
    }
}

#[cfg(test)]
mod Test {
    use starknet::testing::set_caller_address;
    use super::CarbonVintageType;

    #[test]
    fn test_carbon_vintage_type_into() {
        let res: u8 = CarbonVintageType::Unset.into();
        assert_eq!(res, 0);
        let res: u8 = CarbonVintageType::Projected.into();
        assert_eq!(res, 1);
        let res: u8 = CarbonVintageType::Confirmed.into();
        assert_eq!(res, 2);
        let res: u8 = CarbonVintageType::Audited.into();
        assert_eq!(res, 3);
    }
}
