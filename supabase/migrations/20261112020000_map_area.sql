-- The map area is the search area (build step 3, decided 2026-11-10).
--
-- Step 2 searched a circle: a point and a distance from a menu. The menu goes away. A search
-- now covers a box on the map (west, south, east and north edges), and the point it was
-- started from is kept only to measure distances and put the nearest places first:
--   * picking a town opens on the whole town (its land area, see 20261112010000), a ZIP code
--     on its ZIP area, "Use my location" and the internet-address guess on about the nearest
--     50 places (start_area);
--   * moving the map shows "Search this area", which searches what is on the map.
--
--   search_area   the results: places in the box, nearest to the point first, at most 1,000,
--                 with the same columns and filters as step 2's search_places;
--   area_facets   the counts on the filter buttons, for the box (was search_facets);
--   area_cells    true counts for the map's bubbles when there are more than 1,000 places:
--                 the places counted on a grid, with how many in each square are the
--                 person's favorites, friends' favorites and Want to try, and the square's
--                 extent so clicking it can zoom to it;
--   start_area    how wide to open the map around a point: at least the given radius, wide
--                 enough to take in the given number of places, at most 25 miles.
--
-- Boxes are limited to 1.2 degrees north to south (about 80 miles) and 2.5 degrees east to
-- west (about 130 miles in the middle of the country); wider ones are refused, so a zoomed-out
-- map can never ask for a whole region's places at once.
-- search_places and search_facets (step 2) are dropped: only the results page used them.
SET search_path = public, extensions;

DROP FUNCTION IF EXISTS public.search_places(double precision, double precision, double precision,
  public.ltree, text, boolean, boolean, boolean, boolean);
DROP FUNCTION IF EXISTS public.search_facets(double precision, double precision, double precision,
  text, public.ltree, text, boolean, boolean, boolean, boolean);

