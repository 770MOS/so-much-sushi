-- What is in a database: counts only, never names, emails or other personal data, because
-- workflow logs in this repository are public. Works before and after the migrations.
-- Output: one "key|value" line per fact.
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

CREATE FUNCTION pg_temp.n(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  EXECUTE q INTO v;
  RETURN coalesce(v, '');
EXCEPTION WHEN undefined_table OR undefined_column OR invalid_schema_name THEN
  RETURN 'n/a';
END $$;

CREATE FUNCTION pg_temp.has_col(t text, c text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = t AND column_name = c) $$;

SELECT k || '|' || v FROM (
  SELECT 1 AS o, 'database size' AS k, pg_size_pretty(pg_database_size(current_database())) AS v
  UNION ALL SELECT 2, 'migrations recorded', pg_temp.n('SELECT count(*) FROM supabase_migrations.schema_migrations')
  UNION ALL SELECT 3, 'latest migration', pg_temp.n('SELECT max(version) FROM supabase_migrations.schema_migrations')
  UNION ALL SELECT 4, 'old schema (entities.osm_id present)', pg_temp.has_col('entities', 'osm_id')::text
  UNION ALL SELECT 5, 'NocoDB tables in public', pg_temp.n($q$SELECT count(*) FROM pg_tables WHERE schemaname = 'public'
                                                              AND (tablename LIKE 'nc\_%' OR tablename LIKE 'xc\_%')$q$)
  UNION ALL SELECT 10, 'user accounts', pg_temp.n('SELECT count(*) FROM auth.users')
  UNION ALL SELECT 11, 'profiles', pg_temp.n('SELECT count(*) FROM public.profiles')
  UNION ALL SELECT 12, 'friendships', pg_temp.n('SELECT count(*) FROM public.friendships')
  UNION ALL SELECT 13, 'lists', pg_temp.n('SELECT count(*) FROM public.lists')
  UNION ALL SELECT 14, 'list entries', pg_temp.n('SELECT count(*) FROM public.list_items')
  UNION ALL SELECT 15, 'saved lists', pg_temp.n('SELECT count(*) FROM public.saved_lists')
  UNION ALL SELECT 16, 'stars', pg_temp.n('SELECT count(*) FROM public.stars')
  UNION ALL SELECT 17, 'hidden marks', pg_temp.n('SELECT count(*) FROM public.hidden_entities')
  UNION ALL SELECT 18, 'users with any star, list entry or hidden mark', pg_temp.n(
    'SELECT count(DISTINCT u) FROM (SELECT user_id u FROM public.stars UNION ALL SELECT user_id FROM public.hidden_entities
       UNION ALL SELECT l.owner_id FROM public.list_items i JOIN public.lists l ON l.id = i.list_id) x')
  UNION ALL SELECT 20, 'places', pg_temp.n('SELECT count(*) FROM public.entities')
  UNION ALL SELECT 21, 'places by status', pg_temp.n(
    $q$SELECT string_agg(s || ' ' || c, ', ' ORDER BY c DESC) FROM (SELECT status s, count(*) c FROM public.entities GROUP BY 1) x$q$)
  UNION ALL SELECT 22, 'places by old origin (source / source_code)', CASE WHEN pg_temp.has_col('entities', 'source_code') THEN pg_temp.n(
    $q$SELECT string_agg(s || ' ' || c, ', ' ORDER BY c DESC) FROM (
         SELECT coalesce(nullif(source, ''), '(none)') || ' / ' || coalesce(source_code, '(none)') s, count(*) c
         FROM public.entities GROUP BY 1) x$q$) ELSE 'n/a' END
  UNION ALL SELECT 23, 'places with no category or tag', pg_temp.n(
    'SELECT count(*) FROM public.entities e WHERE NOT EXISTS (SELECT 1 FROM public.entity_categories ec WHERE ec.entity_id = e.id)')
  UNION ALL SELECT 24, 'stars, list entries and hidden marks on places by old origin', CASE WHEN pg_temp.has_col('entities', 'source_code') THEN pg_temp.n(
    $q$SELECT string_agg(s || ' ' || c, ', ' ORDER BY c DESC) FROM (
         SELECT coalesce(nullif(e.source, ''), '(none)') || ' / ' || coalesce(e.source_code, '(none)') s, count(*) c
         FROM (SELECT entity_id FROM public.stars UNION ALL SELECT entity_id FROM public.list_items
               UNION ALL SELECT entity_id FROM public.hidden_entities) m
         JOIN public.entities e ON e.id = m.entity_id GROUP BY 1) x$q$) ELSE 'n/a' END
  UNION ALL SELECT 30, 'source records', pg_temp.n('SELECT count(*) FROM public.source_records')
  UNION ALL SELECT 31, 'source loads (runs)', pg_temp.n(
    $q$SELECT count(*) || ' (' || count(*) FILTER (WHERE status = 'succeeded') || ' succeeded)' FROM public.source_runs$q$)
  UNION ALL SELECT 32, 'places from a source / added by hand / neither', pg_temp.n(
    $q$SELECT count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.source_records sr WHERE sr.entity_id = e.id)) || ' / ' ||
              count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.change_events c WHERE c.entity_id = e.id AND c.event_type = 'new_candidate' AND (c.evidence->>'added_by_hand')::boolean)) || ' / ' ||
              count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM public.source_records sr WHERE sr.entity_id = e.id)
                                 AND NOT EXISTS (SELECT 1 FROM public.change_events c WHERE c.entity_id = e.id AND c.event_type = 'new_candidate' AND (c.evidence->>'added_by_hand')::boolean))
       FROM public.entities e WHERE e.status NOT IN ('merged', 'removed')$q$)
  UNION ALL SELECT 33, 'pending review items', pg_temp.n($q$SELECT count(*) FROM public.change_events WHERE status = 'pending'$q$)
  UNION ALL SELECT 40, 'backup schemas', pg_temp.n(
    $q$SELECT coalesce(string_agg(nspname, ', ' ORDER BY nspname), 'none') FROM pg_namespace WHERE nspname LIKE 'backup\_%'$q$)
) x ORDER BY o;
