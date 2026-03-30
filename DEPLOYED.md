# Augury - Deployment Record

## Network

Sui Testnet

## Transaction

- **Tx Digest:** `41pTGxxE58oVmX6kFnRG3yRwSdKp4y6MUvB3GVJJBeyD`
- **Deployer:** `0xc8ac0013ed934bddffda62301c1af9f1e72b9a7afd1aeb55d2561471a8d68bfd`

## Package

- **Package ID:** `0x3fe621a56d198c1cc8b9b57aa2037a53dd026f0b1419383d564c6e2fe6ac5357`
- **Module:** `augury`

## Key Objects

| Object | Type | ID | Owner |
|--------|------|----|-------|
| Treasury | `augury::Treasury` | `0x16e3333cdbd06efab2637c9b958168f2dc9d53c0261a6e5875cb2267ec813680` | Shared |
| MarketRegistry | `augury::MarketRegistry` | `0xe6e1b07d95fad05761e84b34847c260135f213481e4fff73ff38fc5d15a16c56` | Shared |
| AdminCap | `augury::AdminCap` | `0xb81de8f8be6a77a2f30d82263e11e47cd651304020193213c614e0081dcebb57` | Deployer |
| UpgradeCap | `package::UpgradeCap` | `0xa9359c3ae85d10bb53843f4c4d79b7961bc2e81288ceba974198dc938c0584c8` | Deployer |

## Contract Functions

| Function | Description | Access |
|----------|-------------|--------|
| `create_market` | Create a prediction market with question, event type, threshold, deadline | Anyone |
| `place_bet` | Bet YES (1) or NO (2) with SUI coins | Anyone (before deadline) |
| `resolve` | Submit outcome after deadline | AdminCap holder only |
| `claim` | Claim winnings from a resolved market | Winning position holders |

## Events

- `MarketCreated` - emitted when a new market is created
- `BetPlaced` - emitted when a bet is placed
- `MarketResolved` - emitted when a market is resolved (YES=1, NO=2)
- `WinningsClaimed` - emitted when a winner claims their payout

## Settlement Architecture

```
EVE Frontier on-chain events (KillMail, JumpEvent, etc.)
  -> Off-chain indexer queries via GraphQL
  -> Counts events matching market criteria
  -> AdminCap holder submits resolve(outcome) on-chain
  -> Winners call claim() to receive proportional payout (minus 2% fee)
```
