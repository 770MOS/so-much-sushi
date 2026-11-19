-- Advanced search, step 1: the database (mocked 2026-11-19; see the plan's "Advanced search").
--
-- The search functions take one more, optional argument, `more` (jsonb), for the All filters
-- panel. Every key is optional and '{}' (the default) changes nothing, so today's app works
-- as before:
--   cuisines  array of kind paths, any of them ("restaurants.asian.thai", ...)
--   street    a street, matched on its start ("wilson" or "Wilson Boulevard" finds Wilson Blvd)
--   chain     'chain' or 'independent'
--   website   true: only places with a website      phone   true: only with a phone number
--   closed    true: places that have closed too (still never merged or removed ones)
--   list      one of the viewer's own lists (its id)
--   close     true: the typed name also matches close spellings ("sawasdee thai" finds
--             Sawatdee Thai Restaurant); 3 characters or more, word similarity 0.5 or more
--   area      a drawn area: [[lng, lat], ...], 3 to 100 points, closed automatically; the box
--             arguments should be its bounds (the location index searches the box first)
--   counts    true (area_facets only): also count the panel's choices (streets, chain or
--             independent, website, phone, closed places)
-- Each count leaves out its own filter and keeps the others, like the type and cuisine counts.
--
-- A chain is a name with 10 or more open places nationwide (decided 2026-11-19, "to start,
-- keep an eye on it"). Names are compared lower-cased, apostrophes dropped and anything else
-- that isn't a letter or digit as a space ("McDonald's" = "mcdonalds"), and kept in
-- chain_names, refreshed by refresh_chain_names() here and after every source load.
-- Measured 2026-11-19: 200 of 696 open places near Clarendon; Pho 75 has exactly 10.
--
-- suggest_what also offers close spellings (kind 'close', up to 3, among the nearest 5,000 places
-- within 25 miles) when no name nearby contains the typed text. Measured on production in Midtown
-- Manhattan: 80 ms (all places within 10 miles instead: 0.7 s).
SET search_path = public, extensions;
SET statement_timeout = '10min';

-- ---------------------------------------------------------------- chain_key, chain_names
CREATE FUNCTION public.chain_key(place_name text)
  RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT nullif(btrim(regexp_replace(regexp_replace(lower(coalesce(place_name, '')), '[''’`]', '', 'g'),
                                     '[^[:alnum:]]+', ' ', 'g')), '')
$$;

CREATE TABLE public.chain_names (
  name_key text PRIMARY KEY,
  places integer NOT NULL,
  refreshed_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.chain_names IS
  'Names with 10 or more open places nationwide (chain_key); refresh_chain_names() after each load';
ALTER TABLE public.chain_names ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.chain_names FROM anon, authenticated;
GRANT ALL ON TABLE public.chain_names TO service_role;

CREATE FUNCTION public.refresh_chain_names()
  RETURNS integer
  LANGUAGE plpgsql VOLATILE SET search_path = public, extensions AS $$
DECLARE
  n integer;
BEGIN
  DELETE FROM chain_names;
  INSERT INTO chain_names(name_key, places)
  SELECT chain_key(e.name), count(*)
  FROM entities e
  WHERE e.status NOT IN ('permanently_closed', 'merged', 'removed') AND chain_key(e.name) IS NOT NULL
  GROUP BY 1
  HAVING count(*) >= 10;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_chain_names() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_chain_names() TO service_role;

SELECT public.refresh_chain_names();

-- ---------------------------------------------------------------- street_key
-- The street of an address, the same however it was written: lower case, no house number or
-- unit, common words shortened ("1515 Wilson Boulevard, Suite 100" -> "wilson blvd";
-- "305 North Glebe Road" -> "n glebe rd"). Null when nothing like a street is left.
CREATE FUNCTION public.street_key(address text)
  RETURNS text
  LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
  s text := lower(coalesce(address, ''));
BEGIN
  s := split_part(s, ',', 1);
  s := regexp_replace(s, '\s*(#|\m(ste|suite|unit|fl|floor|apt|bldg|building|room|rm|spc|space)\M).*$', '');
  s := regexp_replace(s, '^\s*[0-9][0-9a-z/-]*\s+', '');
  s := replace(s, '.', '');
  s := regexp_replace(s, '\mboulevard\M', 'blvd', 'g');
  s := regexp_replace(s, '\mstreet\M', 'st', 'g');
  s := regexp_replace(s, '\mavenue\M', 'ave', 'g');
  s := regexp_replace(s, '\mroad\M', 'rd', 'g');
  s := regexp_replace(s, '\mdrive\M', 'dr', 'g');
  s := regexp_replace(s, '\mlane\M', 'ln', 'g');
  s := regexp_replace(s, '\mcourt\M', 'ct', 'g');
  s := regexp_replace(s, '\mplace\M', 'pl', 'g');
  s := regexp_replace(s, '\mhighway\M', 'hwy', 'g');
  s := regexp_replace(s, '\mparkway\M', 'pkwy', 'g');
  s := regexp_replace(s, '\mterrace\M', 'ter', 'g');
  s := regexp_replace(s, '\mcircle\M', 'cir', 'g');
  s := regexp_replace(s, '\mnorth\M', 'n', 'g');
  s := regexp_replace(s, '\msouth\M', 's', 'g');
  s := regexp_replace(s, '\meast\M', 'e', 'g');
  s := regexp_replace(s, '\mwest\M', 'w', 'g');
  s := btrim(regexp_replace(s, '\s+', ' ', 'g'));
  IF s = '' OR s ~ '^[0-9]+$' THEN
    RETURN NULL;
  END IF;
  RETURN s;
END;
$$;

-- ---------------------------------------------------------------- area_shape
-- A drawn area ([[lng, lat], ...]) as a polygon, closed automatically and made valid if the
-- line crosses itself. Null when none was given.
CREATE FUNCTION public.area_shape(pts jsonb)
  RETURNS extensions.geometry
  LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE
  n integer;
  line geometry;
  shape geometry;
BEGIN
  IF pts IS NULL OR jsonb_typeof(pts) = 'null' THEN
    RETURN NULL;
  END IF;
  IF jsonb_typeof(pts) <> 'array' THEN
    RAISE EXCEPTION 'a drawn area is a list of points' USING ERRCODE = '22023';
  END IF;
  n := jsonb_array_length(pts);
  IF n < 3 OR n > 100 THEN
    RAISE EXCEPTION 'a drawn area needs 3 to 100 points' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(pts) p
             WHERE jsonb_typeof(p) <> 'array' OR jsonb_array_length(p) <> 2
                OR jsonb_typeof(p -> 0) <> 'number' OR jsonb_typeof(p -> 1) <> 'number'
                OR (p ->> 0)::float8 NOT BETWEEN -180 AND 180 OR (p ->> 1)::float8 NOT BETWEEN -90 AND 90) THEN
    RAISE EXCEPTION 'a drawn area''s points are [longitude, latitude] on the map' USING ERRCODE = '22023';
  END IF;
  SELECT ST_MakeLine(array_agg(ST_SetSRID(ST_MakePoint((p ->> 0)::float8, (p ->> 1)::float8), 4326) ORDER BY i))
  INTO line
  FROM jsonb_array_elements(pts) WITH ORDINALITY AS t(p, i);
  shape := ST_MakePolygon(ST_AddPoint(line, ST_StartPoint(line)));
  IF NOT ST_IsValid(shape) THEN
    shape := ST_CollectionExtract(ST_MakeValid(shape), 3);
  END IF;
  RETURN shape;
END;
$$;
REVOKE ALL ON FUNCTION public.chain_key(text), public.street_key(text), public.area_shape(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chain_key(text), public.street_key(text), public.area_shape(jsonb) TO service_role;

-- ---------------------------------------------------------------- area_options
-- `more` read once per search.
CREATE FUNCTION public.area_options(more jsonb, name_query text)
  RETURNS TABLE(named uuid[], q text, close boolean, shape extensions.geometry, street text, chain text,
                website boolean, phone boolean, closed boolean, list_id uuid, cuisine_ids uuid[], counts boolean)
  LANGUAGE plpgsql STABLE SET search_path = public, extensions AS $$
BEGIN
  IF more IS NOT NULL AND jsonb_typeof(more) <> 'object' THEN
    RAISE EXCEPTION 'more is a set of filters' USING ERRCODE = '22023';
  END IF;
  IF more ->> 'chain' IS NOT NULL AND more ->> 'chain' NOT IN ('chain', 'independent') THEN
    RAISE EXCEPTION 'chain is chain or independent' USING ERRCODE = '22023';
  END IF;
  RETURN QUERY SELECT
    kinds_for_text(name_query),
    btrim(coalesce(name_query, '')),
    coalesce((more ->> 'close')::boolean, false),
    area_shape(more -> 'area'),
    street_key(nullif(btrim(more ->> 'street'), '')),
    more ->> 'chain',
    coalesce((more ->> 'website')::boolean, false),
    coalesce((more ->> 'phone')::boolean, false),
    coalesce((more ->> 'closed')::boolean, false),
    nullif(more ->> 'list', '')::uuid,
    ARRAY(SELECT DISTINCT c.id
          FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(more -> 'cuisines') = 'array'
                                              THEN more -> 'cuisines' ELSE '[]'::jsonb END) p
          JOIN categories c ON c.path <@ p::ltree),
    coalesce((more ->> 'counts')::boolean, false);
END;
$$;
REVOKE ALL ON FUNCTION public.area_options(jsonb, text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- area_matches
-- As in 20261116000000_search_fixes.sql, with `more`.
DROP FUNCTION public.area_matches(double precision, double precision, double precision, double precision,
  public.ltree, text, boolean, boolean, boolean, boolean, uuid);
CREATE FUNCTION public.area_matches(
    west double precision, south double precision, east double precision, north double precision,
    category_path public.ltree, name_query text, only_favorites boolean, only_friends boolean,
    only_want boolean, show_hidden boolean, viewer uuid, more jsonb)
  RETURNS TABLE(id uuid, name text, location extensions.geography)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  WITH box AS MATERIALIZED (SELECT public.area_box(west, south, east, north) AS g),
  opt AS MATERIALIZED (SELECT * FROM public.area_options(more, name_query)),
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
  FROM entities e CROSS JOIN box CROSS JOIN opt
  WHERE e.location && box.g
    AND ST_X(e.location::geometry) BETWEEN west AND east
    AND ST_Y(e.location::geometry) BETWEEN south AND north
    AND (e.status NOT IN ('permanently_closed', 'merged', 'removed')
         OR (opt.closed AND e.status = 'permanently_closed'))
    AND (opt.shape IS NULL OR ST_Intersects(e.location::geometry, opt.shape))
    AND (category_path IS NULL
         OR EXISTS (SELECT 1 FROM categories mc
                    WHERE mc.id = e.main_category_id AND mc.path <@ category_path)
         OR EXISTS (SELECT 1 FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
                    WHERE ec.entity_id = e.id AND c.path <@ category_path))
    AND (cardinality(opt.cuisine_ids) = 0
         OR e.main_category_id = ANY (opt.cuisine_ids)
         OR EXISTS (SELECT 1 FROM entity_categories ec
                    WHERE ec.entity_id = e.id AND ec.category_id = ANY (opt.cuisine_ids)))
    AND (opt.street IS NULL OR public.street_key(e.address) LIKE opt.street || '%')
    AND (opt.chain IS NULL
         OR EXISTS (SELECT 1 FROM chain_names cn WHERE cn.name_key = public.chain_key(e.name)) = (opt.chain = 'chain'))
    AND (NOT opt.website OR nullif(btrim(e.website), '') IS NOT NULL)
    AND (NOT opt.phone OR nullif(btrim(e.phone), '') IS NOT NULL)
    AND (opt.list_id IS NULL OR EXISTS (
            SELECT 1 FROM list_items li JOIN lists l ON l.id = li.list_id
            WHERE li.list_id = opt.list_id AND l.owner_id = viewer AND li.entity_id = e.id))
    AND (show_hidden OR viewer IS NULL OR NOT EXISTS (
            SELECT 1 FROM hidden_entities h WHERE h.user_id = viewer AND h.entity_id = e.id))
    AND (NOT (coalesce(only_favorites, false) OR coalesce(only_friends, false) OR coalesce(only_want, false))
         OR (only_favorites AND EXISTS (
               SELECT 1 FROM stars s WHERE s.user_id = viewer AND s.entity_id = e.id))
         OR (only_friends AND EXISTS (
               SELECT 1 FROM stars fs JOIN my_friends mf ON mf.friend_id = fs.user_id WHERE fs.entity_id = e.id))
         OR (only_want AND EXISTS (
               SELECT 1 FROM list_items li JOIN want_list w ON w.id = li.list_id WHERE li.entity_id = e.id)))
    AND (opt.q = ''
         OR e.name ILIKE '%' || opt.q || '%'
         OR (opt.close AND length(opt.q) >= 3 AND word_similarity(lower(opt.q), lower(e.name)) >= 0.5)
         OR (cardinality(opt.named) > 0
             AND (e.main_category_id = ANY (opt.named)
                  OR EXISTS (SELECT 1 FROM entity_categories ec
                             WHERE ec.entity_id = e.id AND ec.category_id = ANY (opt.named)))));
$$;
REVOKE ALL ON FUNCTION public.area_matches(double precision, double precision, double precision, double precision,
  public.ltree, text, boolean, boolean, boolean, boolean, uuid, jsonb) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- search_area
-- As in 20261112020000_map_area.sql, with `more`.
DROP FUNCTION public.search_area(double precision, double precision, double precision, double precision,
  double precision, double precision, public.ltree, text, boolean, boolean, boolean, boolean);
CREATE FUNCTION public.search_area(
    ref_lat double precision, ref_lng double precision,
    west double precision, south double precision, east double precision, north double precision,
    category_path public.ltree DEFAULT NULL, name_query text DEFAULT NULL,
    only_favorites boolean DEFAULT false, only_friends boolean DEFAULT false,
    only_want boolean DEFAULT false, show_hidden boolean DEFAULT false, more jsonb DEFAULT '{}'::jsonb)
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
                                                   only_favorites, only_friends, only_want, show_hidden,
                                                   ref.uid, more) m
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
  double precision, double precision, public.ltree, text, boolean, boolean, boolean, boolean, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_area(double precision, double precision, double precision, double precision,
  double precision, double precision, public.ltree, text, boolean, boolean, boolean, boolean, jsonb)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- area_cells
-- As in 20261112020000_map_area.sql, with `more`.
DROP FUNCTION public.area_cells(double precision, double precision, double precision, double precision,
  double precision, double precision, public.ltree, text, boolean, boolean, boolean, boolean);
CREATE FUNCTION public.area_cells(
    west double precision, south double precision, east double precision, north double precision,
    cell_lng double precision, cell_lat double precision,
    category_path public.ltree DEFAULT NULL, name_query text DEFAULT NULL,
    only_favorites boolean DEFAULT false, only_friends boolean DEFAULT false,
    only_want boolean DEFAULT false, show_hidden boolean DEFAULT false, more jsonb DEFAULT '{}'::jsonb)
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
                                                   only_favorites, only_friends, only_want, show_hidden,
                                                   ref.uid, more) m
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
  double precision, double precision, public.ltree, text, boolean, boolean, boolean, boolean, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.area_cells(double precision, double precision, double precision, double precision,
  double precision, double precision, public.ltree, text, boolean, boolean, boolean, boolean, jsonb)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- area_facets
