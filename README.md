# Augury

Collective intelligence for EVE Frontier. A prediction market where on-chain game events are the oracle.

## Why This Matters

When 1,000 players simultaneously bet on "Will Null-sec System X see a major battle this week?", the resulting odds become the most accurate early warning system in EVE Frontier. Augury doesn't predict the future -- it aggregates what thousands of players collectively know into a single, real-time price signal.

Every war, every trade route disruption, every resource crisis -- players see the signs before they happen. Augury turns that scattered knowledge into verifiable, on-chain intelligence that anyone can read.

## The Insight

Traditional prediction markets need external oracles -- someone trusted to say "this happened." That trust assumption is the central weakness of every prediction market ever built.

EVE Frontier doesn't have this problem. Every kill, every gate jump, every item destroyed is already an immutable on-chain event. The chain data IS the oracle. No Chainlink, no dispute resolution, no trust required. Settlement is a simple count: "Did System X see 20+ kills? Query the chain. The answer is right there."

This is the only project in 68 hackathon submissions that exploits this insight.

## How It Works

```
1. Creator publishes a market
   "Will System 30003489 see >20 kills this week?"
   (EVE event type + target system + threshold + deadline)

2. Players stake SUI on YES or NO
   Odds shift with each bet -- the market price IS the prediction

3. Deadline passes

4. Indexer counts matching on-chain EVE events via GraphQL
   Anyone can run the same query to verify independently

5. Contract auto-settles: observed_count >= threshold -> YES wins

6. Winners claim proportional payout (minus 2% protocol fee)
```

## Composability: Markets as Infrastructure

Augury's resolved markets are readable on-chain by any other contract. This makes prediction market outcomes a building block for the EVE Frontier ecosystem:

- **Insurance pricing** -- A market showing 80% odds of conflict in a system is a real-time risk signal. Insurance protocols can read `market_status` and `yes_odds_bps` to dynamically price coverage for ships operating in that system.
- **Smart Gate strategies** -- Gate controllers can query active markets to adjust toll pricing or access policies. High predicted traffic (JumpEvent markets) means higher tolls. High predicted combat (KillMail markets) means restricted access.
- **Reputation input** -- A player's prediction track record (win rate across positions) is a measurable signal of information quality. Reputation systems can index `WinningsClaimed` events to score player intelligence.
- **DAO governance** -- Tribes can create markets to gauge member sentiment before committing to operations. "Should we attack System X?" becomes a market where members put stake behind their conviction.

All view functions (`market_status`, `yes_odds_bps`, `market_resolved_count`, `market_threshold`) are public and composable. Any contract can read Augury's markets in the same transaction.

## Oracle Decentralization Roadmap

The current resolver architecture is intentionally simple for v1. Here is the path to full decentralization:

**v1 (current):** Single AdminCap holder submits `observed_count`. Anyone can independently query the same EVE events via GraphQL to audit the result. Trust assumption: the resolver is honest.

**v2 (planned):** Multi-oracle voting. Multiple resolvers register via a `ResolverRegistry`. Resolution requires M-of-N agreement on `observed_count`. Any registered resolver can submit, and the contract accepts the majority value. Trust assumption: majority of resolvers are honest.

**v3 (target):** Permissionless resolution. Anyone can call `resolve()` by providing a Sui-signed attestation of the event count. The contract verifies the attestation against known EVE world contract event signatures. Trust assumption: the chain itself.

## EVE Frontier Integration

### Supported Event Types

| Constant | Value | EVE Source | Example Market |
|----------|-------|-----------|----------------|
| `EVENT_KILLMAIL` | 1 | `KillmailCreatedEvent` | "Will System 30003489 see >20 kills this week?" |
| `EVENT_JUMP` | 2 | `JumpEvent` | "Will Gate Y process >100 jumps tomorrow?" |
| `EVENT_ITEM_DESTROY` | 3 | `ItemDestroyedEvent` | "Will >50% of rare ore be destroyed in 7 days?" |

### Oracle Loop

Each market stores `event_type`, `target_system_id`, and `threshold`. The off-chain indexer queries corresponding EVE events via Sui GraphQL with cursor-based pagination, counts matches within the time window, and submits the observed count. The contract compares against the threshold to determine the outcome. Anyone can run the same query to verify -- the data is public, the logic is deterministic, the result is inevitable.

## Technical Architecture

### Contract (430 lines Move, 29 tests)

| Object | Type | Description |
|--------|------|-------------|
| `Market` | Shared | Prediction market with YES/NO pools, deadline, threshold, event type |
| `Position` | Owned | Player's stake in a market (side, amount, claimed status) |
| `MarketRegistry` | Shared | Table-indexed registry of all markets |
| `Treasury` | Shared | Protocol fee collection |
| `AdminCap` | Owned | Authorizes the off-chain resolver to submit outcomes |

