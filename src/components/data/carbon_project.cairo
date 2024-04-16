/// Struct for orders.
#[derive(Copy, Drop, Debug, starknet::Store, Serde, PartialEq)]
struct CarbonProject {
    project_name: felt252,
    project_carbon_value: u256,
    project_serial_number_metadata: felt252,
    project_serial_number_CC_block: felt252,
    project_total_retired: felt252,
}

impl DefaultCarbonProject of Default<CarbonProject> {
    fn default() -> CarbonProject {
        CarbonProject {
            project_name: 0,
            project_carbon_value: 0,
            project_serial_number_metadata: 0,
            project_serial_number_CC_block: 0,
            project_total_retired: 0,
        }
    }
}
