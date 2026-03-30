#[test_only]
module augury::augury_tests;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use augury::augury::{Self, AdminCap, Treasury, MarketRegistry, Market, Position};

const ADMIN: address = @0xAD;
const ALICE: address = @0xA1;
const BOB: address = @0xB0;
const CAROL: address = @0xCA;

// Deadline 2 hours from time=0
const DEADLINE: u64 = 7_200_000;

// === Helpers ===

fun setup(): ts::Scenario {
    let mut scenario = ts::begin(ADMIN);
    augury::init_for_testing(scenario.ctx());
    scenario
}

fun create_default_market(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    scenario.next_tx(ADMIN);
    let mut registry = scenario.take_shared<MarketRegistry>();
    augury::create_market(
        &mut registry,
        b"Will kills in System X exceed 20?",
        augury::event_killmail(),
        42, // target system
        20, // threshold
        DEADLINE,
        clock,
        scenario.ctx(),
    );
    ts::return_shared(registry);
}

fun place(scenario: &mut ts::Scenario, player: address, side: u8, amount: u64, clock: &clock::Clock) {
    scenario.next_tx(player);
    let mut market = scenario.take_shared<Market>();
    let payment = coin::mint_for_testing<SUI>(amount, scenario.ctx());
    augury::place_bet(&mut market, side, payment, clock, scenario.ctx());
    ts::return_shared(market);
}

// === P0: claim() owner verification ===

#[test]
fun test_claim_by_owner_succeeds() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    place(&mut scenario, ALICE, augury::side_yes(), 1_000_000, &clock);
    place(&mut scenario, BOB, augury::side_no(), 1_000_000, &clock);

    // Resolve YES
    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 25, &clock); // 25 >= 20 → YES
    ts::return_shared(market);
    scenario.return_to_sender(admin_cap);

    // Alice claims her winning position
    scenario.next_tx(ALICE);
    let mut market = scenario.take_shared<Market>();
    let mut treasury = scenario.take_shared<Treasury>();
    let mut position = scenario.take_from_sender<Position>();
    augury::claim(&mut market, &mut treasury, &mut position, scenario.ctx());
    assert!(augury::position_claimed(&position));
    scenario.return_to_sender(position);
    ts::return_shared(market);
    ts::return_shared(treasury);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = augury::EUnauthorized)]
fun test_claim_by_non_owner_fails() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    place(&mut scenario, ALICE, augury::side_yes(), 1_000_000, &clock);
    place(&mut scenario, BOB, augury::side_no(), 1_000_000, &clock);

    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 25, &clock);
    ts::return_shared(market);
    scenario.return_to_sender(admin_cap);

    // Bob tries to claim Alice's winning position → should fail
    scenario.next_tx(ALICE);
    let position = scenario.take_from_sender<Position>();
    // Transfer to Bob so he can attempt claim
    transfer::public_transfer(position, BOB);

    scenario.next_tx(BOB);
    let mut market = scenario.take_shared<Market>();
    let mut treasury = scenario.take_shared<Treasury>();
    let mut position = scenario.take_from_sender<Position>();
    // Bob is sender but position.owner is ALICE → EUnauthorized
    augury::claim(&mut market, &mut treasury, &mut position, scenario.ctx());

    abort 0 // unreachable
}

// === P0: Division by zero ===

#[test]
#[expected_failure(abort_code = augury::ENotWinner)]
fun test_all_bets_on_losing_side() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    // Only YES bets, but outcome is NO
    place(&mut scenario, ALICE, augury::side_yes(), 1_000_000, &clock);

    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 5, &clock); // 5 < 20 → NO
    ts::return_shared(market);
    scenario.return_to_sender(admin_cap);

    // Alice bet YES but outcome is NO → ENotWinner
    scenario.next_tx(ALICE);
    let mut market = scenario.take_shared<Market>();
    let mut treasury = scenario.take_shared<Treasury>();
    let mut position = scenario.take_from_sender<Position>();
    augury::claim(&mut market, &mut treasury, &mut position, scenario.ctx());

    abort 0
}

