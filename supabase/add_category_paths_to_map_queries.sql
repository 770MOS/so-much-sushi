-- Adds category_paths (ltree paths, not display names) to the three
-- lookup functions that feed EntityMap markers: search_entities (search/
-- discover/home/starred/recommended pages), get_my_starred_entities
-- (Profile Starred map), and get_entity_detail (venue page). Lets the
-- frontend classify each entity into one of the 5 marker-icon types
-- (restaurants/bars/coffee/bakeries/breweries - see
-- src/lib/entityTypes.ts's topLevelTypeForCategoryPaths) without guessing
-- from display names, since Bakeries/Breweries aren't root categories -
-- they're specific descendants (restaurants.bakery, bars.brewery) and
-- can only be told apart from a plain Restaurant/Bar by looking at the
-- actual path, not the category name string.
--
-- Deliberately a NEW column alongside the existing `categories` (display
-- names, e.g. "Bakery and dessert") rather than repurposing it - existing
-- consumers (search result rows, the profile map's type/cuisine dropdowns)
-- already rely on `categories`/`type_name` being human-readable, and
-- changing that to raw paths would break their display.
--
-- All three required DROP FUNCTION first, not just CREATE OR REPLACE -
-- adding a RETURNS TABLE column is a return-shape change, which Postgres
-- refuses in place (see the same note in supabase/search_entities.sql).
-- DROP FUNCTION also drops that function's grants, so every GRANT/REVOKE
-- each one already had is reissued below exactly as before - see
-- supabase/grants_reference.sql for why each one is (or isn't) PUBLIC.
--
-- Also fixes an inconsistency noticed while reviewing this file before it
-- was run: get_my_starred_entities calls ST_Y/ST_X (PostGIS, lives in the
-- extensions schema) same as search_entities and get_entity_detail, but -
-- unlike those two - never had an explicit SET search_path = public,
-- extensions. It's worked without one in practice, but that's an
-- accident of whatever search_path happens to apply by default, not a
-- guarantee - added here for the same reason the other two have it.
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

DROP FUNCTION IF EXISTS public.search_entities(double precision, double precision, double precision, ltree, boolean, boolean, boolean, text);

CREATE FUNCTION public.search_entities(ref_lat double precision, ref_lng double precision, radius_miles double precision, category_path ltree DEFAULT NULL::ltree, show_hidden boolean DEFAULT false, recommended_only boolean DEFAULT false, starred_only boolean DEFAULT false, name_query text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, name text, address text, miles numeric, lat double precision, lng double precision, is_starred boolean, is_hidden boolean, recommended_by jsonb, recommended_count integer, status text, categories text[], category_paths text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
    SELECT DISTINCT
        e.id, e.name, e.address,
        round((ST_Distance(
            e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography
        ) / 1609.34)::numeric, 2) AS miles,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        EXISTS (
            SELECT 1 FROM stars s
            WHERE s.entity_id = e.id AND s.user_id = auth.uid()
        ) AS is_starred,
        EXISTS (
            SELECT 1 FROM hidden_entities h
            WHERE h.entity_id = e.id AND h.user_id = auth.uid()
        ) AS is_hidden,
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
        (
            SELECT array_agg(cat.name ORDER BY cat.name)
            FROM entity_categories ec2
            JOIN categories cat ON cat.id = ec2.category_id
            WHERE ec2.entity_id = e.id
        ) AS categories,
        (
            SELECT array_agg(cat3.path::text ORDER BY cat3.path)
            FROM entity_categories ec3
            JOIN categories cat3 ON cat3.id = ec3.category_id
            WHERE ec3.entity_id = e.id
        ) AS category_paths
    FROM entities e
    JOIN entity_categories ec ON ec.entity_id = e.id
    JOIN categories c         ON c.id = ec.category_id
    WHERE (category_path IS NULL OR c.path <@ category_path)
      AND e.status <> 'permanently_closed'
      AND ST_DWithin(
          e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography,
          radius_miles * 1609.34
      )
      AND (
          show_hidden
          OR NOT EXISTS (
              SELECT 1 FROM hidden_entities h2
              WHERE h2.entity_id = e.id AND h2.user_id = auth.uid()
          )
      )
      AND (
          NOT recommended_only
          OR EXISTS (
              SELECT 1 FROM stars fs3
              JOIN friendships f3 ON (
                  (f3.requester_id = auth.uid() AND f3.addressee_id = fs3.user_id)
                  OR (f3.addressee_id = auth.uid() AND f3.requester_id = fs3.user_id)
              )
              WHERE fs3.entity_id = e.id AND f3.status = 'accepted'
          )
      )
      AND (
          NOT starred_only
          OR EXISTS (
              SELECT 1 FROM stars s4
              WHERE s4.entity_id = e.id AND s4.user_id = auth.uid()
          )
      )
      AND (
          name_query IS NULL
          OR trim(name_query) = ''
          OR e.name ILIKE '%' || trim(name_query) || '%'
      )
    ORDER BY miles;
$function$;

GRANT EXECUTE ON FUNCTION search_entities(
  double precision, double precision, double precision, ltree, boolean, boolean, boolean, text
) TO anon, authenticated;

DROP FUNCTION IF EXISTS public.get_my_starred_entities();

CREATE FUNCTION public.get_my_starred_entities()
 RETURNS TABLE(id uuid, name text, address text, city text, state text, lat double precision, lng double precision, type_name text, cuisine_name text, recommended_by jsonb, recommended_count integer, category_paths text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
    SELECT
        e.id, e.name, e.address, e.city, e.state,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        top.name AS type_name,
        c.name AS cuisine_name,
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
        (
            SELECT array_agg(cat2.path::text ORDER BY cat2.path)
            FROM entity_categories ec2
            JOIN categories cat2 ON cat2.id = ec2.category_id
            WHERE ec2.entity_id = e.id
        ) AS category_paths
    FROM stars s
    JOIN entities e            ON e.id = s.entity_id
    JOIN entity_categories ec  ON ec.entity_id = e.id
    JOIN categories c          ON c.id = ec.category_id
    JOIN categories top        ON top.path = subpath(c.path, 0, 1)
    WHERE s.user_id = auth.uid()
    ORDER BY e.name;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_starred_entities() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_starred_entities() TO authenticated;

DROP FUNCTION IF EXISTS public.get_entity_detail(uuid);

CREATE FUNCTION public.get_entity_detail(p_entity_id uuid)
 RETURNS TABLE(
   id uuid,
   name text,
   address text,
   phone text,
   website text,
   hours jsonb,
   attributes jsonb,
   status text,
   lat double precision,
   lng double precision,
   is_starred boolean,
   categories text[],
   category_paths text[]
 )
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
    SELECT
        e.id, e.name, e.address, e.phone, e.website, e.hours, e.attributes,
        e.status,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        EXISTS (
            SELECT 1 FROM stars s
            WHERE s.entity_id = e.id AND s.user_id = auth.uid()
        ) AS is_starred,
        (
            SELECT array_agg(cat.name ORDER BY cat.name)
            FROM entity_categories ec
            JOIN categories cat ON cat.id = ec.category_id
            WHERE ec.entity_id = e.id
        ) AS categories,
        (
            SELECT array_agg(cat2.path::text ORDER BY cat2.path)
            FROM entity_categories ec2
            JOIN categories cat2 ON cat2.id = ec2.category_id
            WHERE ec2.entity_id = e.id
        ) AS category_paths
    FROM entities e
    WHERE e.id = p_entity_id;
$function$;

GRANT EXECUTE ON FUNCTION public.get_entity_detail(uuid) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
