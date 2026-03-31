#!/usr/bin/env tsx
/// Continuous watcher: poll every N seconds, auto-resolve markets past deadline.
/// Usage: npx tsx indexer/watch.ts

import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { config } from "./config.js";
import { fetchResolvableMarkets } from "./markets.js";
import { processMarket } from "./settler.js";

async function runCycle(client: SuiClient, keypair: Ed25519Keypair, cycle: number) {
  const now = new Date().toISOString().slice(11, 19);
  console.log(`\n--- Cycle ${cycle} [${now}] ---`);

  const resolvable = await fetchResolvableMarkets(client);
  if (resolvable.length === 0) {
    console.log("No markets to resolve.");
    return;
  }

  console.log(`Found ${resolvable.length} resolvable market(s)`);
  for (const market of resolvable) {
    await processMarket(client, keypair, market);
  }
}

async function main() {
  const intervalMs = config.pollIntervalSeconds * 1000;

  console.log("=== Augury Watcher ===");
  console.log(`Package:  ${config.packageId.slice(0, 16)}...`);
  console.log(`Interval: ${config.pollIntervalSeconds}s`);

  const client = new SuiClient({ url: config.suiRpcUrl });
  const keypair = Ed25519Keypair.fromSecretKey(config.adminPrivateKey);
  const address = keypair.getPublicKey().toSuiAddress();
  console.log(`Resolver: ${address}`);
  console.log("Press Ctrl+C to stop.\n");

  let cycle = 0;
  while (true) {
    cycle++;
    try {
      await runCycle(client, keypair, cycle);
    } catch (err) {
      console.error("Cycle error (will retry):", err);
    }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
