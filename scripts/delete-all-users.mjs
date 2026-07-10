// One-off/reset utility: deletes every auth user via the Admin API. Cascades
// automatically (ON DELETE CASCADE) to profiles, stars, hidden_entities,
// friendships, and lists - restaurant/category data is untouched, since none
// of it is owned by a user.
//
// Usage: node scripts/delete-all-users.mjs
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

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

console.log(`Found ${data.users.length} user(s) to delete.`);

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
