-- Nationwide loads go state by state (agreed 2026-11-02). Records whose state is missing
-- or is not a US state code (about 0.1% of Overture) are loaded in one extra run with the
-- scope 'state:none', so "missing from 2 loads of the same area" covers them too.
-- The loaders store the two-letter code whenever they recognise the state.
SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.record_in_scope(p_scope text, p_location geography, p_state text)
  RETURNS boolean
  LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE b float8[];
BEGIN
  IF p_scope = 'all' THEN RETURN true; END IF;
  IF p_scope = 'state:none' THEN
    RETURN upper(trim(coalesce(p_state, ''))) <> ALL (ARRAY[
      'AL','AK','AZ','AR','CA','CO','CT','DE','DC','FL','GA','HI','ID','IL','IN','IA','KS','KY','LA','ME','MD',
      'MA','MI','MN','MS','MO','MT','NE','NV','NH','NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD',
      'TN','TX','UT','VT','VA','WA','WV','WI','WY','PR']);
  END IF;
  IF p_scope LIKE 'state:%' THEN RETURN upper(p_state) = upper(substr(p_scope, 7)); END IF;
  IF p_scope LIKE 'bbox:%' THEN
    b := string_to_array(substr(p_scope, 6), ',')::float8[];
    RETURN p_location IS NOT NULL
       AND ST_X(p_location::geometry) BETWEEN b[1] AND b[3] AND ST_Y(p_location::geometry) BETWEEN b[2] AND b[4];
  END IF;
  RAISE EXCEPTION 'unknown run scope %', p_scope;
END $$;
