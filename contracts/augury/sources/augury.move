/// Augury - A prediction market for EVE Frontier on-chain events.
///
/// Core insight: EVE Frontier game events (KillMail, JumpEvent, ItemDestroyed)
/// are on-chain immutable facts, serving as trustless oracles.
///
/// Settlement: off-chain indexer queries EVE events via GraphQL,
/// then AdminCap holder submits the observed count on-chain.
/// Anyone can verify by querying the same events.
#[allow(lint(self_transfer))]
module augury::augury;

use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::event;
use sui::table::{Self, Table};

// === Error codes ===
const EMarketNotOpen: u64 = 0;
const EMarketNotResolved: u64 = 1;
const EMarketAlreadyResolved: u64 = 2;
const EDeadlineNotReached: u64 = 3;
const EDeadlineReached: u64 = 4;
const EInvalidSide: u64 = 5;
const EZeroBet: u64 = 6;
const ENotWinner: u64 = 7;
const EAlreadyClaimed: u64 = 8;
const EInvalidDeadline: u64 = 9;
const EInvalidThreshold: u64 = 10;
const EUnauthorized: u64 = 11;
const ENoWinners: u64 = 12;
const EInvalidEventType: u64 = 13;
const EQuestionTooLong: u64 = 14;
const EPositionMarketMismatch: u64 = 15;

// === EVE Frontier event type constants ===
const EVENT_KILLMAIL: u8 = 1;
const EVENT_JUMP: u8 = 2;
const EVENT_ITEM_DESTROY: u8 = 3;

// === Bet sides ===
const YES: u8 = 1;
const NO: u8 = 2;

// === Market status ===
const STATUS_OPEN: u8 = 0;
const STATUS_RESOLVED_YES: u8 = 1;
const STATUS_RESOLVED_NO: u8 = 2;

// === Protocol parameters ===
/// 2% fee (200 basis points)
const FEE_BPS: u64 = 200;
const BPS_DENOMINATOR: u64 = 10000;
/// Minimum deadline: 1 hour from now
const MIN_DEADLINE_DURATION_MS: u64 = 3_600_000;
/// Maximum question length in bytes
const MAX_QUESTION_LENGTH: u64 = 256;

// === Structs ===

/// Admin capability for resolving markets. Created on init.
public struct AdminCap has key, store {
    id: UID,
}

/// Treasury to collect protocol fees.
public struct Treasury has key {
    id: UID,
    balance: Balance<SUI>,
}

/// Market registry with Table-based index for on-chain enumeration.
public struct MarketRegistry has key {
    id: UID,
    market_count: u64,
    markets: Table<u64, ID>,
}

/// A prediction market tied to a specific EVE Frontier event type.
public struct Market has key, store {
    id: UID,
    /// Human-readable question (max 256 bytes)
    question: vector<u8>,
    /// EVE event type: KILLMAIL(1), JUMP(2), ITEM_DESTROY(3)
    event_type: u8,
    /// Target solar system ID (0 = any system)
    target_system_id: u64,
    /// Threshold count for YES outcome (e.g. ">20 kills")
    threshold: u64,
    /// Deadline timestamp in milliseconds
    deadline_ms: u64,
    /// Current status: OPEN(0), RESOLVED_YES(1), RESOLVED_NO(2)
    status: u8,
    /// Observed event count submitted by resolver (0 until resolved)
    resolved_count: u64,
    /// Total YES pool
    yes_pool: Balance<SUI>,
    /// Total NO pool
    no_pool: Balance<SUI>,
    /// Number of YES positions
    yes_count: u64,
    /// Number of NO positions
    no_count: u64,
    /// Creator address
    creator: address,
}

/// A player's position in a market.
public struct Position has key, store {
    id: UID,
    market_id: ID,
    /// YES (1) or NO (2)
    side: u8,
    /// Amount staked in MIST
    amount: u64,
    /// Whether winnings have been claimed
    claimed: bool,
    /// Owner address
    owner: address,
}

// === Events ===

public struct MarketCreated has copy, drop {
    market_id: ID,
    question: vector<u8>,
    event_type: u8,
    target_system_id: u64,
    threshold: u64,
    deadline_ms: u64,
    creator: address,
}

public struct BetPlaced has copy, drop {
    market_id: ID,
    position_id: ID,
    side: u8,
    amount: u64,
    player: address,
}

public struct MarketResolved has copy, drop {
    market_id: ID,
    outcome: u8,
    observed_count: u64,
}

