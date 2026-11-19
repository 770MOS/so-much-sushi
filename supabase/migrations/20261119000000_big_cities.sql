-- Big cities open on their busiest area, at most 10 miles across (decided 2026-11-19).
--
-- Found on the tester site: picking a big city opened the whole city around its geographic
-- middle (the Census internal point). New York opened on all five boroughs around Crown
-- Heights, Brooklyn; Los Angeles around Palms, 9 miles from downtown; Phoenix 13 miles each
-- way. A first search there had to read tens of thousands of places and could pass the
-- 8-second limit ("pizza" in Los Angeles did), and the list started far from downtown.
--
-- 1. localities.focus: for places at least 4 miles in radius (by land area), the busiest spot:
--    the middle of the places in the busiest 0.02-degree square (about 1.4 by 1.1 miles) among
--    open places whose address names that town and state, within the town's circle. Counting
--    only the town's own addresses keeps Phoenix on downtown Phoenix, not Scottsdale. At
--    least 20 places, or none is set. Checked 2026-11-19: Midtown Manhattan, downtown Los
--    Angeles, the Loop, downtown Houston, Phoenix, San Diego, San Antonio, Dallas, Austin,
--    Boston and Center City Philadelphia; 270 of 469 such towns get one (about 15 s).
--    refresh_locality_focus() works them out again; the place-name list loader runs it after
--    each load, and it runs once here.
-- 2. suggest_localities hands back the focus as a town's point where there is one, so the
--    page opens there and measures distances from there.
-- 3. start_area takes a town's own size up to 5 miles (10 across). Sparse places can still
--    open wider (up to 25 miles) to reach their nearest few places.
SET search_path = public, extensions;
SET statement_timeout = '10min';

ALTER TABLE public.localities ADD COLUMN focus extensions.geography(Point, 4326);
COMMENT ON COLUMN public.localities.focus IS
  'Busiest spot of a large town (refresh_locality_focus); where the map opens when it is picked';

-- ---------------------------------------------------------------- refresh_locality_focus
CREATE FUNCTION public.refresh_locality_focus()
  RETURNS integer
  LANGUAGE plpgsql VOLATILE SET search_path = public, extensions AS $$
DECLARE
  n integer;
BEGIN
  UPDATE localities SET focus = NULL WHERE focus IS NOT NULL;
  WITH big AS (
    SELECT l.id, l.city, l.state, l.location,
           LEAST(25, sqrt(l.land_sq_m / pi()) / 1609.34) * 1609.34 AS reach_m
    FROM localities l
    WHERE l.kind = 'place' AND l.city IS NOT NULL AND l.state IS NOT NULL
      AND l.land_sq_m >= pi() * (4 * 1609.34) ^ 2
  ),
  cells AS (
    SELECT b.id,
           round(ST_Y(e.location::geometry)::numeric / 0.02) AS cy,
           round(ST_X(e.location::geometry)::numeric / 0.02) AS cx,
           count(*) AS places,
           avg(ST_Y(e.location::geometry)) AS lat,
           avg(ST_X(e.location::geometry)) AS lng
    FROM big b
    JOIN entities e ON ST_DWithin(e.location, b.location, b.reach_m)
    WHERE e.status NOT IN ('permanently_closed', 'merged', 'removed')
      AND lower(e.city) = lower(b.city) AND e.state = b.state
    GROUP BY b.id, cy, cx
  ),
  busiest AS (
    SELECT DISTINCT ON (id) id, places, lat, lng
    FROM cells
    ORDER BY id, places DESC, cy, cx
  )
  UPDATE localities l
  SET focus = ST_SetSRID(ST_MakePoint(b.lng, b.lat), 4326)::geography
  FROM busiest b
  WHERE l.id = b.id AND b.places >= 20;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_locality_focus() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_locality_focus() TO service_role;

SELECT public.refresh_locality_focus();

-- ---------------------------------------------------------------- suggest_localities
-- As in 20261112010000_localities_land_area.sql, with a large town's busiest spot as its point.
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

-- ---------------------------------------------------------------- start_area
-- As in 20261116000000_search_fixes.sql, with a town's own size counted up to 5 miles.
CREATE OR REPLACE FUNCTION public.start_area(
    lat double precision, lng double precision,
    min_radius_miles double precision DEFAULT 0, min_places integer DEFAULT 50)
  RETURNS double precision
  LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  n constant integer := greatest(least(coalesce(min_places, 50), 500), 1);
  miles double precision;
BEGIN
  IF lat IS NULL OR lng IS NULL OR lat NOT BETWEEN -90 AND 90 OR lng NOT BETWEEN -180 AND 180 THEN
    RETURN NULL;
  END IF;
  EXECUTE format(
    'SELECT ST_Distance(e.location, $1) / 1609.34 FROM entities e
      WHERE e.status NOT IN (''permanently_closed'', ''merged'', ''removed'')
      ORDER BY e.location <-> $1
      OFFSET %s LIMIT 1', n - 1)
    INTO miles
    USING ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography;
  RETURN round(LEAST(25, GREATEST(1.0 / 3, LEAST(coalesce(min_radius_miles, 0), 5), coalesce(miles, 0)))::numeric, 2)::double precision;
END;
$$;
