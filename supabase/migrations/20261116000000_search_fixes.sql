-- Search fixes after the first look at the tester site (2026-11-16).
--
-- 1. start_area was slow: 6-8 seconds for every search in a new place, against 0.1-0.4 s for
--    the search itself. It finds the min_places-th nearest open place by walking out along the
--    location index, but its OFFSET came from a parameter, so the planner couldn't tell how
--    many rows were needed, assumed a tenth of the table and sorted all 1.7 million places
--    instead. It now writes the number into its query, so the planner reads just the nearest
--    few from the index (1.3 s -> 1 ms on a test copy with 1.5 million places). Same answers.
--
-- 2. A name typed in the What box now also finds places of a kind with that name: "pizza"
--    finds every pizza place as well as places with "pizza" in their name. Before, only
--    picking the Pizza suggestion did that, and Enter found names alone. Kinds are matched
--    the way search engines match words (English word stems, so "bakeries" finds Bakery and
--    "smoothie" finds Juice and Smoothies; "and" and "&" ignored):
--      * a kind whose whole name is the text ("bar" -> Bar, not Bar and Grill);
--      * otherwise kinds whose name contains the text as words ("ice cream" -> Ice Cream and
--        Frozen Desserts; "bar" never finds Barbecue);
--      * if nothing matches, the same again without a trailing "restaurant", "food", "place",
--        "spot", "joint" or "shop" ("thai restaurant" -> Thai; "coffee shop" -> Coffee);
--    each with its finer kinds (Asian includes Sushi). "bbq" and "doughnut" count as Barbecue
--    and Donuts. Fewer than 3 characters, or "food" alone, match names only.
--    Shared by the results, the bubbles' counts and the filter counts, so they always agree.
SET search_path = public, extensions;

-- ---------------------------------------------------------------- kinds_for_text
-- The kinds (and their finer kinds) a typed text names, as category ids; empty when none.
CREATE FUNCTION public.kinds_for_text(t text)
  RETURNS uuid[]
  LANGUAGE plpgsql STABLE SET search_path = public, extensions AS $$
DECLARE
  q text := lower(btrim(coalesce(t, '')));
  generic constant text := '\s+(restaurants?|food|places?|spots?|joints?|shops?)$';
  tries text[];
  try text;
  found public.ltree[];