-- ---------------------------------------------------------------- area_box
-- The box to look in, checked: edges in order, in range, and not too wide. Returned a little
-- larger than asked, as a geography, for the location index; callers then keep only places
-- whose own longitude and latitude are inside the exact edges. (A geography box's top and
-- bottom are great circles, not lines of latitude, so the index box alone could miss places
-- just inside the map's straight edges.)
CREATE FUNCTION public.area_box(
    west double precision, south double precision, east double precision, north double precision)
  RETURNS extensions.geography
  LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE
  pad double precision;
BEGIN
  IF west IS NULL OR south IS NULL OR east IS NULL OR north IS NULL
     OR west >= east OR south >= north
     OR west < -180 OR east > 180 OR south < -90 OR north > 90 THEN
    RAISE EXCEPTION 'search area is not a box on the map' USING ERRCODE = '22023';
  END IF;
  IF north - south > 1.2 OR east - west > 2.5 THEN
    RAISE EXCEPTION 'search area is too large' USING ERRCODE = '22023',
      HINT = 'Zoom the map in to search it.';
  END IF;
  pad := 0.02 * greatest(east - west, north - south) + 0.005;
  RETURN ST_MakeEnvelope(greatest(west - pad, -180), greatest(south - pad, -90),
                         least(east + pad, 180), least(north + pad, 90), 4326)::geography;
END;
$$;
REVOKE ALL ON FUNCTION public.area_box(double precision, double precision, double precision, double precision)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- area_matches
-- The places a search shows: in the box, open, of the kind, with the name, passing the
-- Favorites / Friends / Want to try filters (any of those switched on) and leaving out places
-- the viewer hid. Shared by search_area and area_cells so the list's count and the bubbles'
-- counts always agree. Internal: it takes the viewer as an argument, so the API roles can't
-- call it (search_area and area_cells pass auth.uid()).
CREATE FUNCTION public.area_matches(
    west double precision, south double precision, east double precision, north double precision,
    category_path public.ltree, name_query text, only_favorites boolean, only_friends boolean,
    only_want boolean, show_hidden boolean, viewer uuid)
  RETURNS TABLE(id uuid, name text, location extensions.geography)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  WITH box AS MATERIALIZED (SELECT public.area_box(west, south, east, north) AS g),
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
  FROM entities e CROSS JOIN box
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
    AND (name_query IS NULL OR trim(name_query) = '' OR e.name ILIKE '%' || trim(name_query) || '%');
$$;
REVOKE ALL ON FUNCTION public.area_matches(double precision, double precision, double precision, double precision,
  public.ltree, text, boolean, boolean, boolean, boolean, uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- search_area
CREATE FUNCTION public.search_area(
    ref_lat double precision, ref_lng double precision,
    west double precision, south double precision, east double precision, north double precision,
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
  want_list AS (
    SELECT l.id FROM lists l CROSS JOIN ref WHERE ref.uid IS NOT NULL AND l.owner_id = ref.uid AND l.is_default_list
  ),
  hits AS MATERIALIZED (
    SELECT m.id, m.name, ST_Distance(m.location, ref.g) AS meters
    FROM ref CROSS JOIN LATERAL public.area_matches(west, south, east, north, category_path, name_query,
                                                   only_favorites, only_friends, only_want, show_hidden, ref.uid) m
  ),
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
REVOKE ALL ON FUNCTION public.search_area(double precision, double precision, double precision, double precision,
  double precision, double precision, public.ltree, text, boolean, boolean, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_area(double precision, double precision, double precision, double precision,
  double precision, double precision, public.ltree, text, boolean, boolean, boolean, boolean)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- area_cells
-- The map's bubbles when a search has more than 1,000 places (the list holds only the nearest
-- 1,000, so the map can't count the rest itself). The box is cut into squares cell_lng wide
-- and cell_lat tall (at least a 200th of the box each way, so at most 40,000 squares); each
-- square with places gives where its places are on average, how many there are, and how many
-- of them are marked: each place once, by its first mark of the person's favorite, a friend's
-- favorite, Want to try (the order the map draws them in). west/south/east/north are the
-- extent of the square's places, for zooming to it.
CREATE FUNCTION public.area_cells(
    west double precision, south double precision, east double precision, north double precision,
    cell_lng double precision, cell_lat double precision,
    category_path public.ltree DEFAULT NULL, name_query text DEFAULT NULL,
    only_favorites boolean DEFAULT false, only_friends boolean DEFAULT false,
    only_want boolean DEFAULT false, show_hidden boolean DEFAULT false)
  RETURNS TABLE(lat double precision, lng double precision, n integer, fav integer, friend integer, want integer,
                cell_west double precision, cell_south double precision, cell_east double precision,
                cell_north double precision)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH ref AS (SELECT auth.uid() AS uid),
  size AS (
    SELECT greatest(coalesce(cell_lng, 0), (east - west) / 200) AS x,
           greatest(coalesce(cell_lat, 0), (north - south) / 200) AS y
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
  marked AS (
    SELECT m.location::geometry AS g,
           (ref.uid IS NOT NULL AND EXISTS (
              SELECT 1 FROM stars s WHERE s.user_id = ref.uid AND s.entity_id = m.id)) AS fav,
           EXISTS (SELECT 1 FROM stars fs JOIN my_friends mf ON mf.friend_id = fs.user_id
                   WHERE fs.entity_id = m.id) AS friend,
           EXISTS (SELECT 1 FROM list_items li JOIN want_list w ON w.id = li.list_id
                   WHERE li.entity_id = m.id) AS want
    FROM ref CROSS JOIN LATERAL public.area_matches(west, south, east, north, category_path, name_query,
                                                   only_favorites, only_friends, only_want, show_hidden, ref.uid) m
  )
  SELECT avg(ST_Y(k.g)), avg(ST_X(k.g)), count(*)::integer,
         count(*) FILTER (WHERE k.fav)::integer,
         count(*) FILTER (WHERE k.friend AND NOT k.fav)::integer,
         count(*) FILTER (WHERE k.want AND NOT k.fav AND NOT k.friend)::integer,
         min(ST_X(k.g)), min(ST_Y(k.g)), max(ST_X(k.g)), max(ST_Y(k.g))
  FROM marked k CROSS JOIN size
  GROUP BY ST_SnapToGrid(k.g, size.x, size.y)
  ORDER BY count(*) DESC;
$$;
REVOKE ALL ON FUNCTION public.area_cells(double precision, double precision, double precision, double precision,
  double precision, double precision, public.ltree, text, boolean, boolean, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.area_cells(double precision, double precision, double precision, double precision,
  double precision, double precision, public.ltree, text, boolean, boolean, boolean, boolean)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- area_facets
-- The counts on the filter buttons for the box; otherwise the same as step 2's search_facets
-- (20261112000000_results_page.sql). Each count leaves out its own filter:
--   types     places of each type (and all of them), with the Favorites/Friends/Want to try
--             filters applied but not the type or cuisine;
--   cuisines  each finer kind in the chosen type (every type when none is chosen) with how many
--             places have it or one of its own finer kinds;
--   favorites, friends, want   among places of the chosen type and cuisine, ignoring those three
--             filters, so each button says what it would add;
--   hidden    places the person hid that the current filters would otherwise show.
CREATE FUNCTION public.area_facets(
    west double precision, south double precision, east double precision, north double precision,
    type_key text DEFAULT NULL, cuisine_path public.ltree DEFAULT NULL, name_query text DEFAULT NULL,
    only_favorites boolean DEFAULT false, only_friends boolean DEFAULT false,
    only_want boolean DEFAULT false, show_hidden boolean DEFAULT false)
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH ref AS (SELECT auth.uid() AS uid),
  box AS MATERIALIZED (SELECT public.area_box(west, south, east, north) AS g),
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
    WHERE e.location && box.g
      AND ST_X(e.location::geometry) BETWEEN west AND east
      AND ST_Y(e.location::geometry) BETWEEN south AND north
      AND e.status NOT IN ('permanently_closed', 'merged', 'removed')
      AND (name_query IS NULL OR trim(name_query) = '' OR e.name ILIKE '%' || trim(name_query) || '%')
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
REVOKE ALL ON FUNCTION public.area_facets(double precision, double precision, double precision, double precision,
  text, public.ltree, text, boolean, boolean, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.area_facets(double precision, double precision, double precision, double precision,
  text, public.ltree, text, boolean, boolean, boolean, boolean) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- start_area
-- How many miles around a point to open the map on (a square twice that wide): at least
-- min_radius_miles (a picked town's own size), and far enough to take in the min_places-th
-- nearest open place, so a quiet town or a spot in the country still opens on some places;
-- never less than a third of a mile or more than 25. Downtown, the nearest 50 places are a few
-- blocks away; in the country they can be miles. Found by walking out from the point along the
-- location index, so it stops at the min_places-th place.
CREATE FUNCTION public.start_area(
    lat double precision, lng double precision,
    min_radius_miles double precision DEFAULT 0, min_places integer DEFAULT 50)
  RETURNS double precision
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH p AS (SELECT ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography AS g),
  nth AS (
    SELECT ST_Distance(e.location, p.g) / 1609.34 AS miles
    FROM entities e CROSS JOIN p
    WHERE e.status NOT IN ('permanently_closed', 'merged', 'removed')
    ORDER BY e.location <-> p.g
    OFFSET greatest(least(coalesce(min_places, 50), 500), 1) - 1
    LIMIT 1
  )
  SELECT round(LEAST(25, GREATEST(1.0 / 3, coalesce(min_radius_miles, 0),
                                  coalesce((SELECT miles FROM nth), 0)))::numeric, 2)::double precision
  WHERE lat BETWEEN -90 AND 90 AND lng BETWEEN -180 AND 180;
$$;
REVOKE ALL ON FUNCTION public.start_area(double precision, double precision, double precision, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_area(double precision, double precision, double precision, integer)
  TO anon, authenticated, service_role;
