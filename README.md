# Augury

A trustless prediction market for EVE Frontier where on-chain game events serve as the oracle.

Players bet SUI on future in-game outcomes — kills, gate traffic, item destruction — and settlements are resolved automatically from verifiable chain data. No external oracle needed.

## How It Works

1. A market is created with a question, target event type, and deadline
2. Players buy YES or NO shares with SUI
3. At resolution time, on-chain events (KillMail, JumpEvent, etc.) determine the outcome
4. Winners split the pool proportionally

## Tech Stack

- **Contracts:** Sui Move
- **Frontend:** React + TypeScript + Vite
- **Sui Integration:** @mysten/dapp-kit + @evefrontier/dapp-kit

## License

MIT