public struct WinningsClaimed has copy, drop {
    market_id: ID,
    position_id: ID,
    payout: u64,
    player: address,
}

// === Init ===

fun init(ctx: &mut TxContext) {
    transfer::transfer(
        AdminCap { id: object::new(ctx) },
        ctx.sender(),
    );

    transfer::share_object(Treasury {
        id: object::new(ctx),
        balance: balance::zero(),
    });

    transfer::share_object(MarketRegistry {
        id: object::new(ctx),
        market_count: 0,
        markets: table::new(ctx),
    });
}

// === Public functions ===

/// Create a new prediction market for an EVE Frontier event type.
/// event_type: 1=KILLMAIL, 2=JUMP, 3=ITEM_DESTROY
public fun create_market(
    registry: &mut MarketRegistry,
    question: vector<u8>,
    event_type: u8,
    target_system_id: u64,
    threshold: u64,
    deadline_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let now = clock.timestamp_ms();
    assert!(deadline_ms > now + MIN_DEADLINE_DURATION_MS, EInvalidDeadline);
    assert!(threshold > 0, EInvalidThreshold);
    assert!(
        event_type == EVENT_KILLMAIL ||
        event_type == EVENT_JUMP ||
        event_type == EVENT_ITEM_DESTROY,
        EInvalidEventType,
    );
    assert!(question.length() <= MAX_QUESTION_LENGTH, EQuestionTooLong);

    let market = Market {
        id: object::new(ctx),
        question,
        event_type,
        target_system_id,
        threshold,
        deadline_ms,
        status: STATUS_OPEN,
        resolved_count: 0,
        yes_pool: balance::zero(),
        no_pool: balance::zero(),
        yes_count: 0,
        no_count: 0,
        creator: ctx.sender(),
    };

    let market_id = object::id(&market);
    let index = registry.market_count;
    registry.markets.add(index, market_id);
    registry.market_count = index + 1;

    event::emit(MarketCreated {
        market_id,
        question: market.question,
        event_type,
        target_system_id,
        threshold,
        deadline_ms,
        creator: ctx.sender(),
    });

    transfer::share_object(market);
}

/// Place a bet on YES (1) or NO (2).
public fun place_bet(
    market: &mut Market,
    side: u8,
    coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(market.status == STATUS_OPEN, EMarketNotOpen);
    assert!(clock.timestamp_ms() < market.deadline_ms, EDeadlineReached);
    assert!(side == YES || side == NO, EInvalidSide);

    let amount = coin.value();
    assert!(amount > 0, EZeroBet);

    if (side == YES) {
        market.yes_pool.join(coin.into_balance());
        market.yes_count = market.yes_count + 1;
    } else {
        market.no_pool.join(coin.into_balance());
        market.no_count = market.no_count + 1;
    };

    let position = Position {
        id: object::new(ctx),
        market_id: object::id(market),
        side,
        amount,
        claimed: false,
        owner: ctx.sender(),
    };

    event::emit(BetPlaced {
        market_id: object::id(market),
        position_id: object::id(&position),
        side,
        amount,
        player: ctx.sender(),
    });

    transfer::transfer(position, ctx.sender());
}

/// Resolve a market with the observed event count.
/// Only AdminCap holder (off-chain indexer/resolver) can call.
/// The outcome is YES if observed_count >= threshold, NO otherwise.
public fun resolve(
    _admin: &AdminCap,
    market: &mut Market,
    observed_count: u64,
    clock: &Clock,
) {
    assert!(market.status == STATUS_OPEN, EMarketAlreadyResolved);
    assert!(clock.timestamp_ms() >= market.deadline_ms, EDeadlineNotReached);

    market.resolved_count = observed_count;
    let outcome = if (observed_count >= market.threshold) {
        STATUS_RESOLVED_YES
    } else {
        STATUS_RESOLVED_NO
    };
    market.status = outcome;

    event::emit(MarketResolved {
        market_id: object::id(market),
        outcome,
        observed_count,
    });
}

