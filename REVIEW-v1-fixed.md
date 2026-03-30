# REVIEW-v1 Fix Summary

All issues from REVIEW-v1.md have been addressed. Contract redeployed as v2.

## P0 — Critical (Fixed)

### 1. claim() owner verification
- **Added:** `assert!(ctx.sender() == position.owner, EUnauthorized)` as the first check in `claim()`
- **Tests:** `test_claim_by_owner_succeeds`, `test_claim_by_non_owner_fails`

### 2. Division by zero in payout
- **Added:** `assert!(winning_pool_value > 0, ENoWinners)` guard before the division
- **Tests:** `test_no_winning_pool_loser_cannot_claim` (ENotWinner fires first as defense-in-depth; the ENoWinners guard catches any remaining edge case)

## P1 — High (Fixed)

### 3. Table-based market indexing
- **Added:** `markets: Table<u64, ID>` to `MarketRegistry`
- **Added:** `registry_market_count()` and `registry_market_at(index)` view functions
- Markets are now enumerable on-chain by index
- **Tests:** `test_registry_table_indexing` (creates 3 markets, verifies lookup by index)

### 4. Fee logic simplified
- **Rewritten:** Fee is now extracted first (from losing pool, then winning pool), before payout. Clear sequential logic instead of conditional branching.

### 5. Input validation
- **Min deadline:** 1 hour from creation (`MIN_DEADLINE_DURATION_MS = 3_600_000`)
- **Max question length:** 256 bytes (`MAX_QUESTION_LENGTH = 256`)
- **EVE event type validation:** Must be 1, 2, or 3
- **Tests:** `test_create_market_deadline_too_soon`, `test_create_market_question_too_long`, `test_create_market_invalid_event_type`, `test_create_market_zero_threshold`

## EVE Integration (Fixed)

### 6. Event type constants
- **Replaced** `event_type: vector<u8>` (string) with `event_type: u8` (enum constant)
- **Constants:** `EVENT_KILLMAIL=1`, `EVENT_JUMP=2`, `EVENT_ITEM_DESTROY=3`
- **Added:** Public accessors `event_killmail()`, `event_jump()`, `event_item_destroy()` for SDK usage
- **Added:** `resolved_count: u64` field on Market — stores the actual observed count submitted by the resolver
- **Changed:** `resolve()` now takes `observed_count` instead of raw `outcome`; the contract computes `observed_count >= threshold` to determine YES/NO
- **Event:** `MarketResolved` now includes `observed_count` alongside `outcome`
- **Tests:** `test_eve_event_type_constants`, `test_all_three_event_types_create`, `test_resolve_at_exact_threshold`

## Tests (Added)

29 tests total, all passing:
- Access control: owner verification, AdminCap gating, unauthorized claim
- Payout math: proportional split, multiple winners, fee calculation (2%)
- Edge cases: zero bet, invalid side, double claim, double resolve, deadline enforcement
- EVE integration: all 3 event types, threshold boundary
- Table indexing: multi-market registry enumeration
- View functions: market and position getters, odds calculation

## Deployment

- **v2 Package ID:** `0xb4d66c40073c8ad61df419386645711d5ae2051f96f2e4a0ddaffbc38580b933`
- **Tx:** `3Q5wuWAHngEETMrFYq9Q5KXPik51EXC64zVfENs4Njoo`
- v1 (`0x3fe621...`) is deprecated

## What Remains (Out of Scope for This Pass)

- **Multi-resolver support:** Currently single AdminCap. Could add a `ResolverRegistry` allowing multiple trusted resolvers for decentralization. Low priority for hackathon.
- **Emergency admin functions:** No cancel/refund mechanism if a market can't be resolved. Could add `emergency_refund()` gated by AdminCap.
- **Position transfer hook:** Position is transferable (`store` ability) but `claim()` checks `position.owner` field, not Sui ownership. If someone transfers the Position object, the original owner field remains. This is actually correct (prevents theft) but means transferred positions must update `owner` — not implemented.
