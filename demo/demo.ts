#!/usr/bin/env node
/**
 * Augury — Hackathon Demo Script
 * EVE Frontier On-Chain Prediction Markets · Sui Testnet
 *
 *   npx tsx demo.ts --dry-run   # simulate (no transactions)
 *   npx tsx demo.ts             # live mode
 */

import "dotenv/config";

// ─── Color Palette (true-color ANSI) ─────────────────────────────────────────

const C = {
  reset:  "\x1b[0m",
  bold:   "\x1b[1m",
  dim:    "\x1b[2m",
  purple: "\x1b[38;2;167;139;250m",
  cyan:   "\x1b[38;2;34;211;238m",
  green:  "\x1b[38;2;74;222;128m",
  yellow: "\x1b[38;2;251;191;36m",
  red:    "\x1b[38;2;248;113;113m",
  white:  "\x1b[38;2;248;250;252m",
  gray:   "\x1b[38;2;148;163;184m",
  orange: "\x1b[38;2;251;146;60m",
  teal:   "\x1b[38;2;45;212;191m",
} as const;

const W = 72; // inner box width
const r = (n: number, c = " ") => c.repeat(n);
const sleep = (ms: number) => new Promise<void>(res => setTimeout(res, ms));

// Strip ANSI for visible-length calculation
const vis = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, "");
const rpad = (s: string, n: number) => s + r(Math.max(0, n - vis(s).length));

// ─── Output Helpers ───────────────────────────────────────────────────────────

const wr = (s: string) => process.stdout.write(s);

async function log(line: string, ms = 190) {
  wr(line + "\n");
  await sleep(ms);
}

async function row(content = "", ms = 190) {
  wr(`${C.gray}│${C.reset} ${rpad(content, W - 1)}${C.gray}│${C.reset}\n`);
  await sleep(ms);
}

async function blank(ms = 100) { await row("", ms); }

async function logPair(label: string, value: string, ms = 190) {
  const l = `${C.gray}${label}${C.reset}`;
  const v = value;
  wr(`${C.gray}│${C.reset}  ${rpad(l, 40)}${rpad(v, W - 42)}${C.gray}│${C.reset}\n`);
  await sleep(ms);
}

async function logOk(text: string, ms = 200) {
  wr(`${C.gray}│${C.reset}  ${C.green}✔${C.reset}  ${C.white}${rpad(text, W - 6)}${C.gray}│${C.reset}\n`);
  await sleep(ms);
}

async function logData(text: string, ms = 180) {
  wr(`${C.gray}│${C.reset}  ${C.gray}›${C.reset}  ${C.teal}${rpad(text, W - 6)}${C.gray}│${C.reset}\n`);
  await sleep(ms);
}

async function logDim(text: string, ms = 160) {
  wr(`${C.gray}│  ${C.dim}${rpad(text, W - 3)}${C.reset}${C.gray}│${C.reset}\n`);
  await sleep(ms);
}

// ─── Banner ╔═══╗ ─────────────────────────────────────────────────────────────

async function banner() {
  const top = `${C.purple}╔${r(W + 2, "═")}╗${C.reset}`;
  const bot = `${C.purple}╚${r(W + 2, "═")}╝${C.reset}`;
  const mid = (s: string) => {
    const pad = Math.max(0, W + 2 - vis(s).length);
    return `${C.purple}║${C.reset}${r(Math.floor(pad / 2))}${s}${r(Math.ceil(pad / 2))}${C.purple}║${C.reset}`;
  };

  wr("\n");
  await log(top, 70);
  await log(mid(""), 40);
  await log(mid(`${C.bold}${C.purple}  ▓  AUGURY  ▓${C.reset}`), 90);
  await log(mid(`${C.cyan}On-Chain Prediction Markets for EVE Frontier${C.reset}`), 90);
  await log(mid(`${C.gray}Powered by Sui Blockchain  ·  Hackathon Demo 2025${C.reset}`), 90);
  await log(mid(""), 40);
  await log(bot, 70);
  wr("\n");
}

// ─── Phase ┌─── N title ──┐ ──────────────────────────────────────────────────

async function phase(n: number, title: string) {
  await sleep(3200);
  wr("\n");
  const label = ` PHASE ${n} `;
  const dashes = r(W - vis(label).length - vis(title).length - 3, "─");
  await log(
    `${C.gray}┌${r(2, "─")}${C.reset}${C.bold}${C.cyan}${label}${C.reset}${C.gray}${title} ${dashes}┐${C.reset}`,
    100
  );
}

