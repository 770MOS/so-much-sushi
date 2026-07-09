-- friendships RLS policies: the first tracked record of them, confirmed
-- verbatim via `SELECT policyname, cmd, qual, with_check FROM pg_policies
-- WHERE tablename = 'friendships';` against the live database. Like
-- search_entities.sql, these were created directly in the SQL Editor at some
-- point before this file existed and were never previously tracked in git -
-- this mirrors what's live, it doesn't change it.
--
-- RLS on friendships was already enabled and these policies already active
-- when the Profile page's Connections tab was built (see
-- supabase/grants_reference.sql for the GRANT statements that were missing
-- alongside these - RLS policies alone don't grant the underlying table
-- privilege).
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "See your own friendships" ON friendships;
CREATE POLICY "See your own friendships" ON friendships
  FOR SELECT
  USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

DROP POLICY IF EXISTS "Send requests as yourself" ON friendships;
CREATE POLICY "Send requests as yourself" ON friendships
  FOR INSERT
  WITH CHECK (auth.uid() = requester_id);

DROP POLICY IF EXISTS "Addressee accepts or blocks" ON friendships;
CREATE POLICY "Addressee accepts or blocks" ON friendships
  FOR UPDATE
  USING (auth.uid() = addressee_id);

DROP POLICY IF EXISTS "Either side can remove" ON friendships;
CREATE POLICY "Either side can remove" ON friendships
  FOR DELETE
  USING (auth.uid() = requester_id OR auth.uid() = addressee_id);