#[test]
#[expected_failure(abort_code = augury::ENotWinner)]
fun test_no_winning_pool_division_by_zero() {
    // Market resolved YES but only NO bets exist.
    // ENotWinner fires before the div-by-zero guard (defense-in-depth).
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    place(&mut scenario, BOB, augury::side_no(), 1_000_000, &clock);

    // Resolve YES even though only NO bets exist
    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 25, &clock);
    ts::return_shared(market);
    scenario.return_to_sender(admin_cap);

    // Bob bet NO but outcome is YES → ENotWinner
    scenario.next_tx(BOB);
    let mut market = scenario.take_shared<Market>();
    let mut treasury = scenario.take_shared<Treasury>();
    let mut position = scenario.take_from_sender<Position>();
    augury::claim(&mut market, &mut treasury, &mut position, scenario.ctx());

    abort 0
}

// === Market creation ===

#[test]
fun test_create_market_success() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);

    scenario.next_tx(ADMIN);
    let registry = scenario.take_shared<MarketRegistry>();
    assert!(augury::registry_market_count(&registry) == 1);
    ts::return_shared(registry);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = augury::EInvalidDeadline)]
fun test_create_market_deadline_too_soon() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    scenario.next_tx(ADMIN);
    let mut registry = scenario.take_shared<MarketRegistry>();
    augury::create_market(
        &mut registry,
        b"Too soon",
        augury::event_killmail(),
        1, 10,
        1_000, // only 1 second, less than 1 hour minimum
        &clock,
        scenario.ctx(),
    );

    abort 0
}

#[test]
#[expected_failure(abort_code = augury::EInvalidEventType)]
fun test_create_market_invalid_event_type() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    scenario.next_tx(ADMIN);
    let mut registry = scenario.take_shared<MarketRegistry>();
    augury::create_market(
        &mut registry,
        b"Bad type",
        99, // invalid
        1, 10, DEADLINE,
        &clock,
        scenario.ctx(),
    );

    abort 0
}

#[test]
#[expected_failure(abort_code = augury::EInvalidThreshold)]
fun test_create_market_zero_threshold() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    scenario.next_tx(ADMIN);
    let mut registry = scenario.take_shared<MarketRegistry>();
    augury::create_market(
        &mut registry,
        b"Zero threshold",
        augury::event_killmail(),
        1, 0, DEADLINE,
        &clock,
        scenario.ctx(),
    );

    abort 0
}

#[test]
#[expected_failure(abort_code = augury::EQuestionTooLong)]
fun test_create_market_question_too_long() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    // Create a 300-byte question
    let mut question = vector[];
    let mut i = 0;
    while (i < 300) {
        question.push_back(0x78); // 'x'
        i = i + 1;
    };

    scenario.next_tx(ADMIN);
    let mut registry = scenario.take_shared<MarketRegistry>();
    augury::create_market(
        &mut registry,
        question,
        augury::event_killmail(),
        1, 10, DEADLINE,
        &clock,
        scenario.ctx(),
    );

    abort 0
}

// === Betting ===

#[test]
fun test_place_bet_yes_and_no() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    place(&mut scenario, ALICE, augury::side_yes(), 500_000, &clock);
    place(&mut scenario, BOB, augury::side_no(), 300_000, &clock);

    scenario.next_tx(ADMIN);
    let market = scenario.take_shared<Market>();
    assert!(augury::market_yes_pool(&market) == 500_000);
    assert!(augury::market_no_pool(&market) == 300_000);
    assert!(augury::market_yes_count(&market) == 1);
    assert!(augury::market_no_count(&market) == 1);
    ts::return_shared(market);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = augury::EDeadlineReached)]
fun test_bet_after_deadline_fails() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);

    clock.set_for_testing(DEADLINE);
    place(&mut scenario, ALICE, augury::side_yes(), 100_000, &clock);

    abort 0
}

#[test]
#[expected_failure(abort_code = augury::EInvalidSide)]
fun test_bet_invalid_side_fails() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    place(&mut scenario, ALICE, 99, 100_000, &clock); // side=99 invalid

    abort 0
}

#[test]
#[expected_failure(abort_code = augury::EZeroBet)]
fun test_zero_bet_fails() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    place(&mut scenario, ALICE, augury::side_yes(), 0, &clock);

    abort 0
}

// === Resolution ===

#[test]
fun test_resolve_yes() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);

    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 25, &clock);
    assert!(augury::market_status(&market) == 1); // STATUS_RESOLVED_YES
    assert!(augury::market_resolved_count(&market) == 25);
    ts::return_shared(market);
    scenario.return_to_sender(admin_cap);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_resolve_no() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);

    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 10, &clock); // 10 < 20 → NO
    assert!(augury::market_status(&market) == 2); // STATUS_RESOLVED_NO
    assert!(augury::market_resolved_count(&market) == 10);
    ts::return_shared(market);
    scenario.return_to_sender(admin_cap);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_resolve_at_exact_threshold() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);

    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 20, &clock); // 20 >= 20 → YES
    assert!(augury::market_status(&market) == 1);
    ts::return_shared(market);
    scenario.return_to_sender(admin_cap);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = augury::EDeadlineNotReached)]