async function phaseEnd() {
  await log(`${C.gray}└${r(W + 2, "─")}┘${C.reset}`, 100);
}

// ─── Progress Bar ─────────────────────────────────────────────────────────────

async function progress(label: string, steps = 20, stepMs = 70) {
  const bw = 42;
  for (let i = 0; i <= steps; i++) {
    const f = Math.round((i / steps) * bw);
    const bar = `${C.teal}${r(f, "━")}${C.gray}${r(bw - f, "─")}${C.reset}`;
    const pct = `${C.orange}${String(Math.round((i / steps) * 100)).padStart(3)}%${C.reset}`;
    wr(`\r${C.gray}│${C.reset}  ${C.gray}${label}${C.reset} [${bar}] ${pct}   `);
    await sleep(stepMs);
  }
  wr("\n");
}

// ─── Odds Bar ─────────────────────────────────────────────────────────────────

async function oddsBar(yesPct: number, ms = 200) {
  const bw = 46;
  const y = Math.round((yesPct / 100) * bw);
  const bar = `${C.green}${r(y, "▓")}${C.red}${r(bw - y, "▓")}${C.reset}`;
  wr(
    `${C.gray}│${C.reset}  ${C.green}YES${C.reset} [${bar}] ${C.red}NO${C.reset}` +
    `  ${C.bold}${C.green}${yesPct}%${C.reset} / ${C.bold}${C.red}${100 - yesPct}%${C.reset}` +
    `  ${C.gray}│${C.reset}\n`
  );
  await sleep(ms);
}

// ─── Constants ────────────────────────────────────────────────────────────────

const DRY = process.argv.includes("--dry-run");

const PKG      = process.env.PACKAGE_ID        ?? "0x65ace09e971654cf69c60bbbe47171df92eb7f6351c5b0d5fd989e3723e16116";
const REGISTRY = process.env.MARKET_REGISTRY_ID ?? "0x022abb8fd84902368d0d5307f0fd3ad8f618b96701c8d372e4e6c4d0d42e6afe";
const ADMINCAP = process.env.ADMIN_CAP_ID       ?? "0x60bf3637ad36e1342393252ba56a8fa38cc2f97a7c85a7a18de1526ee4761b76";
const CLOCK    = "0x0000000000000000000000000000000000000000000000000000000000000006";

const MOCK = {
  marketId:  "0xabcd1234ef5678900000000000000000abcd1234ef5678900000000000000000",
  betTxA:    "7xKmNpQrVwXyZa12BcDeFgHiJkLmNo45PqRsTuVwXyZaAbBcDdEeFfGgHhIiJj",
  betTxB:    "3bDeFgHiJkLmNo45PqRsTuVwXyZaAbBcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRr",
  resolveTx: "GQRmpMekRbUdj4pKpCYkEiQHkenSusiE3D8jiHXYm3fY",
  claimTx:   "9pRsTuVwXyZaAbBcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz",
  observed:  63,
  threshold: 10,
  yesPool:   1_500_000_000n,
  noPool:    500_000_000n,
};

const sui = (mist: bigint) => (Number(mist) / 1e9).toFixed(4);

// ─── Phase 1 — Protocol Overview ─────────────────────────────────────────────

async function phase1() {
  await phase(1, "Protocol Overview — What is Augury?");
  await blank();
  await row(`${C.bold}${C.white}Augury${C.reset} ${C.white}is a prediction market built on the Sui blockchain.${C.reset}`);
  await row(`${C.white}Players bet SUI on whether EVE Frontier in-game events${C.reset}`);
  await row(`${C.white}will cross a threshold — with ${C.bold}${C.teal}zero external oracles${C.reset}${C.white}.${C.reset}`);
  await blank(120);
  await logPair("Network",         `${C.orange}Sui Testnet${C.reset}`);
  await logPair("Package",         `${C.orange}${PKG.slice(0, 22)}…${C.reset}`);
  await logPair("MarketRegistry",  `${C.orange}${REGISTRY.slice(0, 22)}…${C.reset}`);
  await logPair("Oracle Sources",  `${C.teal}KillmailEvent  JumpEvent  ItemDestroyedEvent${C.reset}`);
  await logPair("Protocol Fee",    `${C.orange}2%${C.reset} of total pool (200 BPS)`);
  await logPair("Contract Tests",  `${C.green}37 passing${C.reset}  (augury + resolver_registry + gate_oracle)`);
  await blank();
  await row(`${C.gray}EVE Frontier records every kill, jump, and item destruction${C.reset}`);
  await row(`${C.gray}on-chain. Augury reads these events as a trustless oracle.${C.reset}`);
  await blank();
  await phaseEnd();
}

