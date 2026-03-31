# Augury — Final Review v2

**Score: 7.5 / 10 | v1: 5.5 → v2: 7.5 (+2.0)**

## Submission Readiness: READY

## What Judges Will See

A prediction market where EVE Frontier's on-chain events (KillMail, JumpEvent, ItemDestroyed) serve as trustless oracles. No external oracle needed — the chain data IS the truth. Players bet on real in-game outcomes; settlement is verifiable by anyone.

## Code Quality

- 430 lines Move, 29 tests (760 lines), all passing
- Critical P0 fixed: claim() now verifies position owner
- Division-by-zero guard added
- Table-based market registry with enumeration
- Input validation: min deadline (1h), max question length (256), event type constants
- EVE event types documented in contract (KILLMAIL=1, JUMP=2, ITEM_DESTROY=3)

## EVE Integration: Good

- 3 event types referenced (KillMail, JumpEvent, ItemDestroyedEvent)
- Market stores target_system_id + threshold + observed_count
- Settlement: backend indexes events via GraphQL → submits observed_count → contract auto-settles
- Same architecture as Aegis Stack (S-tier) — off-chain indexing → on-chain oracle

## Competitive Position

- Zero prediction market / DeFi competitors
- Core innovation: "on-chain game events = trustless oracle" — genuinely novel, not just a port
- Biggest improvement from v1 (+2.0 points)

## Target Categories

1. **Creative** (primary) — "game events as oracles" is conceptually innovative
2. **Technical Implementation** — off-chain indexing → on-chain settlement
3. **Utility** — prediction markets aggregate collective intelligence

## Top 3 Improvements Before Submission

1. **Market creation + betting UI** — even a simple React form (create market, place bet, view odds) makes judges see the product. (+15%)
2. **Backend resolver example** — Python script: query GraphQL for KillMail count in system X → call resolve(). Proves the oracle architecture works end-to-end. (+10%)
3. **Demo video** — create a market ("Will System 1000 have >5 kills this week?"), place bets from two wallets, resolve with mock data, show payout. (+10%)

## Remaining Gaps

- No multi-resolver support (single AdminCap) — acceptable for hackathon
- No emergency refund mechanism for unresolvable markets
- No frontend
