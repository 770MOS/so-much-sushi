-- Production switch-over, step 1 (run once, before the migrations): remove the places built
-- from the old OpenStreetMap and Google pulls. OpenStreetMap data is share-alike (ODbL) and
-- must not stay in the product; the national load from Overture and All the Places replaces it.
--
-- Usage: psql -v keep_manual=yes|no -f clear_old_places.sql
--   keep_manual=yes  keeps places whose old source_code is 'manual' (entered by hand)
-- Stars, list entries and hidden marks on removed places are removed with them; the
-- switch-over copy (backup_before_switchover) keeps them for carrying over after the load.
-- Everything happens in one transaction: either all of it or none of it.
\set ON_ERROR_STOP 1
SELECT set_config('clear.keep_manual', :'keep_manual', false) \g /dev/null

BEGIN;
DO $$
DECLARE
  keep boolean := current_setting('clear.keep_manual') = 'yes';
  n_places bigint; n_kept bigint; n_stars bigint; n_items bigint; n_hidden bigint; n_cats bigint; n_nocat bigint;
BEGIN
  IF current_setting('clear.keep_manual') NOT IN ('yes', 'no') THEN RAISE EXCEPTION 'keep_manual must be yes or no'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'entities' AND column_name = 'source_code') THEN
    RAISE EXCEPTION 'this database already has the new schema; the switch-over has been done';
  END IF;
  IF to_regnamespace('backup_before_switchover') IS NULL THEN
    RAISE EXCEPTION 'no backup_before_switchover copy; take it first';
  END IF;

  CREATE TEMP TABLE gone ON COMMIT DROP AS
    SELECT id FROM public.entities WHERE NOT (keep AND source_code IS NOT DISTINCT FROM 'manual');
  SELECT count(*) INTO n_places FROM gone;
  SELECT count(*) INTO n_kept FROM public.entities WHERE id NOT IN (SELECT id FROM gone);

  -- A kept place needs a category, or the migration that makes the main category required stops.
  SELECT count(*) INTO n_nocat FROM public.entities e
  WHERE e.id NOT IN (SELECT id FROM gone)
    AND NOT EXISTS (SELECT 1 FROM public.entity_categories ec WHERE ec.entity_id = e.id);
  IF n_nocat > 0 THEN
    RAISE EXCEPTION '% kept places have no category; give them one first, or remove them too', n_nocat;
  END IF;

  DELETE FROM public.stars WHERE entity_id IN (SELECT id FROM gone);           GET DIAGNOSTICS n_stars = ROW_COUNT;
  DELETE FROM public.list_items WHERE entity_id IN (SELECT id FROM gone);      GET DIAGNOSTICS n_items = ROW_COUNT;
  DELETE FROM public.hidden_entities WHERE entity_id IN (SELECT id FROM gone); GET DIAGNOSTICS n_hidden = ROW_COUNT;
  DELETE FROM public.entity_categories WHERE entity_id IN (SELECT id FROM gone); GET DIAGNOSTICS n_cats = ROW_COUNT;
  DELETE FROM public.entities WHERE id IN (SELECT id FROM gone);

  RAISE NOTICE 'removed % old places (kept %), with % stars, % list entries, % hidden marks and % category links',
    n_places, n_kept, n_stars, n_items, n_hidden, n_cats;
END $$;
COMMIT;