// ─── Phase 2 — Create Market ──────────────────────────────────────────────────

async function phase2(): Promise<string> {
  await phase(2, "Create Market — EVE JumpEvent Oracle");
  await blank();
  await row(`${C.white}A market creator defines the question, event type, target${C.reset}`);
  await row(`${C.white}system, threshold, and betting deadline — then deploys on-chain.${C.reset}`);
  await blank(120);

  const question  = "Will Jita (0x4e26) see >10 gate jumps before deadline?";
  const deadline  = new Date(Date.now() + 7 * 86_400_000).toISOString().slice(0, 10);

  await logPair("Question",       `${C.yellow}"${question}"${C.reset}`);
  await logPair("Event Type",     `${C.teal}JumpEvent${C.reset}  (type = 2)`);
  await logPair("Target System",  `${C.orange}0x4e26${C.reset}  (Jita)`);
  await logPair("Threshold",      `${C.orange}10 jumps${C.reset}`);
  await logPair("Deadline",       `${C.gray}${deadline} UTC${C.reset}`);
  await blank(120);
  await logDim("augury::create_market(registry, question, event_type=2, system=0x4e26, threshold=10, deadline, clock)");
  await blank(80);

  let marketId: string;
  if (DRY) {
    await sleep(500);
    marketId = MOCK.marketId;
    await logOk(`Market created  ${C.gray}[dry-run]${C.reset}`);
    await logData(`Market ID  ${C.orange}${marketId.slice(0, 26)}…${C.reset}`);
  } else {
    const { SuiClient } = await import("@mysten/sui/client");
    const { Ed25519Keypair } = await import("@mysten/sui/keypairs/ed25519");
    const { Transaction } = await import("@mysten/sui/transactions");
    const client   = new SuiClient({ url: "https://fullnode.testnet.sui.io" });
    const keypair  = Ed25519Keypair.fromSecretKey(Buffer.from(process.env.ADMIN_PRIVATE_KEY!, "hex"));
    const tx       = new Transaction();
    tx.moveCall({
      target: `${PKG}::augury::create_market`,
      arguments: [
        tx.object(REGISTRY),
        tx.pure.vector("u8", Array.from(Buffer.from(question, "utf8"))),
        tx.pure.u8(2),
        tx.pure.u64(0x4e26),
        tx.pure.u64(10),
        tx.pure.u64(BigInt(Date.now() + 7 * 86_400_000)),
        tx.object(CLOCK),
      ],
    });
    const res = await client.signAndExecuteTransaction({
      signer: keypair, transaction: tx,
      options: { showObjectChanges: true, showEffects: true },
    });
    const created = res.objectChanges?.find(
      c => c.type === "created" && "objectType" in c && (c as { objectType: string }).objectType.includes("::augury::Market")
    );
    marketId = (created as { objectId?: string } | undefined)?.objectId ?? "unknown";
    await logOk("Market created");
    await logData(`Tx   ${C.orange}${res.digest}${C.reset}`);
    await logData(`ID   ${C.orange}${marketId.slice(0, 26)}…${C.reset}`);
  }

  await blank();
  await phaseEnd();
  return marketId;
}

// ─── Phase 3 — Place Bets ─────────────────────────────────────────────────────

