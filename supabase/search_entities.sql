-- search_entities: the main search RPC, powering the root search page,
-- the Starred/Recommended quick views, and the sidebar's name-only Search
-- page.
--
-- This is a live mirror, not an incremental migration - replace this file's
-- contents whenever the function changes live, confirmed verbatim via
-- `SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname =
-- 'search_entities';` against the actual running function. Do not hand-edit
-- this file and assume it's live without re-confirming that way.
--
-- Current state includes, relative to earlier tracked versions:
--   - `starred_only` and `name_query` parameters (name_query does a
--     case-insensitive substring match on entities.name, for the Search
--     page - a very large radius plus name_query means distance/category
--     never hide a place the user is looking up by name).
--   - `status`, `categories` (alphabetically sorted name array), and
--     `category_paths` (ltree paths as text, e.g. "restaurants.bakery" -
--     added in supabase/add_category_paths_to_map_queries.sql so
--     EntityMap can pick a marker icon via
--     src/lib/entityTypes.ts's topLevelTypeForCategoryPaths, since
--     Bakeries/Breweries aren't root categories and can't be told apart
--     from a plain Restaurant/Bar by display name alone) output columns.
--   - `e.status <> 'permanently_closed'` is now always excluded from
--     results, regardless of show_hidden.
--   - `SET search_path = public, extensions` - required because PostGIS
--     (ST_Distance, ST_MakePoint, etc.) lives in the `extensions` schema in
--     this project, not `public`. An earlier draft of the name_query change
--     used `SET search_path = public` alone, which breaks unqualified
--     PostGIS calls - fixed before this was applied live.
--   - `recommended_by` is now `jsonb` (an array of {name, handle} objects),
--     not `text[]` of already-resolved display strings - needed so the
--     frontend's "Starred by X" label can link each name to /u/[handle]
--     (see supabase/add_handle_to_recommended_by.sql). A flat display
--     string discards which user it was; names aren't unique.
--
-- Adding a new parameter to a SECURITY DEFINER function via CREATE OR
-- REPLACE only replaces the existing function if the parameter list
-- matches exactly - otherwise Postgres registers a second overload
-- alongside the old one, and PostgREST can no longer tell them apart
-- (PGRST203, "Could not choose the best candidate function"). That's
-- exactly what happened when name_query was first added here: the old
-- 7-arg overload had to be dropped explicitly afterward -
-- `DROP FUNCTION public.search_entities(double precision, double
-- precision, double precision, ltree, boolean, boolean, boolean);` - before
-- search worked again anywhere in the app. Worth remembering next time this
-- function's parameter list changes.
--
-- CHANGING A RETURN COLUMN'S TYPE (as when recommended_by went from
-- text[] to jsonb) needs the same DROP-first treatment, even though the
-- parameter list didn't change - CREATE OR REPLACE refuses outright with a
-- syntax-adjacent error if the return shape differs, rather than silently
-- creating a duplicate overload the way a parameter-list change does.
--
-- Also: search_entities is the one function in this project meant to keep
-- its default PUBLIC execute grant (see grants_reference.sql) - it's
-- supposed to be anon-callable (Discover/Search/home pages work logged
-- out), and PUBLIC being left alone is also what lets service_role call it
-- without an explicit grant. Don't add `REVOKE EXECUTE ... FROM PUBLIC`
-- here even though that's the standing rule for every other SECURITY
-- DEFINER function - doing so once by mistake didn't affect real anon/
-- authenticated app users (they're granted explicitly either way), but
-- silently broke service_role-based verification tooling until reverted.
--
-- Safe to re-run (idempotent) if replayed against a fresh database that
-- already has the 8-arg signature; on a database still holding the old
-- 7-arg overload, drop that first (see above) or this replay will
-- reproduce the same ambiguity.

CREATE OR REPLACE FUNCTION public.search_entities(ref_lat double precision, ref_lng double precision, radius_miles double precision, category_path ltree DEFAULT NULL::ltree, show_hidden boolean DEFAULT false, recommended_only boolean DEFAULT false, starred_only boolean DEFAULT false, name_query text DEFAULT NULL::text)
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

NOTIFY pgrst, 'reload schema';
