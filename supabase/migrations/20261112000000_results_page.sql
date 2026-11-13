-- One results page (build step 2, agreed 2026-11-10, mockups approved 2026-11-12).
--
-- Search and Discover become one page. It needs three things the old search_entities could not
-- give it, so they are new functions beside it (search_entities stays, unchanged, until nothing
-- calls it; the Favorites quick view still does):
--
--   search_places   the results. Same nearest-first search as search_entities, plus:
--                   * Favorites, Friends and Want to try filters that add up: with more than one
--                     on, a place matching any of them is shown ("both on shows either");
--                   * is_want: the place is on the person's ready-made Want to try list;
--                   * up to three friends' names per place (was two), for "Priya, Sam, Dev and
--                     4 others".
--   search_facets   the counts on the filter buttons: places per type, per cuisine within the
--                   chosen type, how many are favorites / friends' favorites / Want to try, and
--                   how many the person hid.
--   suggest_what    suggestions for the What box: kinds of places (with how many are nearby) and
--                   places by name, nearest first.
--
-- The ready-made list is renamed from "Want to Go" to "Want to try" (decided 2026-11-10).
SET search_path = public, extensions;

UPDATE public.lists SET name = 'Want to try' WHERE is_default_list AND name = 'Want to Go';

-- ---------------------------------------------------------------- search_places
CREATE FUNCTION public.search_places(
    ref_lat double precision, ref_lng double precision, radius_miles double precision,
    category_path public.ltree DEFAULT NULL, name_query text DEFAULT NULL,
    only_favorites boolean DEFAULT false, only_friends boolean DEFAULT false,
    only_want boolean DEFAULT false, show_hidden boolean DEFAULT false)
  RETURNS TABLE(id uuid, name text, address text, miles numeric, lat double precision, lng double precision,
                is_starred boolean, is_hidden boolean, is_want boolean, recommended_by jsonb,
                recommended_count integer, status text, categories text[], category_paths text[],
                total_count integer)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH ref AS (
    SELECT ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography AS g, auth.uid() AS uid
  ),
  my_friends AS (
    SELECT DISTINCT CASE WHEN f.requester_id = ref.uid THEN f.addressee_id ELSE f.requester_id END AS friend_id
    FROM friendships f CROSS JOIN ref
    WHERE ref.uid IS NOT NULL AND f.status = 'accepted'
      AND (f.requester_id = ref.uid OR f.addressee_id = ref.uid)
  ),
  -- The person's ready-made Want to try list (at most one per person).
  want_list AS (
    SELECT l.id FROM lists l CROSS JOIN ref WHERE ref.uid IS NOT NULL AND l.owner_id = ref.uid AND l.is_default_list
  ),
  hits AS (
    SELECT e.id, e.name, ST_Distance(e.location, ref.g) AS meters
    FROM entities e CROSS JOIN ref
    WHERE e.status NOT IN ('permanently_closed', 'merged', 'removed')
      AND ST_DWithin(e.location, ref.g, radius_miles * 1609.34)
      AND (category_path IS NULL
           OR EXISTS (SELECT 1 FROM categories mc
                      WHERE mc.id = e.main_category_id AND mc.path <@ category_path)
           OR EXISTS (SELECT 1 FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
                      WHERE ec.entity_id = e.id AND c.path <@ category_path))
      AND (show_hidden OR ref.uid IS NULL OR NOT EXISTS (
              SELECT 1 FROM hidden_entities h WHERE h.user_id = ref.uid AND h.entity_id = e.id))
      AND (NOT (only_favorites OR only_friends OR only_want)
           OR (only_favorites AND EXISTS (
                 SELECT 1 FROM stars s WHERE s.user_id = ref.uid AND s.entity_id = e.id))
           OR (only_friends AND EXISTS (
                 SELECT 1 FROM stars fs JOIN my_friends mf ON mf.friend_id = fs.user_id WHERE fs.entity_id = e.id))
           OR (only_want AND EXISTS (
                 SELECT 1 FROM list_items li JOIN want_list w ON w.id = li.list_id WHERE li.entity_id = e.id)))
      AND (name_query IS NULL OR trim(name_query) = '' OR e.name ILIKE '%' || trim(name_query) || '%')
  ),
  -- MATERIALIZED: counted once, not once per returned row (see 20261108000000).
  total AS MATERIALIZED (SELECT count(*)::integer AS n FROM hits),
  nearest AS (
    SELECT h.id, h.meters FROM hits h ORDER BY h.meters, h.name, h.id LIMIT 1000
  )
  SELECT
    e.id, e.name, list_address(e.address, e.city) AS address,
    round((n.meters / 1609.34)::numeric, 2) AS miles,
    ST_Y(e.location::geometry) AS lat,
    ST_X(e.location::geometry) AS lng,
    EXISTS (SELECT 1 FROM stars s WHERE s.user_id = ref.uid AND s.entity_id = e.id) AS is_starred,
    EXISTS (SELECT 1 FROM hidden_entities h WHERE h.user_id = ref.uid AND h.entity_id = e.id) AS is_hidden,
    EXISTS (SELECT 1 FROM list_items li JOIN want_list w ON w.id = li.list_id WHERE li.entity_id = e.id) AS is_want,
    (
      SELECT jsonb_agg(jsonb_build_object('name', t.name, 'handle', t.handle) ORDER BY t.starred_at)
      FROM (
        SELECT COALESCE(p.display_name, p.handle) AS name, p.handle AS handle, fs.created_at AS starred_at
        FROM stars fs
        JOIN my_friends mf ON mf.friend_id = fs.user_id
        JOIN profiles p ON p.id = fs.user_id
        WHERE fs.entity_id = e.id
        ORDER BY fs.created_at
        LIMIT 3
      ) t
    ) AS recommended_by,
    (
      SELECT count(*)::integer
      FROM stars fs JOIN my_friends mf ON mf.friend_id = fs.user_id
      WHERE fs.entity_id = e.id
    ) AS recommended_count,
    e.status,
    ARRAY[mc.name] || COALESCE((
        SELECT array_agg(cat.name ORDER BY cat.path)
        FROM entity_categories ec2 JOIN categories cat ON cat.id = ec2.category_id
        WHERE ec2.entity_id = e.id AND cat.id <> mc.id), '{}') AS categories,
    ARRAY[mc.path::text] || COALESCE((
        SELECT array_agg(cat3.path::text ORDER BY cat3.path)
        FROM entity_categories ec3 JOIN categories cat3 ON cat3.id = ec3.category_id
        WHERE ec3.entity_id = e.id AND cat3.id <> mc.id), '{}') AS category_paths,
    total.n AS total_count
  FROM nearest n
  JOIN entities e ON e.id = n.id
  JOIN categories mc ON mc.id = e.main_category_id
  CROSS JOIN ref
  CROSS JOIN total
  ORDER BY n.meters, e.name, e.id;
