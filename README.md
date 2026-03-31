# Augury

A trustless prediction market for EVE Frontier. On-chain game events are the oracle.

## Problem

EVE Frontier generates thousands of verifiable on-chain events every day -- kills, gate jumps, item destruction -- but there is no mechanism for players to aggregate collective intelligence around these events. Traditional prediction markets require external oracles to determine outcomes, introducing trust assumptions and single points of failure.

## Solution

Augury turns EVE Frontier's chain data into a trustless oracle. Players stake SUI on predictions about real in-game outcomes ("Will System X see >20 kills this week?"). Settlement is determined entirely by on-chain event counts that anyone can independently verify via GraphQL. No external oracle, no dispute resolution, no trust required -- the chain data IS the truth.

## How It Works

```
1. Creator publishes a market (question + EVE event type + target system + threshold + deadline)
2. Players stake SUI on YES or NO
3. Deadline passes
4. Resolver indexes on-chain EVE events, submits observed count
5. Contract auto-settles: observed_count >= threshold -> YES wins, otherwise NO wins
6. Winners claim proportional payout (minus 2% protocol fee)
```

## Technical Architecture

### Contract Objects

| Object | Type | Description |
|--------|------|-------------|
| `Market` | Shared | Prediction market with YES/NO pools, deadline, threshold, event type |
| `Position` | Owned | Player's stake in a market (side, amount, claimed status) |
| `MarketRegistry` | Shared | Table-indexed registry of all markets |
| `Treasury` | Shared | Protocol fee collection |
| `AdminCap` | Owned | Authorizes the off-chain resolver to submit outcomes |

### Functions

| Function | Access | Description |
|----------|--------|-------------|
| `create_market` | Anyone | Create a market for a specific EVE event type |
| `place_bet` | Anyone (before deadline) | Stake SUI on YES or NO |
| `resolve` | AdminCap holder (after deadline) | Submit observed event count; outcome auto-determined |
| `claim` | Position owner (winning side) | Withdraw proportional share of the pool |

### Events

| Event | Emitted When |
|-------|-------------|
| `MarketCreated` | New market published |
| `BetPlaced` | Player stakes on a market |
| `MarketResolved` | Outcome determined from observed event count |
| `WinningsClaimed` | Winner withdraws payout |

### Settlement Architecture

```
EVE Frontier chain (KillmailCreatedEvent, JumpEvent, ItemDestroyedEvent)
    |
    v
Off-chain indexer (GraphQL query: count events matching market criteria)
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

This is the same architecture pattern used by Aegis Stack (S-tier in the first hackathon wave): off-chain indexing of on-chain facts, submitted as verifiable oracle data. The difference is that Augury uses this pattern for prediction markets rather than reputation scoring.

## Sui Features Used

| Feature | Usage |
|---------|-------|
| **Clock** | Deadline enforcement for betting and resolution |
| **Events** | 4 event types for frontend indexing and off-chain tracking |
| **Table** | Market registry with on-chain enumeration by index |
| **Capabilities** | AdminCap gates resolution to authorized resolver |
| **Coin / Balance** | SUI staking pools, proportional payout math, fee extraction |
| **Shared Objects** | Market, Treasury, Registry -- concurrent multi-player access |

## EVE Frontier Integration

### Supported Event Types

| Constant | Value | EVE Source | Example Market |
|----------|-------|-----------|----------------|
| `EVENT_KILLMAIL` | 1 | `KillmailCreatedEvent` | "Will System 30003489 see >20 kills this week?" |
| `EVENT_JUMP` | 2 | `JumpEvent` | "Will Gate Y process >100 jumps tomorrow?" |
| `EVENT_ITEM_DESTROY` | 3 | `ItemDestroyedEvent` | "Will >50% of rare ore be destroyed in 7 days?" |

### Oracle Loop

Each market stores `event_type`, `target_system_id`, and `threshold`. The off-chain resolver queries the corresponding EVE events via GraphQL, counts matches within the market's time window, and submits the observed count. The contract then compares against the threshold to determine the outcome. Anyone can run the same query to verify.

## Deployed on Testnet

| | Value |
|-|-------|
| **Package ID** | `0x65ace09e971654cf69c60bbbe47171df92eb7f6351c5b0d5fd989e3723e16116` |
| **Treasury** | `0x8fade1ccdeb5c1164ca10d70b3ab491e8aff0bcb3ee064310e2203b4957e6403` |
| **MarketRegistry** | `0x022abb8fd84902368d0d5307f0fd3ad8f618b96701c8d372e4e6c4d0d42e6afe` |
| **AdminCap** | `0x60bf3637ad36e1342393252ba56a8fa38cc2f97a7c85a7a18de1526ee4761b76` |

Transaction: `4E817wXCdjLbhv95YedZaiEk7vvaJfx8zpgT1mkTZw6o`

## Quick Start

Create a market (KILLMAIL type, system 42, threshold 20, deadline 2h from now):

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

Place a YES bet (1 SUI):

```bash
sui client call \
  --package 0x65ace09e971654cf69c60bbbe47171df92eb7f6351c5b0d5fd989e3723e16116 \
  --module augury \
  --function place_bet \
  --args <MARKET_ID> 1 <COIN_ID> 0x6 \
  --gas-budget 10000000
```

Resolve a market (AdminCap holder, after deadline):

```bash
sui client call \
  --package 0x65ace09e971654cf69c60bbbe47171df92eb7f6351c5b0d5fd989e3723e16116 \
  --module augury \
  --function resolve \
  --args \
    0x60bf3637ad36e1342393252ba56a8fa38cc2f97a7c85a7a18de1526ee4761b76 \
    <MARKET_ID> \
    25 \
    0x6 \
  --gas-budget 10000000
```

## Event Indexer / Auto-Resolver

The `indexer/` directory contains a TypeScript service that closes the oracle loop:

1. Queries EVE Frontier events (KillmailCreatedEvent, JumpEvent, ItemDestroyedEvent) from Sui GraphQL
2. Reads all open markets past their deadline
3. Counts events matching each market's criteria (event type + target system)
4. Submits `resolve(observed_count)` transactions automatically

### Setup

```bash
cd indexer
npm install
cp .env.example .env
# Edit .env with your ADMIN_PRIVATE_KEY and WORLD_PACKAGE_ID
```

### Run

```bash
# Single pass: scan and resolve all eligible markets
npx tsx resolve.ts

# Continuous: poll every 30 seconds
npx tsx watch.ts
```

### Architecture

The indexer follows the same pattern as Aegis Stack (S-tier): cursor-based incremental polling of Sui GraphQL events, with stateless resolution transactions. It uses the standard `events(filter: { type: $eventType })` query with `first/after` pagination.

## Tests

29 unit tests covering access control, payout math, edge cases, EVE event types, input validation, and Table indexing.

```bash
cd contracts/augury && sui move test
```

## Category

- **Creative** -- "On-chain game events as trustless oracle" is a novel architectural insight, not a port of an existing concept
- **Technical Implementation** -- Off-chain indexing to on-chain settlement, the proven S-tier pattern
- **Utility** -- Prediction markets are information aggregation mechanisms; odds become the most accurate early warning system for wars and economic shifts across the server

## License

MIT

---

Built for the 2026 EVE Frontier x Sui Hackathon
