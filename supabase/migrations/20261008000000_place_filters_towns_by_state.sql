-- The Town dropdown should narrow as soon as a state is picked, without a round
-- trip. admin_place_filters now also returns every town with its state, so the
-- page can filter the list in the browser. The existing keys are unchanged.
SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.admin_place_filters(p_state text DEFAULT NULL)
  RETURNS jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'states', (SELECT COALESCE(jsonb_agg(jsonb_build_object('value', s, 'count', n) ORDER BY s), '[]'::jsonb)
               FROM (SELECT state AS s, count(*) AS n FROM entities
                     WHERE status <> 'merged' AND NULLIF(state, '') IS NOT NULL GROUP BY 1) x),
    'cities', (SELECT COALESCE(jsonb_agg(jsonb_build_object('value', c, 'count', n) ORDER BY c), '[]'::jsonb)
               FROM (SELECT city AS c, count(*) AS n FROM entities
                     WHERE status <> 'merged' AND NULLIF(city, '') IS NOT NULL
                       AND (p_state IS NULL OR state = p_state) GROUP BY 1) y),
    'towns',  (SELECT COALESCE(jsonb_agg(jsonb_build_object('state', s, 'value', c, 'count', n) ORDER BY c, s), '[]'::jsonb)
               FROM (SELECT state AS s, city AS c, count(*) AS n FROM entities
                     WHERE status <> 'merged' AND NULLIF(city, '') IS NOT NULL GROUP BY 1, 2) z));
$$;
