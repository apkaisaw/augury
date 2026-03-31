/// Multi-oracle resolver registry for Augury prediction markets.
///
/// Implements the v2 oracle decentralization roadmap:
/// Multiple trusted resolvers submit observed event counts independently.
/// When a quorum (M-of-N) of resolvers agree on a value, the market is
/// auto-resolved via augury::resolve_internal().
///
/// This eliminates single-point-of-failure in the resolution process while
/// maintaining verifiability — anyone can still query the same EVE events
/// via GraphQL to audit the submitted counts.
module augury::resolver_registry;

use augury::augury::{Self, Market, AdminCap};
use sui::clock::Clock;
use sui::event;
use sui::table::{Self, Table};
use sui::vec_map::{Self, VecMap};

// === Error codes ===
const ENotRegistered: u64 = 100;
const EAlreadyRegistered: u64 = 101;
const EAlreadySubmitted: u64 = 102;
const EInvalidQuorum: u64 = 103;
const EMarketNotOpen: u64 = 104;

// === Structs ===

/// Shared registry of trusted resolvers with quorum configuration.
public struct ResolverRegistry has key {
    id: UID,
    /// Registered resolver addresses
    resolvers: vector<address>,
    /// Required agreement count (M in M-of-N)
    quorum: u64,
    /// Pending observations per market: market_id -> PendingResolution
    pending: Table<ID, PendingResolution>,
}

/// Tracks resolver submissions for a single market.
public struct PendingResolution has store {
    /// resolver_address -> observed_count
    submissions: VecMap<address, u64>,
}

// === Events ===

public struct ResolverRegistered has copy, drop {
    resolver: address,
    total_resolvers: u64,
}

public struct ResolverRemoved has copy, drop {
    resolver: address,
    total_resolvers: u64,
}

public struct ObservationSubmitted has copy, drop {
    market_id: ID,
    resolver: address,
    observed_count: u64,
    submissions_so_far: u64,
}

public struct ConsensusReached has copy, drop {
    market_id: ID,
    observed_count: u64,
    agreeing_resolvers: u64,
}

// === Init ===

/// Create a ResolverRegistry. Called by AdminCap holder to set up multi-oracle.
public fun create_registry(
    _admin: &AdminCap,
    quorum: u64,
    ctx: &mut TxContext,
) {
    assert!(quorum > 0, EInvalidQuorum);

    transfer::share_object(ResolverRegistry {
        id: object::new(ctx),
        resolvers: vector[],
        quorum,
        pending: table::new(ctx),
    });
}

// === Admin functions ===

/// Register a new trusted resolver address.
public fun register_resolver(
    _admin: &AdminCap,
    registry: &mut ResolverRegistry,
    resolver: address,
) {
    assert!(!contains(&registry.resolvers, resolver), EAlreadyRegistered);
    registry.resolvers.push_back(resolver);

    event::emit(ResolverRegistered {
        resolver,
        total_resolvers: registry.resolvers.length(),
    });
}

/// Remove a resolver from the registry.
public fun remove_resolver(
    _admin: &AdminCap,
    registry: &mut ResolverRegistry,
    resolver: address,
) {
    let (found, idx) = index_of(&registry.resolvers, resolver);
    assert!(found, ENotRegistered);
    registry.resolvers.swap_remove(idx);

    event::emit(ResolverRemoved {
        resolver,
        total_resolvers: registry.resolvers.length(),
    });
}

/// Update the quorum requirement.
public fun set_quorum(
    _admin: &AdminCap,
    registry: &mut ResolverRegistry,
    quorum: u64,
) {
    assert!(quorum > 0, EInvalidQuorum);
    registry.quorum = quorum;
}

// === Resolver functions ===

/// Submit an observed event count for a market.
/// When quorum is reached on a value, the market is auto-resolved.
public fun submit_observation(
    registry: &mut ResolverRegistry,
    market: &mut Market,
    observed_count: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(contains(&registry.resolvers, sender), ENotRegistered);
    assert!(augury::market_status(market) == 0, EMarketNotOpen); // STATUS_OPEN

    let market_id = object::id(market);

    // Initialize pending resolution if first submission for this market
    if (!registry.pending.contains(market_id)) {
        registry.pending.add(market_id, PendingResolution {
            submissions: vec_map::empty(),
        });
    };

    let pending = registry.pending.borrow_mut(market_id);
    assert!(!pending.submissions.contains(&sender), EAlreadySubmitted);
    pending.submissions.insert(sender, observed_count);

    let submission_count = pending.submissions.length();

    event::emit(ObservationSubmitted {
        market_id,
        resolver: sender,
        observed_count,
        submissions_so_far: submission_count,
    });

    // Check if any value has reached quorum
    let (consensus_value, agreeing_count) = find_consensus(pending, registry.quorum);
    if (agreeing_count >= registry.quorum) {
        // Quorum reached — resolve the market
        augury::resolve_internal(market, consensus_value, clock);

        // Clean up pending (remove from table)
        let PendingResolution { submissions } = registry.pending.remove(market_id);
        submissions.into_keys_values();

        event::emit(ConsensusReached {
            market_id,
            observed_count: consensus_value,
            agreeing_resolvers: agreeing_count,
        });
    };
}

// === View functions ===

public fun resolver_count(registry: &ResolverRegistry): u64 {
    registry.resolvers.length()
}

public fun quorum(registry: &ResolverRegistry): u64 {
    registry.quorum
}

public fun is_resolver(registry: &ResolverRegistry, addr: address): bool {
    contains(&registry.resolvers, addr)
}

// === Internal helpers ===

/// Find the value with the most votes. Returns (value, count).
fun find_consensus(pending: &PendingResolution, _quorum: u64): (u64, u64) {
    let size = pending.submissions.length();
    if (size == 0) return (0, 0);

    // Count votes per value
    let mut best_value = 0u64;
    let mut best_count = 0u64;
    let mut i = 0;

    while (i < size) {
        let (_, value) = pending.submissions.get_entry_by_idx(i);
        // Count how many resolvers submitted this same value
        let mut count = 0u64;
        let mut j = 0;
        while (j < size) {
            let (_, other_value) = pending.submissions.get_entry_by_idx(j);
            if (*other_value == *value) {
                count = count + 1;
            };
            j = j + 1;
        };
        if (count > best_count) {
            best_count = count;
            best_value = *value;
        };
        i = i + 1;
    };

    (best_value, best_count)
}

fun contains(v: &vector<address>, addr: address): bool {
    let (found, _) = index_of(v, addr);
    found
}

fun index_of(v: &vector<address>, addr: address): (bool, u64) {
    let mut i = 0;
    while (i < v.length()) {
        if (*v.borrow(i) == addr) return (true, i);
        i = i + 1;
    };
    (false, 0)
}

// === Test helpers ===
#[test_only]
public fun create_registry_for_testing(quorum: u64, ctx: &mut TxContext) {
    transfer::share_object(ResolverRegistry {
        id: object::new(ctx),
        resolvers: vector[],
        quorum,
        pending: table::new(ctx),
    });
}

#[test_only]
public fun pending_count(registry: &ResolverRegistry, market_id: ID): u64 {
    if (!registry.pending.contains(market_id)) { 0 }
    else { registry.pending.borrow(market_id).submissions.length() }
}
