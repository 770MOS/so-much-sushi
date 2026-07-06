-- search_entities: the main search RPC, powering the root search page.
-- Never previously tracked in git despite being modified live in the SQL
-- Editor several times this session (originally returned a boolean
-- is_recommended; later replaced with recommended_by/recommended_count;
-- lat/lng added most recently to support the search page's Map view) -
-- this file is the first tracked record of it, confirmed verbatim via
-- `SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname =
-- 'search_entities';` against the live, already-working function.
--
-- NOTE: this definition does NOT include `SET search_path = public`,
-- which was recommended earlier this session when the function was first
-- made SECURITY DEFINER (via a plain ALTER FUNCTION at the time). A later
-- CREATE OR REPLACE fully redefined the function and didn't carry that
-- clause forward - ALTER and CREATE OR REPLACE don't share state. Worth
-- adding `SET search_path = public` next time this function is touched,
-- to close the search-path-hijacking gap; not changed here since this
-- file is meant to mirror exactly what's live, not silently patch it.
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

CREATE OR REPLACE FUNCTION public.search_entities(ref_lat double precision, ref_lng double precision, radius_miles double precision, category_path ltree DEFAULT NULL::ltree, show_hidden boolean DEFAULT false, recommended_only boolean DEFAULT false)
 RETURNS TABLE(id uuid, name text, address text, miles numeric, lat double precision, lng double precision, is_starred boolean, is_hidden boolean, recommended_by text[], recommended_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
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
            SELECT array_agg(name ORDER BY starred_at)
            FROM (
                SELECT COALESCE(p.display_name, p.handle) AS name, fs.created_at AS starred_at
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
        ) AS recommended_count
    FROM entities e
    JOIN entity_categories ec ON ec.entity_id = e.id
    JOIN categories c         ON c.id = ec.category_id
    WHERE (category_path IS NULL OR c.path <@ category_path)
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
    ORDER BY miles;
$function$;

GRANT EXECUTE ON FUNCTION search_entities(
  double precision, double precision, double precision, ltree, boolean, boolean
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
