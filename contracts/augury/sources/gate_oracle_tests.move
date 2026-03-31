#[test_only]
module augury::gate_oracle_tests;

use sui::test_scenario::{Self as ts};
use augury::gate_oracle;

const ADMIN: address = @0xAD;

// === Config tests ===

#[test]
fun test_configure_gate_oracle() {
    let mut scenario = ts::begin(ADMIN);

    let market_id = object::id_from_address(@0x42);

    scenario.next_tx(ADMIN);
    gate_oracle::configure(
        market_id,
        8000, // 80% threshold
        60_000, // 1 minute permits
        scenario.ctx(),
    );

    scenario.next_tx(ADMIN);
    let config = scenario.take_shared<gate_oracle::GateOracleConfig>();
    assert!(gate_oracle::config_market_id(&config) == market_id);
    assert!(gate_oracle::config_threshold(&config) == 8000);
    assert!(gate_oracle::config_permit_duration(&config) == 60_000);
    ts::return_shared(config);

    scenario.end();
}

#[test]
fun test_update_threshold() {
    let mut scenario = ts::begin(ADMIN);

    let market_id = object::id_from_address(@0x42);

    scenario.next_tx(ADMIN);
    gate_oracle::configure(market_id, 8000, 60_000, scenario.ctx());

    scenario.next_tx(ADMIN);
    let mut config = scenario.take_shared<gate_oracle::GateOracleConfig>();
    gate_oracle::update_threshold(&mut config, 6000);
    assert!(gate_oracle::config_threshold(&config) == 6000);
    ts::return_shared(config);

    scenario.end();
}

#[test]
fun test_update_market() {
    let mut scenario = ts::begin(ADMIN);

    let market_id_1 = object::id_from_address(@0x42);
    let market_id_2 = object::id_from_address(@0x43);

    scenario.next_tx(ADMIN);
    gate_oracle::configure(market_id_1, 8000, 60_000, scenario.ctx());

    scenario.next_tx(ADMIN);
    let mut config = scenario.take_shared<gate_oracle::GateOracleConfig>();
    gate_oracle::update_market(&mut config, market_id_2);
    assert!(gate_oracle::config_market_id(&config) == market_id_2);
    ts::return_shared(config);

    scenario.end();
}

#[test]
#[expected_failure(abort_code = gate_oracle::EInvalidThreshold)]
fun test_zero_threshold_fails() {
    let mut scenario = ts::begin(ADMIN);
    let market_id = object::id_from_address(@0x42);

    scenario.next_tx(ADMIN);
    gate_oracle::configure(market_id, 0, 60_000, scenario.ctx());

    abort 0
}

#[test]
#[expected_failure(abort_code = gate_oracle::EInvalidThreshold)]
fun test_threshold_over_10000_fails() {
    let mut scenario = ts::begin(ADMIN);
    let market_id = object::id_from_address(@0x42);

    scenario.next_tx(ADMIN);
    gate_oracle::configure(market_id, 10001, 60_000, scenario.ctx());

    abort 0
}
