use core::fmt::{Display, Formatter, Error};

/// Struct for orders.
#[derive(Copy, Drop, Debug, starknet::Store, Serde, PartialEq, Default)]
struct CarbonVintage {
    /// The year of the vintage
    year: u32,
    /// The total supply of Carbon Credit for this vintage.
    supply: u256,
    /// The total amount of Carbon Credit that was failed during audits.
    failed: u256,
    /// The total amount of Carbon Credit that was created during audits.
    created: u256,
    /// The status of the Carbon Credit of this Vintage.
    status: CarbonVintageType,
}

impl CarbonVintageDisplay of Display<CarbonVintage> {
    fn fmt(self: @CarbonVintage, ref f: Formatter) -> Result<(), Error> {
        let str: ByteArray = format!(
            "CarbonVintage(year: {}, supply: {}, failed: {}, created: {}, status: {})",
            self.year,
            self.supply,
            self.failed,
            self.created,
            self.status
        );
        f.buffer.append(@str);
        Result::Ok(())
    }
}

#[derive(Copy, Drop, Debug, starknet::Store, Serde, PartialEq, Default)]
enum CarbonVintageType {
    #[default]
    /// Unset: the Carbon Credit is not yet created nor projected.
    Unset,
    ///  Projected: the Carbon Credit is not yet created and was projected during certification of
    ///  the project.
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

impl U8TryIntoCarbon of TryInto<u8, CarbonVintageType> {
    fn try_into(self: u8) -> Option<CarbonVintageType> {
        match self {
            0 => Option::Some(CarbonVintageType::Unset),
            1 => Option::Some(CarbonVintageType::Projected),
            2 => Option::Some(CarbonVintageType::Confirmed),
            3 => Option::Some(CarbonVintageType::Audited),
            _ => Option::None,
        }
    }
}


impl CarbonVintageTypeDisplay of Display<CarbonVintageType> {
    fn fmt(self: @CarbonVintageType, ref f: Formatter) -> Result<(), Error> {
        let str: ByteArray = match self {
            CarbonVintageType::Unset => "Unset",
            CarbonVintageType::Projected => "Projected",
            CarbonVintageType::Confirmed => "Confirmed",
            CarbonVintageType::Audited => "Audited",
        };
        f.buffer.append(@str);
        Result::Ok(())
    }
}

#[cfg(test)]
mod Test {
    use starknet::testing::set_caller_address;
    use super::{CarbonVintage, CarbonVintageType};

    // CarbonVintage tests

    #[test]
    fn test_carbon_vintage_default() {
        let carbon_vintage: CarbonVintage = Default::default();
        assert_eq!(carbon_vintage.year, 0);
        assert_eq!(carbon_vintage.supply, 0);
        assert_eq!(carbon_vintage.failed, 0);
        assert_eq!(carbon_vintage.created, 0);
        assert_eq!(carbon_vintage.status, CarbonVintageType::Unset);
    }

    #[test]
    fn test_carbon_vintage_display() {
        let carbon_vintage: CarbonVintage = Default::default();
        let res = format!("{}", carbon_vintage);
        assert_eq!(res, "CarbonVintage(year: 0, supply: 0, failed: 0, created: 0, status: Unset)");

        let carbon_vintage = CarbonVintage {
            year: 2024,
            supply: 1000000000,
            failed: 10000,
            created: 500,
            status: CarbonVintageType::Audited
        };
        let res = format!("{}", carbon_vintage);
        assert_eq!(
            res,
            "CarbonVintage(year: 2024, supply: 1000000000, failed: 10000, created: 500, status: Audited)"
        );
    }

    // CarbonVintageType tests
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

    #[test]
    fn test_carbon_vintage_type_display() {
        let carbon_vintage_type: CarbonVintageType = CarbonVintageType::Unset;
        let res = format!("{}", carbon_vintage_type);
        assert_eq!(res, "Unset");

        let carbon_vintage_type: CarbonVintageType = CarbonVintageType::Projected;
        let res = format!("{}", carbon_vintage_type);
        assert_eq!(res, "Projected");

        let carbon_vintage_type: CarbonVintageType = CarbonVintageType::Confirmed;
        let res = format!("{}", carbon_vintage_type);
        assert_eq!(res, "Confirmed");

        let carbon_vintage_type: CarbonVintageType = CarbonVintageType::Audited;
        let res = format!("{}", carbon_vintage_type);
        assert_eq!(res, "Audited");
    }
}