$$;

REVOKE ALL ON FUNCTION public.search_places(double precision, double precision, double precision,
  public.ltree, text, boolean, boolean, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_places(double precision, double precision, double precision,
  public.ltree, text, boolean, boolean, boolean, boolean) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- search_facets
-- The counts on the filter buttons, for the same area and name as search_places. Each count
-- leaves out its own filter, as filter counts usually do:
--   types     places of each type (and all of them), with the Favorites/Friends/Want to try
--             filters applied but not the type or cuisine;
--   cuisines  each finer kind in the chosen type (every type when none is chosen) with how many
--             places have it or one of its own finer kinds (a pizza place counts under Pizza and
--             under Italian). The What box's suggestions take their "12 nearby" from here;
--   favorites, friends, want   among places of the chosen type and cuisine, ignoring those three
--             filters, so each button says what it would add;
--   hidden    places the person hid that the current filters would otherwise show.
CREATE FUNCTION public.search_facets(
    ref_lat double precision, ref_lng double precision, radius_miles double precision,
    type_key text DEFAULT NULL, cuisine_path public.ltree DEFAULT NULL, name_query text DEFAULT NULL,
    only_favorites boolean DEFAULT false, only_friends boolean DEFAULT false,
    only_want boolean DEFAULT false, show_hidden boolean DEFAULT false)
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH ref AS (
    SELECT ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography AS g, auth.uid() AS uid
  ),
  my_friends AS (
    SELECT DISTINCT CASE WHEN f.requester_id = ref.uid THEN f.addressee_id ELSE f.requester_id END AS friend_id
    FROM friendships f CROSS JOIN ref
    WHERE ref.uid IS NOT NULL AND f.status = 'accepted'
      AND (f.requester_id = ref.uid OR f.addressee_id = ref.uid)
  ),
  want_list AS (
    SELECT l.id FROM lists l CROSS JOIN ref WHERE ref.uid IS NOT NULL AND l.owner_id = ref.uid AND l.is_default_list
  ),
  -- The chosen cuisine and its finer kinds, looked up once.
  cuisine_cats AS (SELECT c.id FROM categories c WHERE c.path <@ cuisine_path),
  -- Every place in the area matching the name, with what the counts need to know about it.
  -- (The type and cuisine are looked up per place rather than joined: on a 13,000-place area
  -- the join was planned as a nested loop over every category and took twice as long.)
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
    WHERE e.status NOT IN ('permanently_closed', 'merged', 'removed')
      AND ST_DWithin(e.location, ref.g, radius_miles * 1609.34)
      AND (name_query IS NULL OR trim(name_query) = '' OR e.name ILIKE '%' || trim(name_query) || '%')
  ),
  shown AS (SELECT * FROM area WHERE show_hidden OR NOT hidden),
  -- Passes the Favorites/Friends/Want to try filters (any of those switched on).
  status_ok AS (
    SELECT * FROM shown
    WHERE NOT (only_favorites OR only_friends OR only_want)
       OR (only_favorites AND fav) OR (only_friends AND friend) OR (only_want AND want)
  ),
  in_type AS (SELECT * FROM status_ok WHERE type_key IS NULL OR root = type_key),
  -- Each place in the chosen type (or every type) with every finer kind it has, counting a
  -- kind's parents too.
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
  -- The chosen type and cuisine, before the three status filters.
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

