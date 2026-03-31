#[test_only]
module augury::resolver_registry_tests;

use sui::test_scenario::{Self as ts};
use sui::clock;
use augury::augury::{Self, AdminCap, MarketRegistry, Market};
use augury::resolver_registry::{Self, ResolverRegistry};

const ADMIN: address = @0xAD;
const RESOLVER_A: address = @0xA1;
const RESOLVER_B: address = @0xA2;
const RESOLVER_C: address = @0xA3;
const BETTOR: address = @0xBE;
const DEADLINE: u64 = 7_200_000;

fun setup(): ts::Scenario {
    let mut scenario = ts::begin(ADMIN);
    augury::init_for_testing(scenario.ctx());
    scenario
}

fun create_test_market(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    scenario.next_tx(ADMIN);
    let mut registry = scenario.take_shared<MarketRegistry>();
    augury::create_market(
        &mut registry,
        b"Test market for resolver",
        augury::event_killmail(),
        42, 10, DEADLINE, clock, scenario.ctx(),
    );
    ts::return_shared(registry);
}

// === Registration tests ===

#[test]
fun test_register_and_check_resolvers() {
    let mut scenario = setup();

    // Create registry with quorum=2
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    resolver_registry::create_registry(&admin_cap, 2, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    // Register 3 resolvers
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut registry = scenario.take_shared<ResolverRegistry>();
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_A);
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_B);
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_C);

    assert!(resolver_registry::resolver_count(&registry) == 3);
    assert!(resolver_registry::is_resolver(&registry, RESOLVER_A));
    assert!(resolver_registry::is_resolver(&registry, RESOLVER_B));
    assert!(resolver_registry::quorum(&registry) == 2);

    ts::return_shared(registry);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

#[test]
fun test_remove_resolver() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    resolver_registry::create_registry(&admin_cap, 1, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut registry = scenario.take_shared<ResolverRegistry>();
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_A);
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_B);
    assert!(resolver_registry::resolver_count(&registry) == 2);

    resolver_registry::remove_resolver(&admin_cap, &mut registry, RESOLVER_A);
    assert!(resolver_registry::resolver_count(&registry) == 1);
    assert!(!resolver_registry::is_resolver(&registry, RESOLVER_A));

    ts::return_shared(registry);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = resolver_registry::EAlreadyRegistered)]
fun test_double_register_fails() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    resolver_registry::create_registry(&admin_cap, 1, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut registry = scenario.take_shared<ResolverRegistry>();
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_A);
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_A);

    abort 0
}

// === Consensus tests ===

#[test]
fun test_consensus_resolves_market() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_test_market(&mut scenario, &clock);

    // Setup registry: quorum = 2
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    resolver_registry::create_registry(&admin_cap, 2, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut registry = scenario.take_shared<ResolverRegistry>();
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_A);
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_B);
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_C);
    ts::return_shared(registry);
    scenario.return_to_sender(admin_cap);

    // Advance past deadline
    clock.set_for_testing(DEADLINE);

    // Resolver A submits: 15 events
    scenario.next_tx(RESOLVER_A);
    let mut registry = scenario.take_shared<ResolverRegistry>();
    let mut market = scenario.take_shared<Market>();
    resolver_registry::submit_observation(
        &mut registry, &mut market, 15, &clock, scenario.ctx(),
    );
    // Market still open (only 1 submission, quorum=2)
    assert!(augury::market_status(&market) == 0);
    ts::return_shared(market);
    ts::return_shared(registry);

    // Resolver B submits same value: 15 events -> quorum reached!
    scenario.next_tx(RESOLVER_B);
    let mut registry = scenario.take_shared<ResolverRegistry>();
    let mut market = scenario.take_shared<Market>();
    resolver_registry::submit_observation(
        &mut registry, &mut market, 15, &clock, scenario.ctx(),
    );
    // Market should now be resolved as YES (15 >= 10)
    assert!(augury::market_status(&market) == 1);
    assert!(augury::market_resolved_count(&market) == 15);
    ts::return_shared(market);
    ts::return_shared(registry);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_no_consensus_without_quorum() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_test_market(&mut scenario, &clock);

    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    resolver_registry::create_registry(&admin_cap, 3, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut registry = scenario.take_shared<ResolverRegistry>();
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_A);
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_B);
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_C);
    ts::return_shared(registry);
    scenario.return_to_sender(admin_cap);

    clock.set_for_testing(DEADLINE);

    // All 3 submit different values — no quorum on any single value
    scenario.next_tx(RESOLVER_A);
    let mut registry = scenario.take_shared<ResolverRegistry>();
    let mut market = scenario.take_shared<Market>();
    resolver_registry::submit_observation(&mut registry, &mut market, 10, &clock, scenario.ctx());
    assert!(augury::market_status(&market) == 0);
    ts::return_shared(market);
    ts::return_shared(registry);

    scenario.next_tx(RESOLVER_B);
    let mut registry = scenario.take_shared<ResolverRegistry>();
    let mut market = scenario.take_shared<Market>();
    resolver_registry::submit_observation(&mut registry, &mut market, 20, &clock, scenario.ctx());
    assert!(augury::market_status(&market) == 0);
    ts::return_shared(market);
    ts::return_shared(registry);

    scenario.next_tx(RESOLVER_C);
    let mut registry = scenario.take_shared<ResolverRegistry>();
    let mut market = scenario.take_shared<Market>();
    resolver_registry::submit_observation(&mut registry, &mut market, 30, &clock, scenario.ctx());
    // Still open — no 3 resolvers agree
    assert!(augury::market_status(&market) == 0);
    ts::return_shared(market);
    ts::return_shared(registry);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = resolver_registry::ENotRegistered)]
fun test_unregistered_resolver_fails() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_test_market(&mut scenario, &clock);

    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    resolver_registry::create_registry(&admin_cap, 1, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    clock.set_for_testing(DEADLINE);

    // Non-registered address tries to submit
    scenario.next_tx(BETTOR);
    let mut registry = scenario.take_shared<ResolverRegistry>();
    let mut market = scenario.take_shared<Market>();
    resolver_registry::submit_observation(&mut registry, &mut market, 5, &clock, scenario.ctx());

    abort 0
}

#[test]
#[expected_failure(abort_code = resolver_registry::EAlreadySubmitted)]
fun test_double_submission_fails() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_test_market(&mut scenario, &clock);

    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    resolver_registry::create_registry(&admin_cap, 2, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut registry = scenario.take_shared<ResolverRegistry>();
    resolver_registry::register_resolver(&admin_cap, &mut registry, RESOLVER_A);
    ts::return_shared(registry);
    scenario.return_to_sender(admin_cap);

    clock.set_for_testing(DEADLINE);

    // Resolver A submits twice
    scenario.next_tx(RESOLVER_A);
    let mut registry = scenario.take_shared<ResolverRegistry>();
    let mut market = scenario.take_shared<Market>();
    resolver_registry::submit_observation(&mut registry, &mut market, 5, &clock, scenario.ctx());
    resolver_registry::submit_observation(&mut registry, &mut market, 5, &clock, scenario.ctx());

    abort 0
}
