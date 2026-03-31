/// GraphQL event fetching — adapted from Aegis Stack's sui_graphql.py pattern.
/// Uses cursor-based pagination for incremental polling.

import { config } from "./config.js";

const EVENTS_QUERY = `
query FetchEvents($eventType: String!, $first: Int!, $after: String) {
  events(
    filter: { type: $eventType }
    first: $first
    after: $after
  ) {
    nodes {
      contents { json }
      sender { address }
      timestamp
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
`;

export interface EventNode {
  contents: { json: Record<string, unknown> };
  sender: { address: string };
  timestamp: string;
}

interface FetchResult {
  events: EventNode[];
  endCursor: string | null;
}

/// Fetch paginated events of a given type from Sui GraphQL.
/// Returns events and the last cursor for incremental polling.
export async function fetchEvents(
  eventType: string,
  afterCursor: string | null = null,
  maxPages = 10,
  pageSize = 50,
): Promise<FetchResult> {
  const allEvents: EventNode[] = [];
  let cursor = afterCursor;

  for (let page = 0; page < maxPages; page++) {
    const variables: Record<string, unknown> = {
      eventType,
      first: pageSize,
    };
    if (cursor) variables.after = cursor;

    try {
      const response = await fetch(config.graphqlUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: EVENTS_QUERY, variables }),
      });

      if (!response.ok) {
        console.error(`GraphQL HTTP ${response.status}`);
        break;
      }

      const data = (await response.json()) as {
        errors?: unknown[];
        data?: {
          events?: {
            nodes?: EventNode[];
            pageInfo?: { hasNextPage?: boolean; endCursor?: string | null };
          };
        };
      };

      if (data.errors) {
        console.error("GraphQL errors:", data.errors);
        break;
      }

      const eventsData = data.data?.events;
      const nodes = eventsData?.nodes ?? [];
      allEvents.push(...nodes);

      const pageInfo = eventsData?.pageInfo;
      cursor = pageInfo?.endCursor ?? null;
      if (!pageInfo?.hasNextPage) break;
    } catch (err) {
      console.error("GraphQL fetch error:", err);
      break;
    }
  }

  return { events: allEvents, endCursor: cursor };
}

/// Extract solar_system_id from an event's JSON contents.
/// Different event types store it in different fields.
export function extractSystemId(eventType: number, json: Record<string, unknown>): number {
  if (eventType === 1) {
    // KillmailCreatedEvent has solar_system_id as a TenantItemId struct
    const sysId = json.solar_system_id as { item_id?: string } | undefined;
    return Number(sysId?.item_id ?? 0);
  }
  if (eventType === 2) {
    // JumpEvent — look for smart_gate_id or solar_system_id
    const sysId = json.solar_system_id as { item_id?: string } | undefined;
    return Number(sysId?.item_id ?? 0);
  }
  if (eventType === 3) {
    // ItemDestroyedEvent — may not have system info, return 0
    return 0;
  }
  return 0;
}