-- As in 20261116000000_search_fixes.sql, with `more`. The existing counts keep their rules
-- (types leave out the type and cuisine; cuisines leave out the cuisine; favorites, friends and
-- Want to try leave out Show only), now inside the panel's filters. 'total' is every filter at
-- once (the "Show N places" button). With counts: streets (top 8), chain and independent,
-- website, phone and closed, each leaving out its own filter.
DROP FUNCTION public.area_facets(double precision, double precision, double precision, double precision,
  text, public.ltree, text, boolean, boolean, boolean, boolean);
CREATE FUNCTION public.area_facets(
    west double precision, south double precision, east double precision, north double precision,
    type_key text DEFAULT NULL, cuisine_path public.ltree DEFAULT NULL, name_query text DEFAULT NULL,
    only_favorites boolean DEFAULT false, only_friends boolean DEFAULT false,
    only_want boolean DEFAULT false, show_hidden boolean DEFAULT false, more jsonb DEFAULT '{}'::jsonb)
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH ref AS (SELECT auth.uid() AS uid),
  box AS MATERIALIZED (SELECT public.area_box(west, south, east, north) AS g),
  opt AS MATERIALIZED (SELECT * FROM public.area_options(more, name_query)),
  my_friends AS (
    SELECT DISTINCT CASE WHEN f.requester_id = ref.uid THEN f.addressee_id ELSE f.requester_id END AS friend_id
    FROM friendships f CROSS JOIN ref
    WHERE ref.uid IS NOT NULL AND f.status = 'accepted'
      AND (f.requester_id = ref.uid OR f.addressee_id = ref.uid)
  ),
  want_list AS (
    SELECT l.id FROM lists l CROSS JOIN ref WHERE ref.uid IS NOT NULL AND l.owner_id = ref.uid AND l.is_default_list
  ),
  cuisine_cats AS MATERIALIZED (
    SELECT c.id FROM categories c WHERE c.path <@ cuisine_path
    UNION
    SELECT unnest(opt.cuisine_ids) FROM opt
  ),
  area AS MATERIALIZED (
    SELECT e.id,
           (SELECT subpath(mc.path, 0, 1)::text FROM categories mc WHERE mc.id = e.main_category_id) AS root,
           (NOT EXISTS (SELECT 1 FROM cuisine_cats)
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
              SELECT 1 FROM hidden_entities h WHERE h.user_id = ref.uid AND h.entity_id = e.id)) AS hidden,
           e.status = 'permanently_closed' AS closed,
           CASE WHEN opt.chain IS NOT NULL OR opt.counts
                THEN EXISTS (SELECT 1 FROM chain_names cn WHERE cn.name_key = public.chain_key(e.name)) END AS chain,
           nullif(btrim(e.website), '') IS NOT NULL AS has_web,
           nullif(btrim(e.phone), '') IS NOT NULL AS has_phone,
           CASE WHEN opt.street IS NOT NULL OR opt.counts THEN public.street_key(e.address) END AS street,
           (opt.list_id IS NULL OR EXISTS (
              SELECT 1 FROM list_items li JOIN lists l ON l.id = li.list_id
              WHERE li.list_id = opt.list_id AND l.owner_id = ref.uid AND li.entity_id = e.id)) AS on_list
    FROM entities e
    CROSS JOIN ref
    CROSS JOIN box
    CROSS JOIN opt
    WHERE e.location && box.g
      AND ST_X(e.location::geometry) BETWEEN west AND east
      AND ST_Y(e.location::geometry) BETWEEN south AND north
      AND (e.status NOT IN ('permanently_closed', 'merged', 'removed')
           OR (e.status = 'permanently_closed' AND (opt.closed OR opt.counts)))
      AND (opt.shape IS NULL OR ST_Intersects(e.location::geometry, opt.shape))
      AND (opt.q = ''
           OR e.name ILIKE '%' || opt.q || '%'
           OR (opt.close AND length(opt.q) >= 3 AND word_similarity(lower(opt.q), lower(e.name)) >= 0.5)
           OR (cardinality(opt.named) > 0
               AND (e.main_category_id = ANY (opt.named)
                    OR EXISTS (SELECT 1 FROM entity_categories ec
                               WHERE ec.entity_id = e.id AND ec.category_id = ANY (opt.named)))))
  ),
  flt AS MATERIALIZED (
    SELECT a.*,
           (NOT (only_favorites OR only_friends OR only_want)
            OR (only_favorites AND a.fav) OR (only_friends AND a.friend) OR (only_want AND a.want)) AS p_status,
           (type_key IS NULL OR a.root = type_key) AS p_type,
           (opt.street IS NULL OR a.street LIKE opt.street || '%') AS p_street,
           (opt.chain IS NULL OR a.chain = (opt.chain = 'chain')) AS p_chain,
           (NOT opt.website OR a.has_web) AS p_web,
           (NOT opt.phone OR a.has_phone) AS p_phone,
           (opt.closed OR NOT a.closed) AS p_closed
    FROM area a CROSS JOIN opt
    WHERE a.on_list AND (show_hidden OR NOT a.hidden)
  ),
  more_ok AS (SELECT * FROM flt WHERE p_street AND p_chain AND p_web AND p_phone AND p_closed),
  status_ok AS (SELECT * FROM more_ok WHERE p_status),
  in_type AS (SELECT * FROM status_ok WHERE p_type),
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
  chosen AS (SELECT * FROM more_ok WHERE p_type AND in_cuisine),
  -- every filter but one, for the panel's own counts
  but AS (SELECT * FROM flt WHERE p_status AND p_type AND in_cuisine),
  street_counts AS (
    SELECT b.street, count(*)::integer AS n
    FROM but b CROSS JOIN opt
    WHERE opt.counts AND b.street IS NOT NULL AND b.p_chain AND b.p_web AND b.p_phone AND b.p_closed
    GROUP BY b.street
    ORDER BY count(*) DESC, b.street
    LIMIT 8
  )
  SELECT jsonb_build_object(
    'types', COALESCE((SELECT jsonb_object_agg(k, n) FROM type_counts), '{}'::jsonb),
    'cuisines', COALESCE((SELECT jsonb_agg(jsonb_build_object('path', path, 'name', name, 'n', n) ORDER BY path)
                          FROM cuisine_counts), '[]'::jsonb),
    'favorites', (SELECT count(*)::integer FROM chosen WHERE fav),
    'friends', (SELECT count(*)::integer FROM chosen WHERE friend),
    'want', (SELECT count(*)::integer FROM chosen WHERE want),
    'hidden', CASE WHEN show_hidden THEN 0 ELSE (
      SELECT count(*)::integer
      FROM area a CROSS JOIN opt
      WHERE a.hidden AND a.on_list AND (type_key IS NULL OR a.root = type_key) AND a.in_cuisine
        AND (NOT (only_favorites OR only_friends OR only_want)
             OR (only_favorites AND a.fav) OR (only_friends AND a.friend) OR (only_want AND a.want))
        AND (opt.street IS NULL OR a.street LIKE opt.street || '%')
        AND (opt.chain IS NULL OR a.chain = (opt.chain = 'chain'))
        AND (NOT opt.website OR a.has_web) AND (NOT opt.phone OR a.has_phone)
        AND (opt.closed OR NOT a.closed)) END,
    'total', (SELECT count(*)::integer FROM chosen WHERE p_status)
  ) || CASE WHEN (SELECT counts FROM opt) THEN jsonb_build_object(
    'streets', COALESCE((SELECT jsonb_agg(jsonb_build_object('street', street, 'label', initcap(street), 'n', n)
                                          ORDER BY n DESC, street) FROM street_counts), '[]'::jsonb),
    'chain', (SELECT jsonb_build_object(
                'chain', count(*) FILTER (WHERE chain)::integer,
                'independent', count(*) FILTER (WHERE NOT chain)::integer)
              FROM but WHERE p_street AND p_web AND p_phone AND p_closed),
    'website', (SELECT count(*)::integer FROM but WHERE has_web AND p_street AND p_chain AND p_phone AND p_closed),
    'phone', (SELECT count(*)::integer FROM but WHERE has_phone AND p_street AND p_chain AND p_web AND p_closed),
    'closed', (SELECT count(*)::integer FROM but WHERE closed AND p_street AND p_chain AND p_web AND p_phone)
  ) ELSE '{}'::jsonb END;