/// Claim winnings for a winning position. Only position owner can call.
public fun claim(
    market: &mut Market,
    treasury: &mut Treasury,
    position: &mut Position,
    ctx: &mut TxContext,
) {
    // P0 fix: verify caller is position owner
    assert!(ctx.sender() == position.owner, EUnauthorized);
    assert!(
        market.status == STATUS_RESOLVED_YES || market.status == STATUS_RESOLVED_NO,
        EMarketNotResolved,
    );
    assert!(!position.claimed, EAlreadyClaimed);
    assert!(position.market_id == object::id(market), EPositionMarketMismatch);

    let is_winner = (position.side == YES && market.status == STATUS_RESOLVED_YES) ||
                    (position.side == NO && market.status == STATUS_RESOLVED_NO);
    assert!(is_winner, ENotWinner);

    let total_pool = market.yes_pool.value() + market.no_pool.value();
    let winning_pool_value = if (market.status == STATUS_RESOLVED_YES) {
        market.yes_pool.value()
    } else {
        market.no_pool.value()
    };

    // P0 fix: guard against division by zero
    assert!(winning_pool_value > 0, ENoWinners);

    // Proportional payout (u128 to avoid overflow), then deduct fee
    let gross = ((position.amount as u128) * (total_pool as u128) / (winning_pool_value as u128) as u64);
    let fee = gross * FEE_BPS / BPS_DENOMINATOR;
    let net = gross - fee;

    // Simplified fee logic: take fee from losing pool first, then winning pool
    let (losing_pool, winning_pool_ref) = if (market.status == STATUS_RESOLVED_YES) {
        (&mut market.no_pool, &mut market.yes_pool)
    } else {
        (&mut market.yes_pool, &mut market.no_pool)
    };

    // Fee to treasury (from losing pool first)
    if (fee > 0) {
        let fee_from_losing = fee.min(losing_pool.value());
        if (fee_from_losing > 0) {
            treasury.balance.join(losing_pool.split(fee_from_losing));
        };
        let fee_remaining = fee - fee_from_losing;
        if (fee_remaining > 0) {
            treasury.balance.join(winning_pool_ref.split(fee_remaining));
        };
    };

    // Net payout to winner (from losing pool first)
    let mut payout_balance = balance::zero<SUI>();
    let net_from_losing = net.min(losing_pool.value());
    if (net_from_losing > 0) {
        payout_balance.join(losing_pool.split(net_from_losing));
    };
    let net_remaining = net - net_from_losing;
    if (net_remaining > 0) {
        payout_balance.join(winning_pool_ref.split(net_remaining));
    };

    position.claimed = true;

    event::emit(WinningsClaimed {
        market_id: object::id(market),
        position_id: object::id(position),
        payout: net,
        player: position.owner,
    });

    transfer::public_transfer(coin::from_balance(payout_balance, ctx), position.owner);
}

// === View functions ===

public fun market_status(market: &Market): u8 { market.status }
public fun market_event_type(market: &Market): u8 { market.event_type }
public fun market_yes_pool(market: &Market): u64 { market.yes_pool.value() }
public fun market_no_pool(market: &Market): u64 { market.no_pool.value() }
public fun market_deadline(market: &Market): u64 { market.deadline_ms }
public fun market_threshold(market: &Market): u64 { market.threshold }
public fun market_question(market: &Market): vector<u8> { market.question }
public fun market_resolved_count(market: &Market): u64 { market.resolved_count }
public fun market_target_system(market: &Market): u64 { market.target_system_id }

public fun position_side(pos: &Position): u8 { pos.side }
public fun position_amount(pos: &Position): u64 { pos.amount }
public fun position_claimed(pos: &Position): bool { pos.claimed }
public fun position_market_id(pos: &Position): ID { pos.market_id }
public fun position_owner(pos: &Position): address { pos.owner }

public fun registry_market_count(reg: &MarketRegistry): u64 { reg.market_count }
public fun registry_market_at(reg: &MarketRegistry, index: u64): ID { *reg.markets.borrow(index) }

/// Current implied odds for YES side (basis points, 0-10000).
public fun yes_odds_bps(market: &Market): u64 {
    let total = market.yes_pool.value() + market.no_pool.value();
    if (total == 0) { 5000 }
    else { market.yes_pool.value() * BPS_DENOMINATOR / total }
}

// === Public constants for SDK/frontend usage ===
public fun event_killmail(): u8 { EVENT_KILLMAIL }
public fun event_jump(): u8 { EVENT_JUMP }
public fun event_item_destroy(): u8 { EVENT_ITEM_DESTROY }
public fun side_yes(): u8 { YES }
public fun side_no(): u8 { NO }

// === Test helpers ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun market_yes_count(market: &Market): u64 { market.yes_count }

#[test_only]
public fun market_no_count(market: &Market): u64 { market.no_count }

#[test_only]
public fun treasury_balance(treasury: &Treasury): u64 { treasury.balance.value() }