fun test_resolve_before_deadline_fails() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);

    // Try to resolve before deadline
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 25, &clock);

    abort 0
}

#[test]
#[expected_failure(abort_code = augury::EMarketAlreadyResolved)]
fun test_double_resolve_fails() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);

    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 25, &clock);
    augury::resolve(&admin_cap, &mut market, 30, &clock); // double resolve

    abort 0
}

// === Claim / Payout math ===

#[test]
fun test_payout_proportional_split() {
    // Alice bets 1 SUI YES, Bob bets 1 SUI NO → YES wins
    // Total pool = 2 SUI, winning pool = 1 SUI
    // Alice gross = 1/1 * 2 = 2 SUI, fee = 2% of 2 = 0.04, net = 1.96
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    place(&mut scenario, ALICE, augury::side_yes(), 1_000_000_000, &clock);
    place(&mut scenario, BOB, augury::side_no(), 1_000_000_000, &clock);

    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 25, &clock);
    ts::return_shared(market);
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(ALICE);
    let mut market = scenario.take_shared<Market>();
    let mut treasury = scenario.take_shared<Treasury>();
    let mut position = scenario.take_from_sender<Position>();
    augury::claim(&mut market, &mut treasury, &mut position, scenario.ctx());

    // Verify fee collected
    assert!(augury::treasury_balance(&treasury) == 40_000_000); // 2% of 2 SUI
    scenario.return_to_sender(position);
    ts::return_shared(market);
    ts::return_shared(treasury);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_payout_multiple_winners() {
    // Alice bets 3 SUI YES, Carol bets 1 SUI YES, Bob bets 4 SUI NO → YES wins
    // Total = 8, winning = 4
    // Alice gross = 3/4 * 8 = 6, Carol gross = 1/4 * 8 = 2
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    let one_sui = 1_000_000_000;
    place(&mut scenario, ALICE, augury::side_yes(), 3 * one_sui, &clock);
    place(&mut scenario, CAROL, augury::side_yes(), 1 * one_sui, &clock);
    place(&mut scenario, BOB, augury::side_no(), 4 * one_sui, &clock);

    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 25, &clock);
    ts::return_shared(market);
    scenario.return_to_sender(admin_cap);

    // Alice claims
    scenario.next_tx(ALICE);
    let mut market = scenario.take_shared<Market>();
    let mut treasury = scenario.take_shared<Treasury>();
    let mut position = scenario.take_from_sender<Position>();
    augury::claim(&mut market, &mut treasury, &mut position, scenario.ctx());
    assert!(augury::position_claimed(&position));
    scenario.return_to_sender(position);
    ts::return_shared(market);
    ts::return_shared(treasury);

    // Carol claims
    scenario.next_tx(CAROL);
    let mut market = scenario.take_shared<Market>();
    let mut treasury = scenario.take_shared<Treasury>();
    let mut position = scenario.take_from_sender<Position>();
    augury::claim(&mut market, &mut treasury, &mut position, scenario.ctx());
    assert!(augury::position_claimed(&position));
    scenario.return_to_sender(position);
    ts::return_shared(market);
    ts::return_shared(treasury);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = augury::EAlreadyClaimed)]
fun test_double_claim_fails() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    place(&mut scenario, ALICE, augury::side_yes(), 1_000_000, &clock);
    place(&mut scenario, BOB, augury::side_no(), 1_000_000, &clock);

    clock.set_for_testing(DEADLINE);
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut market = scenario.take_shared<Market>();
    augury::resolve(&admin_cap, &mut market, 25, &clock);
    ts::return_shared(market);
    scenario.return_to_sender(admin_cap);

    // Alice claims once
    scenario.next_tx(ALICE);
    let mut market = scenario.take_shared<Market>();
    let mut treasury = scenario.take_shared<Treasury>();
    let mut position = scenario.take_from_sender<Position>();
    augury::claim(&mut market, &mut treasury, &mut position, scenario.ctx());
    // Try to claim again
    augury::claim(&mut market, &mut treasury, &mut position, scenario.ctx());

    abort 0
}

