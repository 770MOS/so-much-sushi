// ⚠️  DANGER: DELETES EVERY AUTH USER IN THE PROJECT, INCLUDING REAL ACCOUNTS.
//
// This is a deliberate, rarely-used, one-time reset utility - NOT a routine
// test-cleanup tool. It was previously scripts/delete-all-users.mjs, invoked
// casually as "test cleanup" and accidentally deleted a real account
// (john@danzoes.com) that happened to exist alongside test data. It now
// lives here, under scripts/dangerous/, and requires explicit confirmation
// so that can't happen silently again.
//
// For routine Playwright test cleanup, use scripts/delete-test-users.mjs
// instead - it only touches accounts matching an explicit test marker
// (email starting with "test+") created recently, never a blanket wipe.
//
// Cascades automatically (ON DELETE CASCADE) to profiles, stars,
// hidden_entities, friendships, and lists - restaurant/category data is
// untouched, since none of it is owned by a user.
//
// Usage:
//   node scripts/dangerous/wipe-ALL-users.mjs               # dry run: lists who WOULD be deleted
//   node scripts/dangerous/wipe-ALL-users.mjs --confirm-wipe-everything   # actually deletes them
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const CONFIRM_FLAG = "--confirm-wipe-everything";
const confirmed = process.argv.includes(CONFIRM_FLAG);

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

if (data.users.length === 0) {
  console.log("No users exist. Nothing to do.");
  process.exit(0);
}

console.log(`The following ${data.users.length} account(s) would be PERMANENTLY DELETED:\n`);
for (const user of data.users) {
  console.log(`  ${user.email}  (id=${user.id}, created=${user.created_at})`);
}

if (!confirmed) {
  console.log(
    `\nDRY RUN - no accounts were deleted. Review the list above carefully.\n` +
      `If you are certain every single one of these should be permanently deleted,\n` +
      `re-run with: node scripts/dangerous/wipe-ALL-users.mjs ${CONFIRM_FLAG}`
  );
  process.exit(0);
}

console.log(`\n${CONFIRM_FLAG} passed - proceeding with deletion.\n`);

let deleted = 0;
let failed = 0;
for (const user of data.users) {
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
