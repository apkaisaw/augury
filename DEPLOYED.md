# Augury - Deployment Record (v2)

## Network

Sui Testnet

## Transaction

- **Tx Digest:** `3Q5wuWAHngEETMrFYq9Q5KXPik51EXC64zVfENs4Njoo`
- **Deployer:** `0xc8ac0013ed934bddffda62301c1af9f1e72b9a7afd1aeb55d2561471a8d68bfd`

## Package

- **Package ID:** `0xb4d66c40073c8ad61df419386645711d5ae2051f96f2e4a0ddaffbc38580b933`
- **Module:** `augury`

## Key Objects

| Object | Type | ID | Owner |
|--------|------|----|-------|
| Treasury | `augury::Treasury` | `0x2d82084d3909e01f03d91df30b1062a82295013586ffdbc9f6817810a40bf72a` | Shared |
| MarketRegistry | `augury::MarketRegistry` | `0xf53b284bc6e4b4ec7934feeb380dac85130549e4efb842f541ebe2500063e666` | Shared |
| AdminCap | `augury::AdminCap` | `0x8d675f94c0b2e810d7af53b68b49ac68be0e51b7ffd5d8caa4d3780e7f2e9781` | Deployer |
| UpgradeCap | `package::UpgradeCap` | `0xfe32643f7fb17830291c037555c9c58b5f52ffd4e979f435713c7ab934358481` | Deployer |

## Previous Deployment (v1 - deprecated)

- **Package ID:** `0x3fe621a56d198c1cc8b9b57aa2037a53dd026f0b1419383d564c6e2fe6ac5357`
- **Tx:** `41pTGxxE58oVmX6kFnRG3yRwSdKp4y6MUvB3GVJJBeyD`

## EVE Event Type Constants

| Constant | Value | EVE Source Event |
|----------|-------|-----------------|
| `EVENT_KILLMAIL` | 1 | `KillmailCreatedEvent` |
| `EVENT_JUMP` | 2 | `JumpEvent` |
| `EVENT_ITEM_DESTROY` | 3 | `ItemDestroyedEvent` |

## Contract Functions

| Function | Description | Access |
|----------|-------------|--------|
| `create_market` | Create a prediction market with EVE event type (1/2/3), target system, threshold, deadline | Anyone |
| `place_bet` | Bet YES (1) or NO (2) with SUI coins | Anyone (before deadline) |
| `resolve` | Submit observed event count; outcome auto-determined vs threshold | AdminCap holder only (after deadline) |
| `claim` | Claim winnings from a resolved market | Position owner only (winning side) |

## Events

- `MarketCreated` - market_id, question, event_type, target_system_id, threshold, deadline_ms, creator
- `BetPlaced` - market_id, position_id, side, amount, player
- `MarketResolved` - market_id, outcome, observed_count
- `WinningsClaimed` - market_id, position_id, payout, player

## Settlement Architecture

```
EVE Frontier on-chain events (KillmailCreatedEvent, JumpEvent, ItemDestroyedEvent)
  -> Off-chain indexer queries via GraphQL
  -> Counts events matching market criteria (event_type + target_system_id)
  -> AdminCap holder submits resolve(observed_count) on-chain
  -> Contract compares observed_count >= threshold -> YES or NO
  -> Winners call claim() to receive proportional payout (minus 2% protocol fee)
```

## Tests

29 tests covering: access control, payout math, edge cases, EVE event types, input validation, Table indexing.