#[test]
#[expected_failure(abort_code = augury::EMarketNotResolved)]
fun test_claim_before_resolve_fails() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    place(&mut scenario, ALICE, augury::side_yes(), 1_000_000, &clock);

    scenario.next_tx(ALICE);
    let mut market = scenario.take_shared<Market>();
    let mut treasury = scenario.take_shared<Treasury>();
    let mut position = scenario.take_from_sender<Position>();
    augury::claim(&mut market, &mut treasury, &mut position, scenario.ctx());

    abort 0
}

// === Table indexing ===

#[test]
fun test_registry_table_indexing() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    // Create 3 markets
    create_default_market(&mut scenario, &clock);

    scenario.next_tx(ADMIN);
    let mut registry = scenario.take_shared<MarketRegistry>();
    augury::create_market(
        &mut registry,
        b"Jump market",
        augury::event_jump(),
        100, 50, DEADLINE,
        &clock,
        scenario.ctx(),
    );
    augury::create_market(
        &mut registry,
        b"Destroy market",
        augury::event_item_destroy(),
        0, 10, DEADLINE,
        &clock,
        scenario.ctx(),
    );

    assert!(augury::registry_market_count(&registry) == 3);
    // Verify we can look up each market by index
    let _id0 = augury::registry_market_at(&registry, 0);
    let _id1 = augury::registry_market_at(&registry, 1);
    let _id2 = augury::registry_market_at(&registry, 2);
    ts::return_shared(registry);

    clock.destroy_for_testing();
    scenario.end();
}

// === EVE event type constants ===

#[test]
fun test_eve_event_type_constants() {
    assert!(augury::event_killmail() == 1);
    assert!(augury::event_jump() == 2);
    assert!(augury::event_item_destroy() == 3);
}

#[test]
fun test_all_three_event_types_create() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    scenario.next_tx(ADMIN);
    let mut registry = scenario.take_shared<MarketRegistry>();

    augury::create_market(
        &mut registry, b"Killmail market",
        augury::event_killmail(), 42, 20, DEADLINE, &clock, scenario.ctx(),
    );
    augury::create_market(
        &mut registry, b"Jump market",
        augury::event_jump(), 100, 50, DEADLINE, &clock, scenario.ctx(),
    );
    augury::create_market(
        &mut registry, b"Destroy market",
        augury::event_item_destroy(), 0, 10, DEADLINE, &clock, scenario.ctx(),
    );

    assert!(augury::registry_market_count(&registry) == 3);
    ts::return_shared(registry);

    clock.destroy_for_testing();
    scenario.end();
}

// === View functions ===

#[test]
fun test_odds_calculation() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);

    // Empty market → 50/50
    scenario.next_tx(ADMIN);
    let market = scenario.take_shared<Market>();
    assert!(augury::yes_odds_bps(&market) == 5000);
    ts::return_shared(market);

    // 3:1 YES:NO ratio
    place(&mut scenario, ALICE, augury::side_yes(), 3_000_000, &clock);
    place(&mut scenario, BOB, augury::side_no(), 1_000_000, &clock);

    scenario.next_tx(ADMIN);
    let market = scenario.take_shared<Market>();
    assert!(augury::yes_odds_bps(&market) == 7500); // 75%
    ts::return_shared(market);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_market_view_functions() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);

    scenario.next_tx(ADMIN);
    let market = scenario.take_shared<Market>();
    assert!(augury::market_status(&market) == 0);
    assert!(augury::market_event_type(&market) == 1);
    assert!(augury::market_threshold(&market) == 20);
    assert!(augury::market_deadline(&market) == DEADLINE);
    assert!(augury::market_target_system(&market) == 42);
    assert!(augury::market_resolved_count(&market) == 0);
    assert!(augury::market_question(&market) == b"Will kills in System X exceed 20?");
    ts::return_shared(market);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_position_view_functions() {
    let mut scenario = setup();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(0);

    create_default_market(&mut scenario, &clock);
    place(&mut scenario, ALICE, augury::side_yes(), 500_000, &clock);

    scenario.next_tx(ALICE);
    let position = scenario.take_from_sender<Position>();
    assert!(augury::position_side(&position) == 1);
    assert!(augury::position_amount(&position) == 500_000);
    assert!(!augury::position_claimed(&position));
    assert!(augury::position_owner(&position) == ALICE);
    scenario.return_to_sender(position);

    clock.destroy_for_testing();
    scenario.end();
}

// === Side constants ===

#[test]
fun test_side_constants() {
    assert!(augury::side_yes() == 1);
    assert!(augury::side_no() == 2);
}
