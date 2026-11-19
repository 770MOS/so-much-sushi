-- Big cities open on their downtown, not 10 miles of it (2026-11-19, from the tester site).
--
-- 20261119000000_big_cities.sql moved a large town's opening point to its busiest spot, but the
-- map still opened on the town's own size, capped at 5 miles out: 10 miles across, 37,000 places
-- in New York. A town with a busiest spot (localities.focus) now hands back a 1-mile radius as
-- its size, so the map opens about 2 miles across around that spot (New York: Midtown, about
-- 7,400 places; Los Angeles: downtown, about 1,700). start_area still widens it where a mile
-- holds fewer than 10 places. Towns without a busiest spot keep their own size, as before.
SET search_path = public, extensions;

-- ---------------------------------------------------------------- suggest_localities
-- As in 20261119000000_big_cities.sql, with a 1-mile size for a town opened on its busiest spot.
CREATE OR REPLACE FUNCTION public.suggest_localities(
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
         ST_Y(coalesce(l.focus, l.location)::geometry) AS lat,
         ST_X(coalesce(l.focus, l.location)::geometry) AS lng,
         CASE WHEN l.focus IS NOT NULL THEN 1::double precision
              WHEN l.land_sq_m > 0
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