| Function | Access | Description |
|----------|--------|-------------|
| `create_market` | Anyone | Create a market for a specific EVE event type |
| `place_bet` | Anyone (before deadline) | Stake SUI on YES or NO |
| `resolve` | AdminCap holder (after deadline) | Submit observed event count; outcome auto-determined |
| `claim` | Position owner (winning side) | Withdraw proportional share of the pool |

### Settlement Flow

```
EVE Frontier chain (KillmailCreatedEvent, JumpEvent, ItemDestroyedEvent)
    |
    v
Off-chain indexer (Sui GraphQL: cursor-paginated event query)
    |
    v
AdminCap holder calls resolve(observed_count)
    |
    v
Contract: observed_count >= threshold ? YES : NO
    |
    v
Winners call claim() -> proportional payout from combined pool
```

### Sui Features

| Feature | Usage |
|---------|-------|
| **Clock** | Deadline enforcement for betting and resolution |
| **Events** | 4 event types for frontend indexing and off-chain tracking |
| **Table** | Market registry with on-chain enumeration by index |
| **Capabilities** | AdminCap gates resolution to authorized resolver |
| **Coin / Balance** | SUI staking pools, proportional payout math (u128), fee extraction |
| **Shared Objects** | Market, Treasury, Registry -- concurrent multi-player access |

## Deployed on Testnet

| | Value |
|-|-------|
| **Package ID** | `0x65ace09e971654cf69c60bbbe47171df92eb7f6351c5b0d5fd989e3723e16116` |
| **Treasury** | `0x8fade1ccdeb5c1164ca10d70b3ab491e8aff0bcb3ee064310e2203b4957e6403` |
| **MarketRegistry** | `0x022abb8fd84902368d0d5307f0fd3ad8f618b96701c8d372e4e6c4d0d42e6afe` |
| **AdminCap** | `0x60bf3637ad36e1342393252ba56a8fa38cc2f97a7c85a7a18de1526ee4761b76` |

Transaction: `4E817wXCdjLbhv95YedZaiEk7vvaJfx8zpgT1mkTZw6o`

### End-to-End Test

Successfully tested the full oracle loop on testnet:
1. Created market: "Will there be any gate jumps in the next 6 minutes?" (JumpEvent, threshold=1)
2. Placed YES bet
3. Indexer queried Sui GraphQL, counted **63 JumpEvents**
4. Auto-resolved as YES (63 >= 1), tx: `GQRmpMekRbUdj4pKpCYkEiQHkenSusiE3D8jiHXYm3fY`

## Quick Start

Create a market (KILLMAIL type, system 42, threshold 20):

```bash
sui client call \
  --package 0x65ace09e971654cf69c60bbbe47171df92eb7f6351c5b0d5fd989e3723e16116 \
  --module augury \
  --function create_market \
  --args \
    0x022abb8fd84902368d0d5307f0fd3ad8f618b96701c8d372e4e6c4d0d42e6afe \
    "Will System 42 see 20+ kills?" \
    1 \
    42 \
    20 \
    $(echo "$(date +%s)000 + 7200000" | bc) \
    0x6 \
  --gas-budget 10000000
```

Place a YES bet:

```bash
sui client call \
  --package 0x65ace09e971654cf69c60bbbe47171df92eb7f6351c5b0d5fd989e3723e16116 \
  --module augury \
  --function place_bet \
  --args <MARKET_ID> 1 <COIN_ID> 0x6 \
  --gas-budget 10000000
```

## Event Indexer / Auto-Resolver

The `indexer/` directory contains a TypeScript service that closes the oracle loop:

1. Queries EVE Frontier events (KillmailCreatedEvent, JumpEvent, ItemDestroyedEvent) from Sui GraphQL
2. Reads all open markets past their deadline
3. Counts events matching each market's criteria (event type + target system)
4. Submits `resolve(observed_count)` transactions automatically

```bash
cd indexer
npm install
cp .env.example .env   # Edit with your ADMIN_PRIVATE_KEY
npx tsx resolve.ts      # Single pass
npx tsx watch.ts        # Continuous (every 30s)
```

## Tests

29 unit tests covering access control, payout math, edge cases, EVE event types, input validation, and Table indexing.

```bash
cd contracts/augury && sui move test
```

## Category

- **Creative** -- The only prediction market in 68 submissions. "On-chain game events as trustless oracle" is a genuinely novel insight.
- **Technical Implementation** -- Off-chain indexing to on-chain settlement with cursor-based GraphQL pagination, the proven S-tier architecture pattern.
- **Utility** -- Prediction markets are information aggregation mechanisms. When players bet on EVE outcomes, the odds become the server's most accurate early warning system for wars, economic shifts, and strategic opportunities.

## License

MIT

---

Built for the 2026 EVE Frontier x Sui Hackathon
