-- Admin All places at national scale.
--
-- Measured on production 2026-11-20 (1.76 million places, Small compute):
--   admin_place_filters, on every page load      4.2 s, and 2.6 MB of towns (34,715) sent to the page
--   admin_search_places, first page              5.1 s
--   name contains "pizza"                        6.0 s
--   Arlington, VA                                1.1 s
--   "No source has it"                           44 s
-- Every search worked out tags, "added by hand" and the source count for every matching place
-- and counted them all before taking a page, and nothing was indexed by name, state, town or ZIP.
--
-- Now:
--   * Indexes for the list's order (name, id), "name contains" (trigram), state and town, the
--     first five digits of the ZIP, tags (entity_categories by category), the review flag,
--     places added by hand, and places no source has.
--   * entities.no_source, kept by triggers on source_records: true while no source record
--     belongs to the place (added by hand and not matched yet, or its records moved away by
--     undoing a merge). New places start true; linking their first record sets it false.
--   * admin_search_places builds its query from the filters given, so each search is planned
--     for its own filters, and works out tags, "added by hand" and the source count only for
--     the page. With many matches it walks the places in name order; with few it finds them
--     first and sorts them. The count stops at 10,000: a total of 10001 means "more than 10,000". Up to
--     1,000 rows per call (was 200, which cut "all matching" bulk edits short at 200 places).
--     "Name contains" treats % and _ as plain characters.
--   * admin_place_filters lists towns only for the state given (towns for every state are no
--     longer sent; the unused all-states "cities" list is gone), from counts kept in
--     place_counts, counted again after every source load and once a day.
SET search_path = public, extensions;
SET statement_timeout = '15min';
SET maintenance_work_mem = '256MB';

-- ---------------------------------------------------------------- places no source has
ALTER TABLE public.entities ADD COLUMN no_source boolean NOT NULL DEFAULT false;
UPDATE public.entities e SET no_source = true
WHERE NOT EXISTS (SELECT 1 FROM public.source_records sr WHERE sr.entity_id = e.id);
ALTER TABLE public.entities ALTER COLUMN no_source SET DEFAULT true;

CREATE FUNCTION public.track_place_sources()
  RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.entity_id IS NOT NULL THEN
    UPDATE entities SET no_source = false WHERE id = NEW.entity_id AND no_source;
  END IF;
  IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.entity_id IS NOT NULL THEN
    UPDATE entities e SET no_source = true
    WHERE e.id = OLD.entity_id AND NOT e.no_source
      AND NOT EXISTS (SELECT 1 FROM source_records sr WHERE sr.entity_id = OLD.entity_id);
  END IF;
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.track_place_sources() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER source_records_place_added AFTER INSERT ON public.source_records
  FOR EACH ROW WHEN (NEW.entity_id IS NOT NULL) EXECUTE FUNCTION public.track_place_sources();
CREATE TRIGGER source_records_place_changed AFTER UPDATE OF entity_id ON public.source_records
  FOR EACH ROW WHEN (OLD.entity_id IS DISTINCT FROM NEW.entity_id) EXECUTE FUNCTION public.track_place_sources();
CREATE TRIGGER source_records_place_removed AFTER DELETE ON public.source_records
  FOR EACH ROW WHEN (OLD.entity_id IS NOT NULL) EXECUTE FUNCTION public.track_place_sources();

-- ---------------------------------------------------------------- indexes
CREATE INDEX entities_name_idx ON public.entities (name, id);
CREATE INDEX entities_name_trgm_idx ON public.entities USING gin (name gin_trgm_ops);
CREATE INDEX entities_state_city_idx ON public.entities (state, city) WHERE status <> 'merged';
CREATE INDEX entities_zip5_idx ON public.entities (left(postal_code, 5));
CREATE INDEX entities_needs_review_idx ON public.entities (name, id) WHERE needs_review;
CREATE INDEX entities_no_source_idx ON public.entities (name, id) WHERE no_source;
CREATE INDEX entity_categories_category_idx ON public.entity_categories (category_id);
CREATE INDEX change_events_added_by_hand_idx ON public.change_events (entity_id)
  WHERE event_type = 'new_candidate' AND (evidence->>'added_by_hand')::boolean;

