/// Read Market objects from the Sui chain using JSON RPC.

import { SuiClient, SuiObjectResponse } from "@mysten/sui/client";
import { config } from "./config.js";

export interface MarketData {
  objectId: string;
  question: string;
  eventType: number;
  targetSystemId: number;
  threshold: number;
  deadlineMs: number;
  status: number;
  resolvedCount: number;
  yesPool: number;
  noPool: number;
}

const STATUS_OPEN = 0;

/// Fetch all Market objects by querying MarketCreated events from our package.
export async function fetchAllMarkets(client: SuiClient): Promise<MarketData[]> {
  // Query MarketCreated events to discover all market IDs
  const marketIds: string[] = [];

  let cursor: { txDigest: string; eventSeq: string } | null | undefined = undefined;
  let hasNext = true;

  while (hasNext) {
    const page = await client.queryEvents({
      query: {
        MoveEventType: `${config.packageId}::augury::MarketCreated`,
      },
      cursor: cursor ?? undefined,
      limit: 50,
      order: "ascending",
    });

    for (const event of page.data) {
      const json = event.parsedJson as { market_id?: string };
      if (json.market_id) {
        marketIds.push(json.market_id);
      }
    }

    hasNext = page.hasNextPage;
    cursor = page.nextCursor;
  }

  if (marketIds.length === 0) return [];

  // Batch read market objects
  const objects = await client.multiGetObjects({
    ids: marketIds,
    options: { showContent: true },
  });

  return objects
    .map((obj) => parseMarketObject(obj))
    .filter((m): m is MarketData => m !== null);
}

/// Fetch markets that are past deadline and still open (need resolution).
export async function fetchResolvableMarkets(client: SuiClient): Promise<MarketData[]> {
  const markets = await fetchAllMarkets(client);
  const now = Date.now();

  return markets.filter(
    (m) => m.status === STATUS_OPEN && now >= m.deadlineMs,
  );
}

function parseMarketObject(obj: SuiObjectResponse): MarketData | null {
  const content = obj.data?.content;
  if (content?.dataType !== "moveObject") return null;

  const fields = content.fields as Record<string, unknown>;
  if (!fields) return null;

  // question is stored as vector<u8>, which Sui returns as a base64 or array
  let question = "";
  const qRaw = fields.question;
  if (Array.isArray(qRaw)) {
    question = String.fromCharCode(...(qRaw as number[]));
  } else if (typeof qRaw === "string") {
    // Could be base64 or UTF-8
    try {
      question = Buffer.from(qRaw, "base64").toString("utf-8");
    } catch {
      question = qRaw;
    }
  }

  return {
    objectId: obj.data!.objectId,
    question,
    eventType: Number(fields.event_type ?? 0),
    targetSystemId: Number(fields.target_system_id ?? 0),
    threshold: Number(fields.threshold ?? 0),
    deadlineMs: Number(fields.deadline_ms ?? 0),
    status: Number(fields.status ?? 0),
    resolvedCount: Number(fields.resolved_count ?? 0),
    yesPool: Number(
      (fields.yes_pool as { value?: string })?.value ?? 0,
    ),
    noPool: Number(
      (fields.no_pool as { value?: string })?.value ?? 0,
    ),
  };
}