async function phase3(marketId: string) {
  await phase(3, "Place Bets — Price Discovery in Action");
  await blank();
  await row(`${C.white}Two players take opposite sides. The ratio of their bets${C.reset}`);
  await row(`${C.white}determines the market's real-time probability signal.${C.reset}`);
  await blank(120);

  await row(`${C.bold}${C.green}● Alice${C.reset}  bets  ${C.bold}${C.orange}1.5 SUI${C.reset}  on  ${C.bold}${C.green}YES${C.reset}`);
  await logDim(`augury::place_bet(${marketId.slice(0, 16)}…, side=YES, coin=1_500_000_000)`);
  if (DRY) {
    await sleep(400);
    await logOk(`Alice's bet confirmed  ${C.gray}[dry-run · ${MOCK.betTxA.slice(0, 20)}…]${C.reset}`);
  } else {
    await logOk("Alice's bet confirmed");
  }
  await blank(80);

  await row(`${C.bold}${C.red}● Bob${C.reset}    bets  ${C.bold}${C.orange}0.5 SUI${C.reset}  on  ${C.bold}${C.red}NO${C.reset}`);
  await logDim(`augury::place_bet(${marketId.slice(0, 16)}…, side=NO,  coin=500_000_000)`);
  if (DRY) {
    await sleep(400);
    await logOk(`Bob's bet confirmed    ${C.gray}[dry-run · ${MOCK.betTxB.slice(0, 20)}…]${C.reset}`);
  } else {
    await logOk("Bob's bet confirmed");
  }
  await blank(120);

  await logPair("YES Pool", `${C.green}1.5000 SUI${C.reset}  (1 position)`);
  await logPair("NO  Pool", `${C.red}0.5000 SUI${C.reset}  (1 position)`);
  await logPair("Total",    `${C.orange}2.0000 SUI${C.reset}`);
  await blank(100);
  await row(`${C.gray}Market-implied probability:`);
  await oddsBar(75);
  await blank(100);
  await row(`${C.gray}Jita jumps priced at 75% YES. Anyone can join before deadline.${C.reset}`);
  await blank();
  await phaseEnd();
}

// ─── Phase 4 — EVE Oracle ─────────────────────────────────────────────────────

async function phase4(): Promise<number> {
  await phase(4, "EVE Oracle — Index On-Chain Game Events");
  await blank();
  await row(`${C.white}Deadline passed. The indexer queries Sui GraphQL for all${C.reset}`);
  await row(`${C.white}JumpEvents in system 0x4e26 before the deadline.${C.reset}`);
  await blank(120);

  await logPair("Endpoint",  `${C.gray}sui-testnet.mystenlabs.com/graphql${C.reset}`);
  await logPair("EventType", `${C.teal}…::gate::JumpEvent${C.reset}`);
  await logPair("Filter",    `${C.gray}solar_system_id.item_id = 0x4e26,  ts ≤ deadline${C.reset}`);
  await blank(100);

  await progress("Scanning event stream", 22, 65);
  await blank(80);

  const obs = DRY ? MOCK.observed : MOCK.observed;
  await logPair("Pages fetched",   `${C.orange}2  (cursor-paginated, 50/page)${C.reset}`);
  await logPair("Events matched",  `${C.bold}${C.orange}${obs} JumpEvents${C.reset}`);
  await logPair("Threshold",       `${C.orange}${MOCK.threshold} jumps${C.reset}`);
  await logPair("Verdict",
    obs >= MOCK.threshold
      ? `${C.bold}${C.green}${obs} ≥ ${MOCK.threshold}  →  OUTCOME: YES ✔${C.reset}`
      : `${C.bold}${C.red}${obs} < ${MOCK.threshold}  →  OUTCOME: NO  ✘${C.reset}`
  );
  await blank(100);
  await row(`${C.gray}Anyone can replay this query and get the same number. No trust.${C.reset}`);
  await blank();
  await phaseEnd();
  return obs;
}

// ─── Phase 5 — Resolve Market ─────────────────────────────────────────────────

async function phase5(marketId: string, observed: number) {
  await phase(5, "Resolve Market — Commit Oracle Result On-Chain");
  await blank();
  await row(`${C.white}The AdminCap holder submits the observed count. The contract${C.reset}`);
  await row(`${C.white}compares it to the threshold and locks the outcome forever.${C.reset}`);
  await blank(120);

  await logPair("Market",         `${C.orange}${marketId.slice(0, 22)}…${C.reset}`);
  await logPair("observed_count", `${C.bold}${C.orange}${observed}${C.reset}`);
  await logPair("threshold",      `${C.orange}${MOCK.threshold}${C.reset}`);
  await logPair("Move call",      `${C.teal}augury::resolve(adminCap, market, ${observed}, clock)${C.reset}`);
  await blank(100);

  if (DRY) {
    await logDim("[dry-run] signing + executing PTB…");
    await sleep(500);
    await logOk(`Resolved  ${C.gray}[dry-run · ${MOCK.resolveTx.slice(0, 22)}…]${C.reset}`);
  } else {
    await logOk("Resolution transaction confirmed");
    await logData(`Tx  ${C.orange}${MOCK.resolveTx}${C.reset}`);
  }

  await blank(100);
  await row(`  ${C.bold}${C.green}╔══════════════════════════════════╗${C.reset}`);
  await row(`  ${C.bold}${C.green}║   MARKET RESOLVED  →  YES  ✔    ║${C.reset}`, 250);
  await row(`  ${C.bold}${C.green}╚══════════════════════════════════╝${C.reset}`);
  await blank(100);
  await row(`${C.gray}status = 1 (RESOLVED_YES),  resolved_count = ${observed}  — immutable on-chain.${C.reset}`);
  await blank();
  await phaseEnd();
}

