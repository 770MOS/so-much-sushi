-- Adds an UPDATE policy so list owners can edit their own lists' name,
-- description, and visibility (previously only SELECT/INSERT/DELETE were
-- policied - see supabase/lists.sql). Applied live in the SQL Editor;
-- this is a reconstruction matching that confirmed-working behavior and
-- the exact pattern of lists' existing SELECT/INSERT/DELETE policies, not
-- a verbatim pg_get_functiondef capture - no function is involved here,
-- just one CREATE POLICY statement, so the risk of drifting from the real
-- SQL is low, but flag it if anything looks off.
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

DROP POLICY IF EXISTS "Users can update their own lists" ON lists;
CREATE POLICY "Users can update their own lists" ON lists
  FOR UPDATE TO authenticated
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
