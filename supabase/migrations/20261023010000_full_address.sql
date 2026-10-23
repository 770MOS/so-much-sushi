-- Addresses as people read them (agreed 2026-10-23):
--   * lists and map pins: street and town, "1401 Wilson Blvd Ste 110 · Arlington";
--   * the place page: the full address, "1401 Wilson Blvd Ste 110, Arlington, VA 22209".
-- The functions keep their columns; only the text in "address" changes. Raw town and
-- state stay in their own columns where a function already returned them.
-- When neighbourhoods are added they replace the town for large cities.
SET search_path = public, extensions;

CREATE FUNCTION public.display_address(p_address text, p_city text, p_state text, p_postal text)
  RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path TO '' AS $$
  SELECT CASE
    -- Some sources already put the town in the street line.
    WHEN a IS NOT NULL AND c IS NOT NULL AND strpos(lower(a), lower(', ' || c)) > 0 THEN a
    ELSE NULLIF(concat_ws(', ', a, c, NULLIF(concat_ws(' ', s, z), '')), '') END
  FROM (SELECT NULLIF(trim(p_address), '') AS a, NULLIF(trim(p_city), '') AS c, NULLIF(trim(p_state), '') AS s,
               COALESCE(substring(p_postal from '^\s*(\d{5})'), NULLIF(trim(p_postal), '')) AS z) t;
$$;
GRANT EXECUTE ON FUNCTION public.display_address(text, text, text, text) TO anon, authenticated, service_role;

CREATE FUNCTION public.list_address(p_address text, p_city text)
  RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path TO '' AS $$
  SELECT NULLIF(concat_ws(' · ',
           NULLIF(trim(CASE WHEN a IS NOT NULL AND c IS NOT NULL AND strpos(lower(a), lower(', ' || c)) > 0
                            THEN left(a, strpos(lower(a), lower(', ' || c)) - 1) ELSE a END), ''),
           c), '')
  FROM (SELECT NULLIF(trim(p_address), '') AS a, NULLIF(trim(p_city), '') AS c) t;
