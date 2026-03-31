#!/usr/bin/env tsx
/// Single-pass resolver: scan all markets, resolve any that are past deadline.
/// Usage: npx tsx indexer/resolve.ts

import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { config } from "./config.js";
import { fetchResolvableMarkets, fetchAllMarkets } from "./markets.js";
import { processMarket } from "./settler.js";

async function main() {
  console.log("=== Augury Resolver (single pass) ===\n");
  console.log(`Package:  ${config.packageId.slice(0, 16)}...`);
  console.log(`Registry: ${config.marketRegistryId.slice(0, 16)}...`);
  console.log(`AdminCap: ${config.adminCapId.slice(0, 16)}...`);
  console.log(`World:    ${config.worldPackageId.slice(0, 16)}...`);

  const client = new SuiClient({ url: config.suiRpcUrl });
  const keypair = Ed25519Keypair.fromSecretKey(config.adminPrivateKey);
  const address = keypair.getPublicKey().toSuiAddress();
  console.log(`Resolver: ${address}\n`);

  // Show all markets
  const allMarkets = await fetchAllMarkets(client);
  console.log(`Total markets: ${allMarkets.length}`);

  // Find resolvable markets
  const resolvable = await fetchResolvableMarkets(client);
  console.log(`Resolvable (past deadline, still open): ${resolvable.length}`);

  if (resolvable.length === 0) {
    console.log("\nNo markets to resolve. Done.");
    return;
  }

  let resolved = 0;
  let failed = 0;

  for (const market of resolvable) {
    const ok = await processMarket(client, keypair, market);
    if (ok) resolved++;
    else failed++;
  }

  console.log(`\n=== Done: ${resolved} resolved, ${failed} failed ===`);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
