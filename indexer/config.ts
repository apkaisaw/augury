import "dotenv/config";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required env var: ${name}`);
  return value;
}

export const config = {
  adminPrivateKey: requireEnv("ADMIN_PRIVATE_KEY"),
  packageId: requireEnv("PACKAGE_ID"),
  marketRegistryId: requireEnv("MARKET_REGISTRY_ID"),
  adminCapId: requireEnv("ADMIN_CAP_ID"),
  worldPackageId: requireEnv("WORLD_PACKAGE_ID"),
  suiRpcUrl: process.env.SUI_RPC_URL || "https://fullnode.testnet.sui.io:443",
  graphqlUrl: process.env.SUI_GRAPHQL_URL || "https://graphql.testnet.sui.io/graphql",
  pollIntervalSeconds: Number(process.env.POLL_INTERVAL_SECONDS || "30"),
};

// EVE event type → fully qualified Sui event type string
// Format: {WORLD_PACKAGE_ID}::module::EventName
export const EVE_EVENT_TYPES: Record<number, string> = {
  1: `${config.worldPackageId}::killmail::KillmailCreatedEvent`,
  2: `${config.worldPackageId}::gate::JumpEvent`,
  3: `${config.worldPackageId}::inventory::ItemDestroyedEvent`,
};

export const EVENT_TYPE_NAMES: Record<number, string> = {
  1: "KillmailCreatedEvent",
  2: "JumpEvent",
  3: "ItemDestroyedEvent",
};

export const CLOCK_ID = "0x0000000000000000000000000000000000000000000000000000000000000006";
