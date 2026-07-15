-- Changes recommended_by on search_entities() and get_my_starred_entities()
-- from a flat text[] of already-resolved display strings to a jsonb array
-- of {name, handle} objects - the "Starred by X" label needs to link each
-- name to /u/[handle], and a bare display string discards which user it
-- was (names aren't unique, and there was no id/handle carried alongside
-- it to recover that afterward).
--
-- Changing a RETURNS TABLE column's type requires DROP + CREATE, not just
-- CREATE OR REPLACE (Postgres won't let you change an existing function's
-- return shape in place) - both DROPs are included so this file replays
-- cleanly against a fresh database or the current one.
--
-- IMPORTANT: search_entities is the one function in this project meant to
-- keep its default PUBLIC execute grant (see grants_reference.sql) - it's
-- supposed to be anon-callable (Discover/Search/home pages work logged
-- out), and PUBLIC being left alone is also what lets service_role call it
-- without an explicit grant. An earlier draft of this file mechanically
-- added `REVOKE EXECUTE ... FROM PUBLIC` here, which broke that (real
-- anon/authenticated app users were unaffected, since they're granted
-- explicitly either way - it silently broke service_role-based tooling
-- instead). Do not revoke PUBLIC on search_entities.
--
-- Safe to re-run (idempotent).

DROP FUNCTION IF EXISTS public.search_entities(double precision, double precision, double precision, ltree, boolean, boolean, boolean, text);

CREATE OR REPLACE FUNCTION public.search_entities(ref_lat double precision, ref_lng double precision, radius_miles double precision, category_path ltree DEFAULT NULL::ltree, show_hidden boolean DEFAULT false, recommended_only boolean DEFAULT false, starred_only boolean DEFAULT false, name_query text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, name text, address text, miles numeric, lat double precision, lng double precision, is_starred boolean, is_hidden boolean, recommended_by jsonb, recommended_count integer, status text, categories text[])
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
        ) AS categories
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

-- No REVOKE FROM PUBLIC here - see the note at the top of this file.
GRANT EXECUTE ON FUNCTION search_entities(
  double precision, double precision, double precision, ltree, boolean, boolean, boolean, text
) TO anon, authenticated;

DROP FUNCTION IF EXISTS public.get_my_starred_entities();

CREATE OR REPLACE FUNCTION public.get_my_starred_entities()
 RETURNS TABLE(id uuid, name text, address text, city text, state text, lat double precision, lng double precision, type_name text, cuisine_name text, recommended_by jsonb, recommended_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
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
        ) AS recommended_count
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

NOTIFY pgrst, 'reload schema';
