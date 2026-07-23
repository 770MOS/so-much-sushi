-- get_entity_detail: powers the standalone /venue/[id] page and its
-- intercepted modal equivalent (see src/app/(with-sidebar)/venue/[id] and
-- src/app/(with-sidebar)/@modal/(.)venue/[id]). Returns one row for a
-- given entity id with everything that page needs: full contact/hours
-- fields (entities/entity_categories aren't otherwise readable directly -
-- see the REVOKE ALL note in grants_reference.sql), lat/lng computed the
-- same way search_entities does, the caller's own is_starred, and a sorted
-- categories array.
--
-- Deliberately anon-callable, same reasoning and same documented exception
-- as search_entities in grants_reference.sql: venue pages need to work for
-- signed-out visitors (direct links, search engine crawlers hitting
-- sitemap.xml - see src/app/sitemap.ts) not just signed-in users. PUBLIC is
-- intentionally left alone below, not revoked.
--
-- Returns zero rows (not an error) for an id that doesn't exist, so the
-- page can call notFound() either way without a special-case error branch.
--
-- hours is declared jsonb, not text - entities.hours is actually jsonb
-- (confirmed via the live PostgREST schema definitions, format: "jsonb"),
-- despite being null on every row today since it's never been populated.
-- An earlier draft of this file declared it as text before that was
-- checked, which would have been a real RETURNS TABLE type mismatch.
--
-- category_paths (ltree paths as text, added in
-- supabase/add_category_paths_to_map_queries.sql) lets the venue page's
-- single-pin map pick a marker icon via
-- src/lib/entityTypes.ts's topLevelTypeForCategoryPaths - a plain
-- Restaurant and a Bakery share no distinguishing display name, only path
-- (restaurants vs restaurants.bakery).
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

CREATE OR REPLACE FUNCTION public.get_entity_detail(p_entity_id uuid)
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

-- CREATE FUNCTION grants EXECUTE to PUBLIC by default - kept intentionally,
-- see note above. Do not add a REVOKE EXECUTE ... FROM PUBLIC here despite
-- that being the standing rule for every other SECURITY DEFINER function in
-- this project (grants_reference.sql) - this is the second deliberate
-- exception alongside search_entities.
GRANT EXECUTE ON FUNCTION public.get_entity_detail(uuid) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
