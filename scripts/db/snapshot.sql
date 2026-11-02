-- A copy of the people's data, kept inside the database before a deploy changes anything.
-- Usage: psql -v schema=backup_20261102_193000 -v scope=routine -f snapshot.sql
--   scope=routine     profiles, friendships, lists, list entries, saved lists, stars, hidden marks
--   scope=switchover  the same, plus places, their categories and the category tree
-- The copies live in their own schema, which the API does not expose. Routine copies beyond
-- the newest 10 are dropped; the switch-over copy is kept.
-- Supabase's own daily backups cover everything else (the source data can be reloaded).
\set ON_ERROR_STOP 1
SELECT set_config('snapshot.schema', :'schema', false), set_config('snapshot.scope', :'scope', false) \g /dev/null

DO $$
DECLARE
  s text := current_setting('snapshot.schema');
  t text;
  n bigint;
  tables text[] := ARRAY['profiles', 'friendships', 'lists', 'list_items', 'saved_lists', 'stars', 'hidden_entities'];
BEGIN
  IF s !~ '^backup_[a-z0-9_]+$' THEN RAISE EXCEPTION 'bad backup schema name %', s; END IF;
  IF current_setting('snapshot.scope') = 'switchover' THEN
    tables := tables || ARRAY['entities', 'entity_categories', 'categories'];
  ELSIF current_setting('snapshot.scope') <> 'routine' THEN
    RAISE EXCEPTION 'scope must be routine or switchover';
  END IF;
  IF s = 'backup_before_switchover' AND to_regnamespace(s) IS NOT NULL THEN
    RAISE NOTICE 'kept the existing copy %, taken by an earlier attempt', s;
    RETURN;
  END IF;
  EXECUTE format('CREATE SCHEMA %I', s);
  EXECUTE format('REVOKE ALL ON SCHEMA %I FROM PUBLIC', s);
  FOREACH t IN ARRAY tables LOOP
    CONTINUE WHEN to_regclass('public.' || t) IS NULL;
    EXECUTE format('CREATE TABLE %I.%I AS TABLE public.%I', s, t, t);
    EXECUTE format('SELECT count(*) FROM %I.%I', s, t) INTO n;
    RAISE NOTICE 'copied % (% rows)', t, n;
  END LOOP;
  EXECUTE format('COMMENT ON SCHEMA %I IS %L', s,
                 'Copy of people''s data taken before a production deploy, ' || now()::text);

  -- Keep the newest 10 routine copies.
  FOR t IN SELECT nspname FROM pg_namespace
           WHERE nspname ~ '^backup_[0-9]{8}_[0-9]{6}$' ORDER BY nspname DESC OFFSET 10 LOOP
    EXECUTE format('DROP SCHEMA %I CASCADE', t);
    RAISE NOTICE 'dropped old copy %', t;
  END LOOP;
END $$;