$$;
GRANT EXECUTE ON FUNCTION public.list_address(text, text) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.search_entities(
    ref_lat double precision, ref_lng double precision, radius_miles double precision,
    category_path public.ltree DEFAULT NULL, show_hidden boolean DEFAULT false,
    recommended_only boolean DEFAULT false, starred_only boolean DEFAULT false,
    name_query text DEFAULT NULL)
  RETURNS TABLE(id uuid, name text, address text, miles numeric, lat double precision, lng double precision,
                is_starred boolean, is_hidden boolean, recommended_by jsonb, recommended_count integer,
                status text, categories text[], category_paths text[])
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
    SELECT
        e.id, e.name, list_address(e.address, e.city) AS address,
        round((ST_Distance(
            e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography
        ) / 1609.34)::numeric, 2) AS miles,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        EXISTS (SELECT 1 FROM stars s WHERE s.entity_id = e.id AND s.user_id = auth.uid()) AS is_starred,
        EXISTS (SELECT 1 FROM hidden_entities h WHERE h.entity_id = e.id AND h.user_id = auth.uid()) AS is_hidden,
        (
            SELECT jsonb_agg(jsonb_build_object('name', name, 'handle', handle) ORDER BY starred_at)
            FROM (
                SELECT COALESCE(p.display_name, p.handle) AS name, p.handle AS handle, fs.created_at AS starred_at
                FROM stars fs
                JOIN profiles p ON p.id = fs.user_id
                JOIN friendships f ON (
                    (f.requester_id = auth.uid() AND f.addressee_id = fs.user_id)
                    OR (f.addressee_id = auth.uid() AND f.requester_id = fs.user_id)
                )
                WHERE fs.entity_id = e.id AND f.status = 'accepted'
                ORDER BY fs.created_at
                LIMIT 2
            ) top_two
        ) AS recommended_by,
        (
            SELECT count(*)::integer
            FROM stars fs2
            JOIN friendships f2 ON (
                (f2.requester_id = auth.uid() AND f2.addressee_id = fs2.user_id)
                OR (f2.addressee_id = auth.uid() AND f2.requester_id = fs2.user_id)
            )
            WHERE fs2.entity_id = e.id AND f2.status = 'accepted'
        ) AS recommended_count,
        e.status,
        ARRAY[mc.name] || COALESCE((
            SELECT array_agg(cat.name ORDER BY cat.path)
            FROM entity_categories ec2 JOIN categories cat ON cat.id = ec2.category_id
            WHERE ec2.entity_id = e.id AND cat.id <> mc.id), '{}') AS categories,
        ARRAY[mc.path::text] || COALESCE((
            SELECT array_agg(cat3.path::text ORDER BY cat3.path)
            FROM entity_categories ec3 JOIN categories cat3 ON cat3.id = ec3.category_id
            WHERE ec3.entity_id = e.id AND cat3.id <> mc.id), '{}') AS category_paths
    FROM entities e
    JOIN categories mc ON mc.id = e.main_category_id
    WHERE (category_path IS NULL
           OR mc.path <@ category_path
           OR EXISTS (SELECT 1 FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
                      WHERE ec.entity_id = e.id AND c.path <@ category_path))
      AND e.status NOT IN ('permanently_closed', 'merged', 'removed')
      AND ST_DWithin(
          e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography,
          radius_miles * 1609.34
      )
      AND (show_hidden OR NOT EXISTS (
              SELECT 1 FROM hidden_entities h2 WHERE h2.entity_id = e.id AND h2.user_id = auth.uid()))
      AND (NOT recommended_only OR EXISTS (
              SELECT 1 FROM stars fs3
              JOIN friendships f3 ON (
                  (f3.requester_id = auth.uid() AND f3.addressee_id = fs3.user_id)
                  OR (f3.addressee_id = auth.uid() AND f3.requester_id = fs3.user_id)
              )
              WHERE fs3.entity_id = e.id AND f3.status = 'accepted'))
      AND (NOT starred_only OR EXISTS (
              SELECT 1 FROM stars s4 WHERE s4.entity_id = e.id AND s4.user_id = auth.uid()))
      AND (name_query IS NULL OR trim(name_query) = '' OR e.name ILIKE '%' || trim(name_query) || '%')
    ORDER BY miles;
$$;

CREATE OR REPLACE FUNCTION public.get_entity_detail(p_entity_id uuid)
  RETURNS TABLE(id uuid, name text, address text, phone text, website text, hours jsonb, attributes jsonb,
                status text, lat double precision, lng double precision, is_starred boolean,
                categories text[], category_paths text[])
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
    SELECT
        e.id, e.name, display_address(e.address, e.city, e.state, e.postal_code) AS address, e.phone, e.website, e.hours, e.attributes,
        e.status,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        EXISTS (SELECT 1 FROM stars s WHERE s.entity_id = e.id AND s.user_id = auth.uid()) AS is_starred,
        ARRAY[mc.name] || COALESCE((
            SELECT array_agg(cat.name ORDER BY cat.path)
            FROM entity_categories ec JOIN categories cat ON cat.id = ec.category_id
            WHERE ec.entity_id = e.id AND cat.id <> mc.id), '{}') AS categories,
        ARRAY[mc.path::text] || COALESCE((
            SELECT array_agg(cat2.path::text ORDER BY cat2.path)
            FROM entity_categories ec2 JOIN categories cat2 ON cat2.id = ec2.category_id
            WHERE ec2.entity_id = e.id AND cat2.id <> mc.id), '{}') AS category_paths
    FROM entities e
    JOIN categories mc ON mc.id = e.main_category_id
    WHERE e.id = resolve_entity(p_entity_id);
$$;

