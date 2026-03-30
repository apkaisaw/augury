/// Augury - A prediction market for EVE Frontier on-chain events.
///
/// Core insight: EVE Frontier game events (KillMail, JumpEvent, etc.) are
/// on-chain immutable facts, serving as trustless oracles. No external oracle needed.
///
/// Settlement flow: off-chain indexer queries EVE events via GraphQL,
/// then submits the outcome on-chain. Anyone can verify by querying the same events.
#[allow(lint(self_transfer))]
module augury::augury;

use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::event;

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

// === Constants ===
/// Sides
const YES: u8 = 1;
const NO: u8 = 2;

/// Market status
const STATUS_OPEN: u8 = 0;
const STATUS_RESOLVED_YES: u8 = 1;
const STATUS_RESOLVED_NO: u8 = 2;

/// Protocol fee: 2% (200 basis points)
const FEE_BPS: u64 = 200;
const BPS_DENOMINATOR: u64 = 10000;

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

/// Market registry - tracks all markets.
public struct MarketRegistry has key {
    id: UID,
    market_count: u64,
}

/// A prediction market.
public struct Market has key, store {
    id: UID,
    /// Human-readable question, e.g. "Will System X have >20 kills this week?"
    question: vector<u8>,
    /// EVE event type: "killmail", "jump", "item_destroyed"
    event_type: vector<u8>,
    /// Target solar system ID (0 = any system)
    target_system_id: u64,
    /// Threshold count for YES outcome
    threshold: u64,
    /// Deadline timestamp in milliseconds
    deadline_ms: u64,
    /// Current status
    status: u8,
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
    /// Market ID this position belongs to
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
    event_type: vector<u8>,
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
}

public struct WinningsClaimed has copy, drop {
    market_id: ID,
    position_id: ID,
    payout: u64,
    player: address,
}

// === Init ===

fun init(ctx: &mut TxContext) {
    let admin_cap = AdminCap { id: object::new(ctx) };
    transfer::transfer(admin_cap, ctx.sender());

    let treasury = Treasury {
        id: object::new(ctx),
        balance: balance::zero(),
    };
    transfer::share_object(treasury);

    let registry = MarketRegistry {
        id: object::new(ctx),
        market_count: 0,
    };
    transfer::share_object(registry);
}

// === Public functions ===