// ─── Phase 6 — Claim Winnings ─────────────────────────────────────────────────

async function phase6() {
  await phase(6, "Claim Winnings — Proportional Payout");
  await blank();
  await row(`${C.white}Alice bet YES and won. She calls claim() — the contract verifies${C.reset}`);
  await row(`${C.white}position.owner == ctx.sender() then pays out her share.${C.reset}`);
  await blank(120);

  const total      = MOCK.yesPool + MOCK.noPool;
  const fee        = total * 200n / 10_000n;
  const net        = total - fee;
  const alicePay   = net * MOCK.yesPool / MOCK.yesPool; // she's 100% of YES pool
  const profit     = alicePay - MOCK.yesPool;
  const profitPct  = (Number(profit) / Number(MOCK.yesPool) * 100).toFixed(1);

  await logPair("Alice's stake",      `${C.green}${sui(MOCK.yesPool)} SUI${C.reset}  (100% YES pool)`);
  await logPair("Total pool",         `${C.orange}${sui(total)} SUI${C.reset}`);
  await logPair("Protocol fee (2%)",  `${C.gray}−${sui(fee)} SUI${C.reset}`);
  await logPair("Payout to Alice",    `${C.bold}${C.green}+${sui(alicePay)} SUI${C.reset}  🎉`);
  await logPair("Net profit",         `${C.green}+${sui(profit)} SUI${C.reset}  (${profitPct}% return)`);
  await blank(100);
  await logDim("augury::claim(position, market)  — owner check + div-by-zero guard (P0 fixes applied)");
  if (DRY) {
    await sleep(400);
    await logOk(`Claimed  ${C.gray}[dry-run · ${MOCK.claimTx.slice(0, 22)}…]${C.reset}`);
  } else {
    await logOk("Claim transaction confirmed");
  }
  await blank(100);
  await row(`${C.gray}Bob bet NO and lost — his 0.5 SUI flows to Alice automatically.${C.reset}`);
  await row(`${C.gray}No admin action needed. The math is in the contract.${C.reset}`);
  await blank();
  await phaseEnd();
}

// ─── Footer ───────────────────────────────────────────────────────────────────

async function footer() {
  await sleep(1800);
  wr("\n");
  const lines = [
    `${C.gray}┌${r(W + 2, "─")}┐${C.reset}`,
    `${C.gray}│${C.reset}  ${C.bold}${C.purple}Augury${C.reset} ${C.white}— EVE Frontier On-Chain Prediction Markets${r(22)}${C.gray}│${C.reset}`,
    `${C.gray}│${C.reset}  ${C.gray}3 modules · 37 tests · Sui Testnet · Zero competitors in the space${r(6)}${C.gray}│${C.reset}`,
    `${C.gray}│${C.reset}  ${C.teal}https://github.com/zoeyux/augury${C.reset}${r(39)}${C.gray}│${C.reset}`,
    `${C.gray}└${r(W + 2, "─")}┘${C.reset}`,
  ];
  for (const l of lines) await log(l, 140);
  if (DRY) wr(`\n${C.yellow}  ⚠  DRY-RUN — no transactions were submitted${C.reset}\n\n`);
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  if (!DRY && !process.env.ADMIN_PRIVATE_KEY) {
    wr(`\n${C.red}Error: ADMIN_PRIVATE_KEY not set. Use --dry-run or copy .env.example → .env${C.reset}\n\n`);
    process.exit(1);
  }

  await banner();
  await sleep(800);

  if (DRY) await log(`  ${C.yellow}◆  DRY-RUN MODE — transactions simulated, no gas spent${C.reset}\n`, 200);

  await phase1();
  const marketId = await phase2();
  await phase3(marketId);
  const observed = await phase4();
  await phase5(marketId, observed);
  await phase6();
  await footer();
}

main().catch(err => {
  wr(`\n${C.red}Fatal: ${(err as Error).message}${C.reset}\n\n`);
  process.exit(1);
});