REVOKE ALL ON FUNCTION public.search_facets(double precision, double precision, double precision,
  text, public.ltree, text, boolean, boolean, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_facets(double precision, double precision, double precision,
  text, public.ltree, text, boolean, boolean, boolean, boolean) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- suggest_what
-- Suggestions for the What box once two characters are typed:
--   kinds   up to 4 kinds of places whose name starts with the text, or has a word starting
--           with it ("ita" -> Italian; "bar" -> Bar, Barbecue, Bar and Grill, ...), whole-name
--           starts first, broader kinds first. How many are nearby comes from search_facets,
--           which already counted the area, so typing never re-counts it;
--   places  up to 5 places whose name contains the text, within 25 miles, nearest first,
--           leaving out places the person hid. Walked outward from the point along the
--           location index, so it stops at the fifth match instead of reading the whole area.
-- Without a point, no places are suggested.
CREATE FUNCTION public.suggest_what(
    q text, ref_lat double precision DEFAULT NULL, ref_lng double precision DEFAULT NULL)
  RETURNS TABLE(kind text, label text, path text, type_key text, place_id uuid, address text, miles numeric)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH qn AS (SELECT lower(trim(coalesce(q, ''))) AS t),
  kinds AS (
    SELECT 'kind'::text AS kind, c.name AS label, c.path::text AS path, subpath(c.path, 0, 1)::text AS type_key,
           NULL::uuid AS place_id, NULL::text AS address, NULL::numeric AS miles,
           row_number() OVER (ORDER BY (lower(c.name) LIKE qn.t || '%') DESC, nlevel(c.path), c.name) AS ord
    FROM categories c CROSS JOIN qn
    WHERE length(qn.t) >= 2
      AND (lower(c.name) LIKE qn.t || '%' OR lower(c.name) LIKE '% ' || qn.t || '%')
  ),
  places AS (
    SELECT 'place'::text AS kind, e.name AS label, NULL::text AS path,
           (SELECT subpath(mc.path, 0, 1)::text FROM categories mc WHERE mc.id = e.main_category_id) AS type_key,
           e.id AS place_id, list_address(e.address, e.city) AS address,
           round((ST_Distance(e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography) / 1609.34)::numeric, 1) AS miles,
           row_number() OVER () AS ord
    FROM (
      SELECT e.* FROM entities e CROSS JOIN qn
      WHERE ref_lat IS NOT NULL AND ref_lng IS NOT NULL AND length(qn.t) >= 2
        AND e.status NOT IN ('permanently_closed', 'merged', 'removed')
        AND ST_DWithin(e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography, 25 * 1609.34)
        AND e.name ILIKE '%' || qn.t || '%'
        AND (auth.uid() IS NULL OR NOT EXISTS (
               SELECT 1 FROM hidden_entities h WHERE h.user_id = auth.uid() AND h.entity_id = e.id))
      ORDER BY e.location <-> ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography, e.name, e.id
      LIMIT 5
    ) e
  )
  SELECT kind, label, path, type_key, place_id, address, miles
  FROM (SELECT *, 0 AS grp FROM kinds WHERE ord <= 4 UNION ALL SELECT *, 1 AS grp FROM places) s
  ORDER BY grp, ord;
$$;

REVOKE ALL ON FUNCTION public.suggest_what(text, double precision, double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suggest_what(text, double precision, double precision)
  TO anon, authenticated, service_role;