/// Create a new prediction market.
public fun create_market(
    registry: &mut MarketRegistry,
    question: vector<u8>,
    event_type: vector<u8>,
    target_system_id: u64,
    threshold: u64,
    deadline_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(deadline_ms > clock.timestamp_ms(), EInvalidDeadline);
    assert!(threshold > 0, EInvalidThreshold);

    let market = Market {
        id: object::new(ctx),
        question,
        event_type,
        target_system_id,
        threshold,
        deadline_ms,
        status: STATUS_OPEN,
        yes_pool: balance::zero(),
        no_pool: balance::zero(),
        yes_count: 0,
        no_count: 0,
        creator: ctx.sender(),
    };

    registry.market_count = registry.market_count + 1;

    event::emit(MarketCreated {
        market_id: object::id(&market),
        question: market.question,
        event_type: market.event_type,
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

    let coin_balance = coin.into_balance();

    if (side == YES) {
        market.yes_pool.join(coin_balance);
        market.yes_count = market.yes_count + 1;
    } else {
        market.no_pool.join(coin_balance);
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

/// Resolve a market. Only AdminCap holder can call this.
/// Called after deadline, with the outcome determined by off-chain event indexing.
public fun resolve(
    _admin: &AdminCap,
    market: &mut Market,
    outcome: u8,
    clock: &Clock,
) {
    assert!(market.status == STATUS_OPEN, EMarketAlreadyResolved);
    assert!(clock.timestamp_ms() >= market.deadline_ms, EDeadlineNotReached);
    assert!(outcome == STATUS_RESOLVED_YES || outcome == STATUS_RESOLVED_NO, EInvalidSide);

    market.status = outcome;

    event::emit(MarketResolved {
        market_id: object::id(market),
        outcome,
    });
}

/// Claim winnings for a winning position.
public fun claim(
    market: &mut Market,
    treasury: &mut Treasury,
    position: &mut Position,
    ctx: &mut TxContext,
) {
    assert!(market.status == STATUS_RESOLVED_YES || market.status == STATUS_RESOLVED_NO, EMarketNotResolved);
    assert!(!position.claimed, EAlreadyClaimed);
    assert!(position.market_id == object::id(market), EMarketNotOpen);

    // Determine if this position is a winner
    let is_winner = (position.side == YES && market.status == STATUS_RESOLVED_YES) ||
                    (position.side == NO && market.status == STATUS_RESOLVED_NO);
    assert!(is_winner, ENotWinner);

    // Calculate payout: winner gets proportional share of the total pool
    let total_pool = market.yes_pool.value() + market.no_pool.value();
    let winning_pool = if (market.status == STATUS_RESOLVED_YES) {
        market.yes_pool.value()
    } else {
        market.no_pool.value()
    };

    // Proportional payout = (position.amount / winning_pool) * total_pool
    // Use u128 to avoid overflow
    let payout = ((position.amount as u128) * (total_pool as u128) / (winning_pool as u128) as u64);

    // Deduct protocol fee
    let fee = payout * FEE_BPS / BPS_DENOMINATOR;
    let net_payout = payout - fee;

    // Take from the appropriate pools
    // First take from losing pool, then from winning pool if needed
    let (losing_pool, winning_pool_ref) = if (market.status == STATUS_RESOLVED_YES) {
        (&mut market.no_pool, &mut market.yes_pool)
    } else {
        (&mut market.yes_pool, &mut market.no_pool)
    };

    let mut payout_balance = balance::zero<SUI>();

    // Take from losing pool first
    let from_losing = if (losing_pool.value() >= net_payout) {
        net_payout
    } else {
        losing_pool.value()
    };
    if (from_losing > 0) {
        payout_balance.join(losing_pool.split(from_losing));
    };

    // Take remainder from winning pool
    let remaining = net_payout - from_losing;
    if (remaining > 0) {
        payout_balance.join(winning_pool_ref.split(remaining));
    };

    // Fee goes to treasury
    if (fee > 0) {
        let fee_source = if (losing_pool.value() >= fee) {
            losing_pool
        } else {
            winning_pool_ref
        };
        treasury.balance.join(fee_source.split(fee));
    };

    position.claimed = true;

    let payout_coin = coin::from_balance(payout_balance, ctx);

    event::emit(WinningsClaimed {
        market_id: object::id(market),
        position_id: object::id(position),
        payout: net_payout,
        player: ctx.sender(),
    });

    transfer::public_transfer(payout_coin, position.owner);
}

// === View functions ===

public fun market_status(market: &Market): u8 { market.status }
public fun market_yes_pool(market: &Market): u64 { market.yes_pool.value() }
public fun market_no_pool(market: &Market): u64 { market.no_pool.value() }
public fun market_deadline(market: &Market): u64 { market.deadline_ms }
public fun market_threshold(market: &Market): u64 { market.threshold }
public fun market_question(market: &Market): vector<u8> { market.question }

public fun position_side(pos: &Position): u8 { pos.side }
public fun position_amount(pos: &Position): u64 { pos.amount }
public fun position_claimed(pos: &Position): bool { pos.claimed }
public fun position_market_id(pos: &Position): ID { pos.market_id }

/// Current implied odds for YES side (basis points, 0-10000).
public fun yes_odds_bps(market: &Market): u64 {
    let yes_val = market.yes_pool.value();
    let no_val = market.no_pool.value();
    let total = yes_val + no_val;
    if (total == 0) { 5000 } // 50/50 default
    else { yes_val * BPS_DENOMINATOR / total }
}