$$;
REVOKE ALL ON FUNCTION public.area_facets(double precision, double precision, double precision, double precision,
  text, public.ltree, text, boolean, boolean, boolean, boolean, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.area_facets(double precision, double precision, double precision, double precision,
  text, public.ltree, text, boolean, boolean, boolean, boolean, jsonb)
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- suggest_what
-- As in 20261112000000_results_page.sql, plus close spellings: when no place within 25 miles
-- has the typed text in its name, up to 3 of the nearest 5,000 places (within 25 miles) whose
-- names are close to it (word similarity 0.45 or more, closest first; 4 characters or more),
-- as kind 'close'.
CREATE OR REPLACE FUNCTION public.suggest_what(
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
  places AS MATERIALIZED (
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
  ),
  close AS (
    SELECT 'close'::text AS kind, e.name AS label, NULL::text AS path,
           (SELECT subpath(mc.path, 0, 1)::text FROM categories mc WHERE mc.id = e.main_category_id) AS type_key,
           e.id AS place_id, list_address(e.address, e.city) AS address,
           round((ST_Distance(e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography) / 1609.34)::numeric, 1) AS miles,
           row_number() OVER (ORDER BY e.sim DESC, e.meters, e.id) AS ord
    FROM (
      SELECT n.*, word_similarity(qn.t, lower(n.name)) AS sim,
             ST_Distance(n.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography) AS meters
      FROM (
        SELECT e.* FROM entities e CROSS JOIN qn
        WHERE ref_lat IS NOT NULL AND ref_lng IS NOT NULL AND length(qn.t) >= 4
          AND NOT EXISTS (SELECT 1 FROM places)
          AND e.status NOT IN ('permanently_closed', 'merged', 'removed')
          AND ST_DWithin(e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography, 25 * 1609.34)
        ORDER BY e.location <-> ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography
        LIMIT 5000
      ) n CROSS JOIN qn
      WHERE word_similarity(qn.t, lower(n.name)) >= 0.45
        AND (auth.uid() IS NULL OR NOT EXISTS (
               SELECT 1 FROM hidden_entities h WHERE h.user_id = auth.uid() AND h.entity_id = n.id))
      ORDER BY word_similarity(qn.t, lower(n.name)) DESC,
               n.location <-> ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography, n.id
      LIMIT 3
    ) e
  )
  SELECT kind, label, path, type_key, place_id, address, miles
  FROM (SELECT *, 0 AS grp FROM kinds WHERE ord <= 4
        UNION ALL SELECT *, 1 AS grp FROM places
        UNION ALL SELECT *, 2 AS grp FROM close) s
  ORDER BY grp, ord;
$$;