-- ---------------------------------------------------------------- admin_search_places
CREATE OR REPLACE FUNCTION public.admin_search_places(
    p_q text DEFAULT NULL, p_state text DEFAULT NULL, p_city text DEFAULT NULL, p_zip text DEFAULT NULL,
    p_main text DEFAULT NULL, p_tags text[] DEFAULT NULL, p_status text DEFAULT NULL,
    p_needs_review boolean DEFAULT NULL, p_untagged boolean DEFAULT NULL,
    p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_origin text DEFAULT NULL)
  RETURNS TABLE(id uuid, name text, address text, city text, state text, postal_code text, phone text,
                website text, status text, needs_review boolean, main_category text, tags text[],
                updated_at timestamptz, total bigint,
                added_by_hand boolean, source_records integer, last_checked timestamptz)
  LANGUAGE plpgsql STABLE SET search_path = public, extensions AS $$
DECLARE
  v_q text := NULLIF(trim(p_q), '');
  v_zip text := left(NULLIF(trim(p_zip), ''), 5);
  v_main uuid;
  v_tags uuid[];
  w text[] := '{}';
  v_where text;
  v_total bigint;
BEGIN
  -- Values reach the query as parameters: $1 name pattern, $2 state, $3 town, $4 status,
  -- $5 ZIP, $6 main category, $7 tags (with the tags beneath them), $8 the total.
  w := w || CASE WHEN p_status IS NULL THEN $c$e.status <> 'merged'$c$ ELSE 'e.status = $4' END;
  IF v_q IS NOT NULL THEN
    v_q := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
    w := w || 'e.name ILIKE $1'::text;
  END IF;
  IF p_state IS NOT NULL THEN w := w || 'e.state = $2'::text; END IF;
  IF p_city IS NOT NULL THEN w := w || 'e.city = $3'::text; END IF;
  IF v_zip IS NOT NULL THEN w := w || 'left(e.postal_code, 5) = $5'::text; END IF;
  IF p_main IS NOT NULL THEN
    SELECT c.id INTO v_main FROM categories c WHERE c.path = p_main::ltree;
    IF v_main IS NULL THEN RETURN; END IF;
    w := w || 'e.main_category_id = $6'::text;
  END IF;
  IF cardinality(p_tags) > 0 THEN
    v_tags := ARRAY(SELECT c.id FROM categories c WHERE c.path <@ ANY (p_tags::ltree[]));
    w := w || 'EXISTS (SELECT 1 FROM entity_categories ec WHERE ec.entity_id = e.id AND ec.category_id = ANY ($7))'::text;
  END IF;
  IF p_needs_review IS TRUE THEN w := w || 'e.needs_review'::text;
  ELSIF p_needs_review IS FALSE THEN w := w || 'NOT e.needs_review'::text;
  END IF;
  IF p_untagged IS TRUE THEN
    w := w || 'NOT EXISTS (SELECT 1 FROM entity_categories ec WHERE ec.entity_id = e.id)'::text;
  END IF;
  -- hand: added by hand. unconfirmed: no source has it. stale: no source has it and nobody
  -- has checked it in 6 months.
  IF p_origin = 'hand' THEN
    w := w || $c$e.id IN (SELECT c.entity_id FROM change_events c
                         WHERE c.event_type = 'new_candidate' AND (c.evidence->>'added_by_hand')::boolean)$c$::text;
  ELSIF p_origin = 'unconfirmed' THEN
    w := w || 'e.no_source'::text;
  ELSIF p_origin = 'stale' THEN
    w := w || $c$e.no_source AND COALESCE(e.last_verified, e.created_at) < now() - interval '6 months'$c$::text;
  END IF;
  v_where := array_to_string(w, ' AND ');

  EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM entities e WHERE %s LIMIT 10001) c', v_where)
    INTO v_total USING v_q, p_state, p_city, p_status, v_zip, v_main, v_tags;
  IF v_total = 0 THEN RETURN; END IF;

  RETURN QUERY EXECUTE format($q$
    SELECT e.id, e.name, e.address, e.city, e.state, e.postal_code, e.phone, e.website, e.status,
           e.needs_review, m.name,
           COALESCE((SELECT array_agg(c.name ORDER BY c.path)
                     FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
                     WHERE ec.entity_id = e.id), '{}'),
           e.updated_at, $8,
           EXISTS (SELECT 1 FROM change_events c WHERE c.entity_id = e.id AND c.event_type = 'new_candidate'
                     AND (c.evidence->>'added_by_hand')::boolean),
           (SELECT count(*)::integer FROM source_records sr WHERE sr.entity_id = e.id),
           e.last_verified
    FROM (%s ORDER BY e.name, e.id LIMIT %s OFFSET %s) e
    JOIN categories m ON m.id = e.main_category_id
    ORDER BY e.name, e.id$q$,
    -- Many matches: walk the places in name order until the page is full. Few (10,000 or
    -- fewer): find them all first, then sort (walking the name order to find a few places
    -- in one state can pass over a hundred thousand others).
    CASE WHEN v_total > 10000 THEN format('SELECT e.* FROM entities e WHERE %s', v_where)
         ELSE format('SELECT e.* FROM (SELECT e.* FROM entities e WHERE %s OFFSET 0) e', v_where) END,
    LEAST(GREATEST(p_limit, 1), 1000), GREATEST(p_offset, 0))
  USING v_q, p_state, p_city, p_status, v_zip, v_main, v_tags, v_total;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_search_places(text, text, text, text, text, text[], text, boolean, boolean, integer, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_search_places(text, text, text, text, text, text[], text, boolean, boolean, integer, integer, text) TO service_role;

-- ---------------------------------------------------------------- admin_place_filters
-- The State and Town menus' counts, kept in place_counts: counted again after every source load
-- (scripts/ingest/common.py) and when a day old, by the first page that asks (counting every
-- place takes about a second on production; the list's own total is always current). A row
-- with city '' holds the places without a town.
CREATE TABLE public.place_counts (
  state text NOT NULL,
  city text NOT NULL,
  places integer NOT NULL,
  refreshed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (state, city)
);
ALTER TABLE public.place_counts ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION public.refresh_place_counts()
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  DELETE FROM place_counts;
  -- Grouped in the index's order (state, town), then the few towns left blank put together.
  INSERT INTO place_counts (state, city, places)
  SELECT state, COALESCE(city, ''), sum(n) FROM (
    SELECT state, city, count(*) AS n FROM entities
    WHERE status <> 'merged' AND state <> '' GROUP BY state, city) t
  GROUP BY 1, 2;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

-- States with their counts, and the towns of the state given (none without a state).
DROP FUNCTION public.admin_place_filters(text);
CREATE FUNCTION public.admin_place_filters(p_state text DEFAULT NULL)
  RETURNS jsonb
  LANGUAGE plpgsql VOLATILE SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM place_counts WHERE refreshed_at > now() - interval '1 day')
     AND pg_try_advisory_xact_lock(hashtext('refresh_place_counts')) THEN
    PERFORM refresh_place_counts();
  END IF;
  RETURN jsonb_build_object(
    'states', (SELECT COALESCE(jsonb_agg(jsonb_build_object('value', s, 'count', n) ORDER BY s), '[]'::jsonb)
               FROM (SELECT state AS s, sum(places)::integer AS n FROM place_counts GROUP BY 1) x),
    'towns',  (SELECT COALESCE(jsonb_agg(jsonb_build_object('state', state, 'value', city, 'count', places) ORDER BY city), '[]'::jsonb)
               FROM place_counts WHERE state = p_state AND city <> ''));
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_place_filters(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_place_filters(text) TO service_role;
REVOKE EXECUTE ON FUNCTION public.refresh_place_counts() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_place_counts() TO service_role;
REVOKE ALL ON TABLE public.place_counts FROM anon, authenticated;
GRANT ALL ON TABLE public.place_counts TO service_role;

SELECT public.refresh_place_counts();
