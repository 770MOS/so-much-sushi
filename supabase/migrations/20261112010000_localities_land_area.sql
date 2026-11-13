-- Opening a picked town on the whole town (build step 3, decided 2026-11-10).
--
-- The results page no longer has a distance menu: picking a city, town or ZIP code opens the
-- map on that place. To know how much map that is, each place on the list now carries its
-- land area from the same Census Gazetteer files (ALAND, square metres; New York City's
-- boroughs, added by hand, carry their 2020 land areas). The list has to be loaded again
-- ("Load place-name list" workflow) to fill it in; until then it is empty and the results
-- page falls back to "about the nearest 50 places" around the point.
--
-- suggest_localities hands back a radius_miles with each suggestion: the radius of a circle
-- with the place's land area, between 0.5 and 25 miles (Anchorage and Jacksonville are larger
-- than any useful map). The page opens on a square that wide around the place's point. Null
-- when the land area isn't known.
SET search_path = public, extensions;

ALTER TABLE public.localities ADD COLUMN land_sq_m bigint CHECK (land_sq_m >= 0);
COMMENT ON COLUMN public.localities.land_sq_m IS
  'Land area in square metres (Census Gazetteer ALAND); sizes the map when the place is picked';

-- Same matching and order as before (20261109000000_localities.sql); one more column out.
DROP FUNCTION public.suggest_localities(text, double precision, double precision, integer);
CREATE FUNCTION public.suggest_localities(
    query text, near_lat double precision DEFAULT NULL, near_lng double precision DEFAULT NULL,
    max_results integer DEFAULT 8)
  RETURNS TABLE(kind text, label text, detail text, city text, state text,
                lat double precision, lng double precision, radius_miles double precision)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH q AS MATERIALIZED (
    SELECT public.locality_normalize(query) AS t,
           CASE WHEN near_lat IS NULL OR near_lng IS NULL THEN NULL
                ELSE ST_SetSRID(ST_MakePoint(near_lng, near_lat), 4326)::geography END AS near,
           LEAST(GREATEST(coalesce(max_results, 8), 1), 20) AS lim
  ),
  zip_hits AS (
    SELECT l.id, CASE WHEN l.code = q.t THEN 1 ELSE 2 END AS tier, 1::real AS sim
    FROM localities l CROSS JOIN q
    WHERE q.t ~ '^[0-9]{2,5}$' AND l.kind = 'zip' AND l.code LIKE q.t || '%'
  ),
  name_hits AS (
    SELECT n.locality_id AS id,
           min(CASE WHEN n.name_norm = q.t THEN 1 WHEN n.name_norm LIKE q.t || '%' THEN 2 ELSE 3 END) AS tier,
           max(similarity(n.name_norm, q.t)) FILTER (WHERE NOT n.with_state) AS sim
    FROM locality_names n CROSS JOIN q
    WHERE length(q.t) >= 2 AND q.t !~ '^[0-9 ]+$'
      AND (n.name_norm LIKE q.t || '%'
           OR (length(q.t) >= 4 AND NOT n.with_state
               AND n.name_norm % q.t AND similarity(n.name_norm, q.t) >= 0.36))
    GROUP BY n.locality_id
  ),
  hits AS (
    SELECT h.*, bool_or(h.tier = 1) OVER () AS has_exact
    FROM (SELECT * FROM zip_hits UNION ALL SELECT * FROM name_hits) h
  )
  SELECT l.kind, l.label, l.detail, l.city, l.state,
         ST_Y(l.location::geometry) AS lat, ST_X(l.location::geometry) AS lng,
         CASE WHEN l.land_sq_m > 0
              THEN round(LEAST(25, GREATEST(0.5, sqrt(l.land_sq_m / pi()) / 1609.34))::numeric, 2)::double precision
         END AS radius_miles
  FROM hits h
  JOIN localities l ON l.id = h.id
  CROSS JOIN q
  WHERE h.tier < 3 OR NOT h.has_exact
  ORDER BY h.tier,
           CASE WHEN h.tier = 3 THEN h.sim END DESC NULLS LAST,
           CASE WHEN l.kind = 'zip' THEN l.code END,
           CASE WHEN q.near IS NOT NULL AND ST_DWithin(l.location, q.near, 80000) THEN 0 ELSE 1 END,
           CASE WHEN q.near IS NOT NULL AND ST_DWithin(l.location, q.near, 80000)
                THEN ST_Distance(l.location, q.near) END,
           l.population DESC NULLS LAST,
           l.label
  LIMIT (SELECT lim FROM q);
$$;
REVOKE ALL ON FUNCTION public.suggest_localities(text, double precision, double precision, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suggest_localities(text, double precision, double precision, integer)
  TO anon, authenticated, service_role;