CREATE OR REPLACE FUNCTION public.get_my_starred_entities()
  RETURNS TABLE(id uuid, name text, address text, city text, state text, lat double precision, lng double precision,
                type_name text, cuisine_name text, recommended_by jsonb, recommended_count integer, category_paths text[])
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
    SELECT
        e.id, e.name, list_address(e.address, e.city) AS address, e.city, e.state,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        mc.name AS type_name,
        COALESCE(sub.name, mc.name) AS cuisine_name,
        (
            SELECT jsonb_agg(jsonb_build_object('name', name, 'handle', handle) ORDER BY starred_at)
            FROM (
                SELECT COALESCE(p.display_name, p.handle) AS name, p.handle AS handle, fs.created_at AS starred_at
                FROM stars fs
                JOIN profiles p ON p.id = fs.user_id
                JOIN friendships f ON (
                    (f.requester_id = auth.uid() AND f.addressee_id = fs.user_id)
                    OR (f.addressee_id = auth.uid() AND f.requester_id = fs.user_id)
                )
                WHERE fs.entity_id = e.id AND f.status = 'accepted'
                ORDER BY fs.created_at
                LIMIT 2
            ) top_two
        ) AS recommended_by,
        (
            SELECT count(*)::integer
            FROM stars fs2
            JOIN friendships f2 ON (
                (f2.requester_id = auth.uid() AND f2.addressee_id = fs2.user_id)
                OR (f2.addressee_id = auth.uid() AND f2.requester_id = fs2.user_id)
            )
            WHERE fs2.entity_id = e.id AND f2.status = 'accepted'
        ) AS recommended_count,
        ARRAY[mc.path::text] || COALESCE((
            SELECT array_agg(cat2.path::text ORDER BY cat2.path)
            FROM entity_categories ec2 JOIN categories cat2 ON cat2.id = ec2.category_id
            WHERE ec2.entity_id = e.id AND cat2.id <> mc.id), '{}') AS category_paths
    FROM stars s
    JOIN entities e    ON e.id = s.entity_id
    JOIN categories mc ON mc.id = e.main_category_id
    LEFT JOIN LATERAL (
        SELECT c.name FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
        WHERE ec.entity_id = e.id AND c.id <> mc.id ORDER BY nlevel(c.path) DESC, c.path LIMIT 1) sub ON true
    WHERE s.user_id = auth.uid()
    ORDER BY e.name;
$$;

CREATE OR REPLACE FUNCTION "public"."get_list_entities"("p_list_id" "uuid") RETURNS TABLE("entity_id" "uuid", "name" "text", "address" "text", "city" "text", "state" "text", "lat" double precision, "lng" double precision, "added_at" timestamp with time zone, "status" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
    SELECT e.id AS entity_id, e.name, list_address(e.address, e.city) AS address, e.city, e.state,
           ST_Y(e.location::geometry) AS lat, ST_X(e.location::geometry) AS lng,
           li.added_at, e.status
    FROM lists l
    JOIN list_items li ON li.list_id = l.id
    JOIN entities e ON e.id = li.entity_id
    WHERE l.id = p_list_id
      AND (
        l.owner_id = auth.uid()
        OR l.visibility = 'public'
        OR (
          l.visibility = 'friends'
          AND EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'accepted'
              AND ((f.requester_id = auth.uid() AND f.addressee_id = l.owner_id)
                OR (f.addressee_id = auth.uid() AND f.requester_id = l.owner_id))
          )
        )
      )
    ORDER BY li.added_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_profile_starred_entities(target_user_id uuid)
  RETURNS TABLE(id uuid, name text, address text, city text, state text, lat double precision, lng double precision,
                type_name text, cuisine_name text, status text)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
    SELECT
        e.id, e.name, list_address(e.address, e.city) AS address, e.city, e.state,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        mc.name AS type_name,
        COALESCE(sub.name, mc.name) AS cuisine_name,
        e.status
    FROM stars s
    JOIN entities e    ON e.id = s.entity_id
    JOIN categories mc ON mc.id = e.main_category_id
    LEFT JOIN LATERAL (
        SELECT c.name FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
        WHERE ec.entity_id = e.id AND c.id <> mc.id ORDER BY nlevel(c.path) DESC, c.path LIMIT 1) sub ON true
    WHERE s.user_id = target_user_id
      AND (
          target_user_id = auth.uid()
          OR EXISTS (
              SELECT 1 FROM friendships f
              WHERE f.status = 'accepted'
                AND (
                    (f.requester_id = auth.uid() AND f.addressee_id = target_user_id)
                    OR (f.addressee_id = auth.uid() AND f.requester_id = target_user_id)
                )
          )
      )
    ORDER BY e.name;
$$;
