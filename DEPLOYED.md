# Augury - Deployment Record (v3)

## Network

Sui Testnet

## Transaction

- **Tx Digest:** `4E817wXCdjLbhv95YedZaiEk7vvaJfx8zpgT1mkTZw6o`
- **Deployer:** `0xc8ac0013ed934bddffda62301c1af9f1e72b9a7afd1aeb55d2561471a8d68bfd`

## Package

- **Package ID:** `0x65ace09e971654cf69c60bbbe47171df92eb7f6351c5b0d5fd989e3723e16116`
- **Module:** `augury`

## Key Objects

| Object | Type | ID | Owner |
|--------|------|----|-------|
| Treasury | `augury::Treasury` | `0x8fade1ccdeb5c1164ca10d70b3ab491e8aff0bcb3ee064310e2203b4957e6403` | Shared |
| MarketRegistry | `augury::MarketRegistry` | `0x022abb8fd84902368d0d5307f0fd3ad8f618b96701c8d372e4e6c4d0d42e6afe` | Shared |
| AdminCap | `augury::AdminCap` | `0x60bf3637ad36e1342393252ba56a8fa38cc2f97a7c85a7a18de1526ee4761b76` | Deployer |
| UpgradeCap | `package::UpgradeCap` | `0xfdcfd7cc21b4a98e22f9157bce7316ad3e57182c4636ca5e22b47bb2384633d3` | Deployer |

## Previous Deployments

- **v2 Package ID:** `0xb4d66c40073c8ad61df419386645711d5ae2051f96f2e4a0ddaffbc38580b933`
- **v1 Package ID:** `0x3fe621a56d198c1cc8b9b57aa2037a53dd026f0b1419383d564c6e2fe6ac5357`

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
  -> Off-chain indexer queries via Sui GraphQL (cursor-based pagination)
  -> Counts events matching market criteria (event_type + target_system_id)
  -> AdminCap holder submits resolve(observed_count) on-chain
  -> Contract compares observed_count >= threshold -> YES or NO
  -> Winners call claim() to receive proportional payout (minus 2% protocol fee)
```

## End-to-End Test (2026-03-31)

Successfully tested the full oracle loop:
1. Created market: "Will there be any gate jumps in the next 6 minutes?" (JumpEvent, threshold=1)
2. Placed YES bet (0.09 SUI)
3. Indexer queried Sui GraphQL, found **63 JumpEvents**
4. Auto-resolved as YES (63 >= 1)
5. Resolve tx: `GQRmpMekRbUdj4pKpCYkEiQHkenSusiE3D8jiHXYm3fY`

## Tests

29 unit tests covering: access control, payout math, edge cases, EVE event types, input validation, Table indexing.
