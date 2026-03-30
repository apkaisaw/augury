# Augury — Contract Review v1

**Score: 5.5 / 10**

## Summary

Functional prediction market with correct event/shared-object/clock patterns, but has a **critical security vulnerability** in `claim()` and missing Table indexing. Zero tests.

## What's Good

- 4 proper events (MarketCreated, BetPlaced, MarketResolved, WinningsClaimed)
- AdminCap gates resolution correctly
- Market and Treasury are shared objects (concurrent access)
- Clock used for deadline validation
- Clean module structure with named error codes

## Critical Issues (P0)

### 1. `claim()` does not verify position owner

Anyone who can reference a Position object can call `claim()` and steal winnings. Must add:
```move
assert!(ctx.sender() == position.owner, EUnauthorized);
```

### 2. Division by zero in payout calculation

If all bets are on one side and that side loses, `winning_pool` is 0 → divide by zero panic. Must add:
```move
assert!(winning_pool_value > 0, ENoWinners);
```

## High Issues (P1)

### 3. No Table for market indexing

Only a `market_count: u64` in MarketRegistry. No way to enumerate markets on-chain. Add:
```move
markets: Table<u64, ID>
```

### 4. Fee logic is convoluted

Fee extraction from pools after payout is fragile. Simplify to always take fee from the losing pool first.

### 5. No input validation

- No minimum deadline duration
- No max string length for question/event_type (storage DoS risk)

## EVE Integration Gap

Contract is generic — does not reference or verify any EVE events (KillMail, JumpEvent, etc.) on-chain. Resolution is fully off-chain via AdminCap. The "on-chain events as oracle" innovation exists only at the architecture level, not in the contract code.

**Recommendation:** Add event_type enum constants (KILLMAIL=1, JUMP=2, ITEM_DESTROY=3) and store target parameters (system_id, threshold) so the contract at least documents what it's resolving. Consider adding a `ResolverRegistry` allowing multiple trusted resolvers, not just a single AdminCap.

## Missing

- [ ] Tests (0 — need 25+ covering payout math, access control, edge cases)
- [ ] Table-based market registry
- [ ] Position owner verification in claim()
- [ ] Division-by-zero guard
- [ ] Input validation (min deadline, max string length)
- [ ] Multi-resolver support (reduce centralization)

## Priority Order

1. **Fix claim() access control** (security — fund theft possible)
2. **Fix division by zero** (crash on edge case)
3. **Add Table indexing** (functionality)
4. **Add EVE event type constants** (integration depth)
5. **Add tests** (quality)
