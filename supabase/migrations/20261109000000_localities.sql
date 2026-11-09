-- Suggestions as you type in the location box (agreed 2026-11-09).
--
-- A list of every US city, town, village and census-designated place, and every ZIP code
-- area, from the Census Bureau's Gazetteer files (public domain, US government work), with
-- 2020 census populations. Loaded and refreshed only by scripts/localities/load_census.py
-- (the "Load place-name list" workflow).
--
-- What people type is matched against this list inside our own database, so keystrokes never
-- go to an outside service. Pressing Enter without picking a suggestion still uses the lookup
-- the location box used before (street addresses, anything not on the list).
SET search_path = public, extensions;

-- Lower case, common accents removed, apostrophes dropped, other punctuation turned into
-- spaces, single spaces. IMMUTABLE so it can back a generated column: names are normalised
-- once when loaded, and typed text the same way when matched.
--   'St. Louis' -> 'st louis', 'Coeur d''Alene' -> 'coeur dalene', 'Cañon City' -> 'canon city'
CREATE FUNCTION public.locality_normalize(t text) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT btrim(regexp_replace(
           translate(replace(replace(lower(coalesce(t, '')), '''', ''), '’', ''),
                     'áàâäãåāéèêëēíìîïīóòôöõøōúùûüūñçýÿ',
                     'aaaaaaaeeeeeiiiiiooooooouuuuuncyy'),
           '[^a-z0-9]+', ' ', 'g'))
$$;

CREATE TABLE public.localities (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('place', 'zip')),
  code text NOT NULL,          -- Census GEOID: 7 digits for a place; the 5-digit ZIP for a ZIP area
  name text NOT NULL,          -- 'New York', '22201'
  state text,                  -- two-letter code; for a ZIP area, the state of its main place
  label text NOT NULL,         -- the dropdown's main line: 'New York, NY', '22201'
  detail text,                 -- a ZIP area's second line: its main place, 'Arlington, VA'
  city text,                   -- city handed back when picked (a ZIP area: its main place)
  population integer,          -- 2020 census count (places); orders far-away suggestions
  location extensions.geography(Point, 4326) NOT NULL,  -- the Census internal point
  source text NOT NULL,        -- e.g. 'census_gazetteer_2024'
  loaded_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (kind, code)
);
CREATE INDEX localities_location ON public.localities USING gist (location);
CREATE INDEX localities_zip_code ON public.localities (code text_pattern_ops) WHERE kind = 'zip';

-- Every way a place can be typed: its own name, nicknames ('NYC', 'Philly'), and
-- Saint/St, Fort/Ft, Mount/Mt variants, each also followed by the state's code and the
-- state's name ('albany', 'albany ny', 'albany new york'; with_state marks the last two kinds).
CREATE TABLE public.locality_names (
  locality_id bigint NOT NULL REFERENCES public.localities(id) ON DELETE CASCADE,
  name text NOT NULL,
  with_state boolean NOT NULL DEFAULT false,
  name_norm text GENERATED ALWAYS AS (public.locality_normalize(name)) STORED,
  PRIMARY KEY (locality_id, name)
);
-- Trigram index: serves both "starts with" (LIKE 'abc%') and close spellings (%).
CREATE INDEX locality_names_trgm ON public.locality_names USING gin (name_norm gin_trgm_ops);

-- Reference data, read only through suggest_localities.
ALTER TABLE public.localities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locality_names ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.localities, public.locality_names FROM anon, authenticated;
GRANT ALL ON public.localities, public.locality_names TO service_role;

-- Suggestions for what has been typed so far.
--   * Digits only: ZIP code areas whose code starts with them.
--   * Otherwise places, in three tiers: the whole name matches, the name starts with what was
--     typed, or (4+ characters) a close spelling ('albny' -> Albany, 'pittsburg' -> Pittsburgh).
--     Close spellings are compared with a place's own names only, not "name + state" (otherwise
--     'new york ny' looks close to 'albany new york'), and need a trigram similarity of 0.36:
--     measured 2026-11-09, that keeps typos like 'new yrok' (0.38) and 'albny' (0.44) and drops
--     'saint paul' -> Saint Louis (0.35) and 'arlington' -> Washington (0.31).
--   * Close spellings are only added when nothing's whole name matches: "new york, ny" lists
--     New York, NY alone, not West New York, NJ (seen on the real Census list, 2026-11-09).
--   * ZIP codes come in number order.
--   * Within a tier (close spellings: closest spelling first), places within 80 km of near_lat/
--     near_lng (where the person's map is) come first, nearest first; then bigger places.
--     So 'albany' typed in DC lists Albany, NY before Albany, GA, and 'arlington' typed in DC
--     lists Arlington, VA first.
-- This orders places to guess what someone meant; it is not a ranking of restaurants.
CREATE FUNCTION public.suggest_localities(
    query text, near_lat double precision DEFAULT NULL, near_lng double precision DEFAULT NULL,
    max_results integer DEFAULT 8)
  RETURNS TABLE(kind text, label text, detail text, city text, state text,
                lat double precision, lng double precision)
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
         ST_Y(l.location::geometry) AS lat, ST_X(l.location::geometry) AS lng
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
