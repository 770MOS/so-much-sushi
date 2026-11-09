-- Search picks the nearest places first (agreed 2026-11-08).
--
-- Before: every place inside the circle had its stars, hidden mark, friends' recommendations
-- and tags worked out, then all of them were sorted by distance, and only then did the API keep
-- the nearest 1,000. In a big city that meant working out tens of thousands of places to show
-- 1,000 of them.
--
-- Now:
--   * matching places are found and counted using only the filters (no per-place details);
--   * the nearest 1,000 are kept, closest first, with ties broken by name and then id so the
--     order is the same every time;
--   * stars, hidden marks, friends' recommendations and tags are worked out for those 1,000 only;
--   * every row carries total_count, how many places matched in all, so the page can say
--     "the nearest 1,000 of 12,400".
--
-- The parameters are unchanged, so the app works before and after this migration. The return
-- type gains total_count, which CREATE OR REPLACE cannot do, so the function is dropped and
-- created again (see supabase/grants_reference.sql), and its grants are set again from zero.
SET search_path = public, extensions;

DROP FUNCTION public.search_entities(double precision, double precision, double precision,
                                     public.ltree, boolean, boolean, boolean, text);

CREATE FUNCTION public.search_entities(
    ref_lat double precision, ref_lng double precision, radius_miles double precision,
    category_path public.ltree DEFAULT NULL, show_hidden boolean DEFAULT false,
    recommended_only boolean DEFAULT false, starred_only boolean DEFAULT false,
    name_query text DEFAULT NULL)
  RETURNS TABLE(id uuid, name text, address text, miles numeric, lat double precision, lng double precision,
                is_starred boolean, is_hidden boolean, recommended_by jsonb, recommended_count integer,
                status text, categories text[], category_paths text[], total_count integer)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH ref AS (
    SELECT ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography AS g, auth.uid() AS uid
  ),
  -- The signed-in person's accepted friends, worked out once rather than once per place.
  my_friends AS (
    SELECT DISTINCT CASE WHEN f.requester_id = ref.uid THEN f.addressee_id ELSE f.requester_id END AS friend_id
    FROM friendships f CROSS JOIN ref
    WHERE ref.uid IS NOT NULL AND f.status = 'accepted'
      AND (f.requester_id = ref.uid OR f.addressee_id = ref.uid)
  ),
  -- Every matching place, with only what is needed to count and order them.
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
              SELECT 1 FROM hidden_entities h WHERE h.entity_id = e.id AND h.user_id = ref.uid))
      AND (NOT recommended_only OR EXISTS (
              SELECT 1 FROM stars fs JOIN my_friends mf ON mf.friend_id = fs.user_id
              WHERE fs.entity_id = e.id))
      AND (NOT starred_only OR EXISTS (
              SELECT 1 FROM stars s WHERE s.entity_id = e.id AND s.user_id = ref.uid))
      AND (name_query IS NULL OR trim(name_query) = '' OR e.name ILIKE '%' || trim(name_query) || '%')
  ),
  -- MATERIALIZED: worked out once. Left to itself the planner can re-count every match once
  -- per row returned (seen on a 33,000-place test: 1,000 recounts, 3.6 s instead of 0.2 s).
  total AS MATERIALIZED (SELECT count(*)::integer AS n FROM hits),
  nearest AS (
    SELECT h.id, h.meters FROM hits h ORDER BY h.meters, h.name, h.id LIMIT 1000
  )
  SELECT
    e.id, e.name, list_address(e.address, e.city) AS address,
    round((n.meters / 1609.34)::numeric, 2) AS miles,
    ST_Y(e.location::geometry) AS lat,
    ST_X(e.location::geometry) AS lng,
    EXISTS (SELECT 1 FROM stars s WHERE s.entity_id = e.id AND s.user_id = ref.uid) AS is_starred,
    EXISTS (SELECT 1 FROM hidden_entities h WHERE h.entity_id = e.id AND h.user_id = ref.uid) AS is_hidden,
    (
      SELECT jsonb_agg(jsonb_build_object('name', t.name, 'handle', t.handle) ORDER BY t.starred_at)
      FROM (
        SELECT COALESCE(p.display_name, p.handle) AS name, p.handle AS handle, fs.created_at AS starred_at
        FROM stars fs
        JOIN my_friends mf ON mf.friend_id = fs.user_id
        JOIN profiles p ON p.id = fs.user_id
        WHERE fs.entity_id = e.id
        ORDER BY fs.created_at
        LIMIT 2
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

REVOKE ALL ON FUNCTION public.search_entities(double precision, double precision, double precision,
                                              public.ltree, boolean, boolean, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_entities(double precision, double precision, double precision,
                                                 public.ltree, boolean, boolean, boolean, text)
  TO anon, authenticated, service_role;