BEGIN
  -- Common other spellings.
  q := regexp_replace(q, '\m(bbq|barbeque)\M', 'barbecue', 'g');
  q := regexp_replace(q, '\mdoughnuts?\M', 'donut', 'g');
  -- Too short, or only a general word ("food" alone isn't a kind): names only.
  IF length(q) < 3 OR q ~ '^(food|places?|spots?|joints?|shops?)$' THEN
    RETURN '{}';
  END IF;
  tries := ARRAY[q];
  IF q ~ generic THEN
    tries := tries || regexp_replace(q, generic, '');
  END IF;
  FOREACH try IN ARRAY tries LOOP
    -- Only little words ("the", "and"): nothing to match.
    CONTINUE WHEN numnode(phraseto_tsquery('english', try)) = 0;
    SELECT array_agg(c.path) INTO found FROM categories c
    WHERE strip(to_tsvector('english', c.name)) = strip(to_tsvector('english', try));
    IF found IS NULL THEN
      SELECT array_agg(c.path) INTO found FROM categories c
      WHERE to_tsvector('english', c.name) @@ phraseto_tsquery('english', try);
    END IF;
    IF found IS NOT NULL THEN
      RETURN ARRAY(SELECT c.id FROM categories c WHERE c.path <@ found);
    END IF;
  END LOOP;
  RETURN '{}';
END;
$$;
REVOKE ALL ON FUNCTION public.kinds_for_text(text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- area_matches
-- As in 20261112020000_map_area.sql, with the typed text matching kinds as well as names.
CREATE OR REPLACE FUNCTION public.area_matches(
    west double precision, south double precision, east double precision, north double precision,
    category_path public.ltree, name_query text, only_favorites boolean, only_friends boolean,
    only_want boolean, show_hidden boolean, viewer uuid)
  RETURNS TABLE(id uuid, name text, location extensions.geography)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  WITH box AS MATERIALIZED (SELECT public.area_box(west, south, east, north) AS g),
  named AS MATERIALIZED (SELECT public.kinds_for_text(name_query) AS ids),
  my_friends AS (
    SELECT DISTINCT CASE WHEN f.requester_id = viewer THEN f.addressee_id ELSE f.requester_id END AS friend_id
    FROM friendships f
    WHERE viewer IS NOT NULL AND f.status = 'accepted'
      AND (f.requester_id = viewer OR f.addressee_id = viewer)
  ),
  want_list AS (
    SELECT l.id FROM lists l WHERE viewer IS NOT NULL AND l.owner_id = viewer AND l.is_default_list
  )
  SELECT e.id, e.name, e.location
  FROM entities e CROSS JOIN box CROSS JOIN named
  WHERE e.location && box.g
    AND ST_X(e.location::geometry) BETWEEN west AND east
    AND ST_Y(e.location::geometry) BETWEEN south AND north
    AND e.status NOT IN ('permanently_closed', 'merged', 'removed')
    AND (category_path IS NULL
         OR EXISTS (SELECT 1 FROM categories mc
                    WHERE mc.id = e.main_category_id AND mc.path <@ category_path)
         OR EXISTS (SELECT 1 FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
                    WHERE ec.entity_id = e.id AND c.path <@ category_path))
    AND (show_hidden OR viewer IS NULL OR NOT EXISTS (
            SELECT 1 FROM hidden_entities h WHERE h.user_id = viewer AND h.entity_id = e.id))
    AND (NOT (coalesce(only_favorites, false) OR coalesce(only_friends, false) OR coalesce(only_want, false))
         OR (only_favorites AND EXISTS (
               SELECT 1 FROM stars s WHERE s.user_id = viewer AND s.entity_id = e.id))
         OR (only_friends AND EXISTS (
               SELECT 1 FROM stars fs JOIN my_friends mf ON mf.friend_id = fs.user_id WHERE fs.entity_id = e.id))
         OR (only_want AND EXISTS (
               SELECT 1 FROM list_items li JOIN want_list w ON w.id = li.list_id WHERE li.entity_id = e.id)))
    AND (name_query IS NULL OR btrim(name_query) = ''
         OR e.name ILIKE '%' || btrim(name_query) || '%'
         OR (cardinality(named.ids) > 0
             AND (e.main_category_id = ANY (named.ids)
                  OR EXISTS (SELECT 1 FROM entity_categories ec
                             WHERE ec.entity_id = e.id AND ec.category_id = ANY (named.ids)))));
$$;

-- ---------------------------------------------------------------- area_facets
-- As in 20261112020000_map_area.sql, with the typed text matching kinds as well as names.
CREATE OR REPLACE FUNCTION public.area_facets(
    west double precision, south double precision, east double precision, north double precision,
    type_key text DEFAULT NULL, cuisine_path public.ltree DEFAULT NULL, name_query text DEFAULT NULL,
    only_favorites boolean DEFAULT false, only_friends boolean DEFAULT false,
    only_want boolean DEFAULT false, show_hidden boolean DEFAULT false)
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH ref AS (SELECT auth.uid() AS uid),
  box AS MATERIALIZED (SELECT public.area_box(west, south, east, north) AS g),
  named AS MATERIALIZED (SELECT public.kinds_for_text(name_query) AS ids),
  my_friends AS (
    SELECT DISTINCT CASE WHEN f.requester_id = ref.uid THEN f.addressee_id ELSE f.requester_id END AS friend_id
    FROM friendships f CROSS JOIN ref
    WHERE ref.uid IS NOT NULL AND f.status = 'accepted'
      AND (f.requester_id = ref.uid OR f.addressee_id = ref.uid)
  ),
  want_list AS (
    SELECT l.id FROM lists l CROSS JOIN ref WHERE ref.uid IS NOT NULL AND l.owner_id = ref.uid AND l.is_default_list
  ),
  cuisine_cats AS (SELECT c.id FROM categories c WHERE c.path <@ cuisine_path),
  area AS MATERIALIZED (
    SELECT e.id,
           (SELECT subpath(mc.path, 0, 1)::text FROM categories mc WHERE mc.id = e.main_category_id) AS root,
           (cuisine_path IS NULL
            OR e.main_category_id IN (SELECT id FROM cuisine_cats)
            OR EXISTS (SELECT 1 FROM entity_categories ec
                       WHERE ec.entity_id = e.id AND ec.category_id IN (SELECT id FROM cuisine_cats))) AS in_cuisine,
           (ref.uid IS NOT NULL AND EXISTS (
              SELECT 1 FROM stars s WHERE s.user_id = ref.uid AND s.entity_id = e.id)) AS fav,
           EXISTS (SELECT 1 FROM stars fs JOIN my_friends mf ON mf.friend_id = fs.user_id
                   WHERE fs.entity_id = e.id) AS friend,
           EXISTS (SELECT 1 FROM list_items li JOIN want_list w ON w.id = li.list_id
                   WHERE li.entity_id = e.id) AS want,
           (ref.uid IS NOT NULL AND EXISTS (
              SELECT 1 FROM hidden_entities h WHERE h.user_id = ref.uid AND h.entity_id = e.id)) AS hidden
    FROM entities e
    CROSS JOIN ref
    CROSS JOIN box
    CROSS JOIN named
    WHERE e.location && box.g
      AND ST_X(e.location::geometry) BETWEEN west AND east
      AND ST_Y(e.location::geometry) BETWEEN south AND north
      AND e.status NOT IN ('permanently_closed', 'merged', 'removed')
      AND (name_query IS NULL OR btrim(name_query) = ''
           OR e.name ILIKE '%' || btrim(name_query) || '%'
           OR (cardinality(named.ids) > 0
               AND (e.main_category_id = ANY (named.ids)
                    OR EXISTS (SELECT 1 FROM entity_categories ec
                               WHERE ec.entity_id = e.id AND ec.category_id = ANY (named.ids)))))
  ),
  shown AS (SELECT * FROM area WHERE show_hidden OR NOT hidden),
  status_ok AS (
    SELECT * FROM shown
    WHERE NOT (only_favorites OR only_friends OR only_want)
       OR (only_favorites AND fav) OR (only_friends AND friend) OR (only_want AND want)
  ),
  in_type AS (SELECT * FROM status_ok WHERE type_key IS NULL OR root = type_key),
  kinds AS (
    SELECT DISTINCT t.id, subpath(c.path, 0, k) AS path
    FROM in_type t
    JOIN entity_categories ec ON ec.entity_id = t.id
    JOIN categories c ON c.id = ec.category_id
    CROSS JOIN LATERAL generate_series(2, nlevel(c.path)) AS k
    WHERE nlevel(c.path) >= 2 AND (type_key IS NULL OR subpath(c.path, 0, 1)::text = type_key)
  ),
  type_counts AS (
    SELECT 'all' AS k, count(*)::integer AS n FROM status_ok
    UNION ALL
    SELECT root, count(*)::integer FROM status_ok GROUP BY root
  ),
  cuisine_counts AS (
    SELECT c.path::text AS path, c.name, count(*)::integer AS n
    FROM kinds k JOIN categories c ON c.path = k.path
    GROUP BY c.path, c.name
  ),
  chosen AS (SELECT * FROM shown WHERE (type_key IS NULL OR root = type_key) AND in_cuisine)
  SELECT jsonb_build_object(
    'types', COALESCE((SELECT jsonb_object_agg(k, n) FROM type_counts), '{}'::jsonb),
    'cuisines', COALESCE((SELECT jsonb_agg(jsonb_build_object('path', path, 'name', name, 'n', n) ORDER BY path)
                          FROM cuisine_counts), '[]'::jsonb),
    'favorites', (SELECT count(*)::integer FROM chosen WHERE fav),
    'friends', (SELECT count(*)::integer FROM chosen WHERE friend),
    'want', (SELECT count(*)::integer FROM chosen WHERE want),
    'hidden', CASE WHEN show_hidden THEN 0 ELSE (
      SELECT count(*)::integer FROM area
      WHERE hidden AND (type_key IS NULL OR root = type_key) AND in_cuisine
        AND (NOT (only_favorites OR only_friends OR only_want)
             OR (only_favorites AND fav) OR (only_friends AND friend) OR (only_want AND want))) END
  );
$$;

-- ---------------------------------------------------------------- start_area
-- As in 20261112020000_map_area.sql (how many miles around a point to open the map on), now
-- in PL/pgSQL so the place count is written into the query as a number; see the top of this
-- file. Same answers, including null for a point off the map.
CREATE OR REPLACE FUNCTION public.start_area(
    lat double precision, lng double precision,
    min_radius_miles double precision DEFAULT 0, min_places integer DEFAULT 50)
  RETURNS double precision
  LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  n constant integer := greatest(least(coalesce(min_places, 50), 500), 1);
  miles double precision;
BEGIN
  IF lat IS NULL OR lng IS NULL OR lat NOT BETWEEN -90 AND 90 OR lng NOT BETWEEN -180 AND 180 THEN
    RETURN NULL;
  END IF;
  EXECUTE format(
    'SELECT ST_Distance(e.location, $1) / 1609.34 FROM entities e
      WHERE e.status NOT IN (''permanently_closed'', ''merged'', ''removed'')
      ORDER BY e.location <-> $1
      OFFSET %s LIMIT 1', n - 1)
    INTO miles
    USING ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography;
  RETURN round(LEAST(25, GREATEST(1.0 / 3, coalesce(min_radius_miles, 0), coalesce(miles, 0)))::numeric, 2)::double precision;
END;
$$;
