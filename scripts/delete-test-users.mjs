// Routine Playwright test cleanup - scoped on purpose. Only deletes accounts
// that BOTH:
//   1. match a test-account email pattern (default: local-part starts with
//      "test+", e.g. test+abc123@example.com), AND
//   2. were created recently (default: within the last 24h)
//
// Both conditions must hold, so a real account can never be swept up by
// coincidence - even if its email happened to match the pattern, it won't
// match the recency window unless it was just created.
//
// This replaces scripts/delete-all-users.mjs (moved to
// scripts/dangerous/wipe-ALL-users.mjs), which deleted every account in the
// project with no filtering and no confirmation, and once took out a real
// account (john@danzoes.com) along with test data. Never use that script for
// routine cleanup - use this one.
//
// Going forward, name test accounts created for Playwright verification
// test+<anything>@example.com (e.g. test+signup-flow-<timestamp>@example.com)
// so they're covered by the default pattern here.
//
// Usage:
//   node scripts/delete-test-users.mjs                        # dry run
//   node scripts/delete-test-users.mjs --confirm               # actually deletes
//   node scripts/delete-test-users.mjs --pattern '^test\+' --since 2h --confirm
//   node scripts/delete-test-users.mjs --since 2026-07-10T00:00:00Z --confirm
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const DEFAULT_PATTERN = "^test\\+";
const DEFAULT_SINCE = "24h";
const SAFETY_CAP = 50; // require --force too if more than this many match

function parseArgs(argv) {
  const args = { pattern: DEFAULT_PATTERN, since: DEFAULT_SINCE, confirm: false, force: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--pattern") args.pattern = argv[++i];
    else if (argv[i] === "--since") args.since = argv[++i];
    else if (argv[i] === "--confirm") args.confirm = true;
    else if (argv[i] === "--force") args.force = true;
  }
  return args;
}

function parseSince(value) {
  const relative = /^(\d+)([smhd])$/.exec(value);
  if (relative) {
    const amount = Number(relative[1]);
    const unitMs = { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 }[relative[2]];
    return new Date(Date.now() - amount * unitMs);
  }
  const asDate = new Date(value);
  if (Number.isNaN(asDate.getTime())) {
    throw new Error(`Could not parse --since value "${value}" as a duration (e.g. "24h") or ISO date.`);
  }
  return asDate;
}

const args = parseArgs(process.argv.slice(2));
const emailPattern = new RegExp(args.pattern, "i");
const sinceDate = parseSince(args.since);

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !serviceRoleKey) {
  console.error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env.local");
  process.exit(1);
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const { data, error } = await supabase.auth.admin.listUsers({ perPage: 1000 });
if (error) {
  console.error("Failed to list users:", error.message);
  process.exit(1);
}

const matches = data.users.filter(
  (user) => emailPattern.test(user.email ?? "") && new Date(user.created_at) >= sinceDate
);

console.log(`Pattern: /${args.pattern}/i    Since: ${sinceDate.toISOString()}`);
console.log(`${data.users.length} total account(s) in project, ${matches.length} match both criteria.\n`);

if (matches.length === 0) {
  console.log("Nothing to delete.");
  process.exit(0);
}

console.log("The following account(s) would be deleted:\n");
for (const user of matches) {
  console.log(`  ${user.email}  (id=${user.id}, created=${user.created_at})`);
}

if (matches.length > SAFETY_CAP && !args.force) {
  console.log(
    `\n${matches.length} accounts matched, which is more than the safety cap of ${SAFETY_CAP}.\n` +
      `This is refused by default in case the pattern/window is broader than intended.\n` +
      `Re-run with --force (in addition to --confirm) if this is really what you want.`
  );
  process.exit(1);
}

if (!args.confirm) {
  console.log(
    `\nDRY RUN - no accounts were deleted. Review the list above.\n` +
      `Re-run with --confirm to actually delete these ${matches.length} account(s).`
  );
  process.exit(0);
}

console.log(`\n--confirm passed - proceeding with deletion.\n`);

let deleted = 0;
let failed = 0;
for (const user of matches) {
  const { error: deleteError } = await supabase.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error(`  FAILED  ${user.email} (${user.id}): ${deleteError.message}`);
    failed += 1;
  } else {
    console.log(`  deleted ${user.email} (${user.id})`);
    deleted += 1;
  }
}

console.log(`Done. Deleted ${deleted}, failed ${failed}.`);
if (failed > 0) process.exit(1);
