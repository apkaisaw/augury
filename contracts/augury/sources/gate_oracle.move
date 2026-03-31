/// Smart Gate extension powered by Augury prediction market odds.
///
/// Gate owners can configure their gates to use Augury market data as an
/// access control signal. When a prediction market shows high probability
/// of danger (e.g. >80% odds of kills in a system), the gate denies passage.
///
/// This is the first concrete example of prediction market composability:
/// market odds directly influence in-game infrastructure behavior.
///
/// Setup:
/// 1. Gate owner calls gate::authorize_extension<AuguryGateAuth>(gate, owner_cap)
/// 2. Admin calls configure() to link a market and set the odds threshold
/// 3. Travelers call issue_jump_permit() — gate checks market odds before granting passage
module augury::gate_oracle;

use augury::augury::{Self, Market};
use sui::clock::Clock;
use sui::event;
use world::gate::{Self, Gate};
use world::character::Character;

// === Error codes ===
const EThreatLevelTooHigh: u64 = 200;
const EMarketMismatch: u64 = 201;
const EInvalidThreshold: u64 = 203;
const EExpiryOverflow: u64 = 204;

// === Structs ===

/// Typed witness for gate extension authorization.
/// Gate owners authorize this type via gate::authorize_extension<AuguryGateAuth>().
public struct AuguryGateAuth has drop {}

/// Configuration linking a gate to an Augury market for access control.
public struct GateOracleConfig has key {
    id: UID,
    /// The prediction market used as threat signal
    market_id: ID,
    /// YES odds above this threshold (in basis points) block passage.
    /// E.g. 8000 = if market shows >80% chance of danger, deny access.
    odds_threshold_bps: u64,
    /// How long each jump permit is valid (milliseconds)
    permit_duration_ms: u64,
}

// === Events ===

public struct GateOracleConfigured has copy, drop {
    config_id: ID,
    market_id: ID,
    odds_threshold_bps: u64,
    permit_duration_ms: u64,
}

public struct JumpPermitDenied has copy, drop {
    market_id: ID,
    current_odds_bps: u64,
    threshold_bps: u64,
    character_id: ID,
}

public struct JumpPermitGranted has copy, drop {
    market_id: ID,
    current_odds_bps: u64,
    threshold_bps: u64,
    character_id: ID,
}

// === Admin functions ===

/// Create a gate oracle configuration. Links a market to gate access control.
public fun configure(
    market_id: ID,
    odds_threshold_bps: u64,
    permit_duration_ms: u64,
    ctx: &mut TxContext,
) {
    assert!(odds_threshold_bps > 0 && odds_threshold_bps <= 10000, EInvalidThreshold);

    let config = GateOracleConfig {
        id: object::new(ctx),
        market_id,
        odds_threshold_bps,
        permit_duration_ms,
    };

    event::emit(GateOracleConfigured {
        config_id: object::id(&config),
        market_id,
        odds_threshold_bps,
        permit_duration_ms,
    });

    transfer::share_object(config);
}

/// Update the odds threshold.
public fun update_threshold(
    config: &mut GateOracleConfig,
    odds_threshold_bps: u64,
) {
    assert!(odds_threshold_bps > 0 && odds_threshold_bps <= 10000, EInvalidThreshold);
    config.odds_threshold_bps = odds_threshold_bps;
}

/// Update the linked market.
public fun update_market(
    config: &mut GateOracleConfig,
    market_id: ID,
) {
    config.market_id = market_id;
}

// === Jump permit issuance ===

/// Issue a jump permit if the linked market's odds are below the threat threshold.
///
/// If the market shows high danger probability (YES odds >= threshold), the
/// permit is denied and an event is emitted for the frontend to display.
///
/// Example: market = "Will System X see >20 kills this week?"
///          threshold = 8000 (80%)
///          current odds = 65% -> PERMIT GRANTED (below threat level)
///          current odds = 85% -> PERMIT DENIED (above threat level)
public fun issue_jump_permit(
    config: &GateOracleConfig,
    market: &Market,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(object::id(market) == config.market_id, EMarketMismatch);

    let current_odds = augury::yes_odds_bps(market);
    let character_id = object::id(character);

    if (current_odds >= config.odds_threshold_bps) {
        // Threat level too high — deny passage
        event::emit(JumpPermitDenied {
            market_id: config.market_id,
            current_odds_bps: current_odds,
            threshold_bps: config.odds_threshold_bps,
            character_id,
        });
        abort EThreatLevelTooHigh
    };

    // Safe to pass — issue permit
    let ts = clock.timestamp_ms();
    assert!(ts <= (0xFFFFFFFFFFFFFFFFu64 - config.permit_duration_ms), EExpiryOverflow);
    let expires = ts + config.permit_duration_ms;

    gate::issue_jump_permit<AuguryGateAuth>(
        source_gate,
        destination_gate,
        character,
        AuguryGateAuth {},
        expires,
        ctx,
    );

    event::emit(JumpPermitGranted {
        market_id: config.market_id,
        current_odds_bps: current_odds,
        threshold_bps: config.odds_threshold_bps,
        character_id,
    });
}

// === View functions ===

public fun config_market_id(config: &GateOracleConfig): ID { config.market_id }
public fun config_threshold(config: &GateOracleConfig): u64 { config.odds_threshold_bps }
public fun config_permit_duration(config: &GateOracleConfig): u64 { config.permit_duration_ms }
