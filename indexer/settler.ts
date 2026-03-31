/// Settlement logic: count matching EVE events for a market, then submit resolve().

import { SuiClient } from "@mysten/sui/client";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { config, EVE_EVENT_TYPES, EVENT_TYPE_NAMES, CLOCK_ID } from "./config.js";
import { fetchEvents, extractSystemId, type EventNode } from "./graphql.js";
import type { MarketData } from "./markets.js";

/// Count EVE events matching a market's criteria.
/// Fetches events of the market's event_type, filters by target_system_id
/// (if non-zero), and counts those within the market's time window.
export async function countMatchingEvents(
  market: MarketData,
  afterCursor: string | null = null,
): Promise<{ count: number; cursor: string | null }> {
  const eventTypeStr = EVE_EVENT_TYPES[market.eventType];
  if (!eventTypeStr) {
    console.warn(
      `  Unknown event type ${market.eventType}, skipping`,
    );
    return { count: 0, cursor: null };
  }

  const { events, endCursor } = await fetchEvents(
    eventTypeStr,
    afterCursor,
    50, // max pages
    50, // page size
  );

  let count = 0;
  for (const event of events) {
    const json = event.contents.json;

    // Filter by target system (0 = any system)
    if (market.targetSystemId !== 0) {
      const systemId = extractSystemId(market.eventType, json);
      if (systemId !== market.targetSystemId) continue;
    }

    // Filter by time window: events before the market deadline
    const eventTime = new Date(event.timestamp).getTime();
    if (eventTime <= market.deadlineMs) {
      count++;
    }
  }

  return { count, cursor: endCursor };
}

/// Submit resolve() transaction for a market.
export async function resolveMarket(
  client: SuiClient,
  keypair: Ed25519Keypair,
  market: MarketData,
  observedCount: number,
): Promise<string> {
  const tx = new Transaction();

  tx.moveCall({
    target: `${config.packageId}::augury::resolve`,
    arguments: [
      tx.object(config.adminCapId),
      tx.object(market.objectId),
      tx.pure.u64(observedCount),
      tx.object(CLOCK_ID),
    ],
  });

  const result = await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
    options: { showEffects: true },
  });

  const status = result.effects?.status?.status;
  if (status !== "success") {
    throw new Error(
      `resolve() failed: ${JSON.stringify(result.effects?.status)}`,
    );
  }

  return result.digest;
}

/// Process a single market: count events, resolve if needed.
export async function processMarket(
  client: SuiClient,
  keypair: Ed25519Keypair,
  market: MarketData,
): Promise<boolean> {
  const eventName = EVENT_TYPE_NAMES[market.eventType] ?? "Unknown";
  console.log(`\n  Market: ${market.objectId.slice(0, 16)}...`);
  console.log(`  Question: ${market.question}`);
  console.log(
    `  Type: ${eventName} | System: ${market.targetSystemId || "any"} | Threshold: ${market.threshold}`,
  );
  console.log(
    `  Pools: YES=${market.yesPool} NO=${market.noPool}`,
  );

  // Count matching events
  const { count } = await countMatchingEvents(market);
  const outcome = count >= market.threshold ? "YES" : "NO";
  console.log(
    `  Observed: ${count} events | Threshold: ${market.threshold} | Outcome: ${outcome}`,
  );

  // Submit resolve transaction
  try {
    const digest = await resolveMarket(client, keypair, market, count);
    console.log(`  Resolved! Tx: ${digest}`);
    return true;
  } catch (err) {
    console.error(`  Failed to resolve:`, err);
    return false;
  }
}
