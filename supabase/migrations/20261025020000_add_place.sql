-- Manual tools, part 3: add a place no source has.
--
-- admin_similar_places(lat, lng, name, phone): places that might already be this one,
--   shown before saving: within 150 m with a similar name, or anywhere within 2 km with
--   the same phone.
-- admin_add_place(values, by, note): creates the place. Every value is marked as our own
--   research and edited by hand, so a source can later propose a change but never
--   overwrite it. A "new_candidate" ledger entry records who added it and why.
SET search_path = public, extensions;

CREATE FUNCTION public.admin_similar_places(p_lat double precision, p_lng double precision, p_name text, p_phone text DEFAULT NULL)
  RETURNS TABLE(id uuid, name text, address text, city text, state text, phone text, distance_m integer, reason text)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  WITH me AS (SELECT ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography AS loc)
  SELECT e.id, e.name, e.address, e.city, e.state, e.phone, round(ST_Distance(e.location, me.loc))::integer,
         CASE WHEN match_phone(p_phone) IS NOT NULL AND match_phone(e.phone) = match_phone(p_phone) THEN 'same phone'
              ELSE 'similar name nearby' END
  FROM entities e, me
  WHERE e.status NOT IN ('merged', 'removed')
    AND ST_DWithin(e.location, me.loc, 2000)
    AND ((ST_DWithin(e.location, me.loc, 150)
          AND (similarity(match_name(e.name), match_name(p_name)) >= 0.4
               OR strpos(match_name(e.name), match_name(p_name)) > 0
               OR strpos(match_name(p_name), match_name(e.name)) > 0))
         OR (match_phone(p_phone) IS NOT NULL AND match_phone(e.phone) = match_phone(p_phone)))
  ORDER BY ST_Distance(e.location, me.loc)
  LIMIT 10;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_similar_places(double precision, double precision, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_similar_places(double precision, double precision, text, text) TO service_role;

CREATE FUNCTION public.admin_add_place(p_values jsonb, p_decided_by text, p_note text DEFAULT NULL)
  RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v_id uuid := gen_random_uuid(); v_src smallint; v_lic text; v_main uuid;
  v_name text := NULLIF(trim(p_values->>'name'), '');
  v_lat double precision; v_lng double precision;
  v_status text := COALESCE(NULLIF(trim(p_values->>'status'), ''), 'active');
  v_vals jsonb;
BEGIN
  IF v_name IS NULL THEN RAISE EXCEPTION 'a place needs a name'; END IF;
  BEGIN
    v_lat := (p_values->>'lat')::double precision;
    v_lng := (p_values->>'lng')::double precision;
  EXCEPTION WHEN others THEN RAISE EXCEPTION 'the map pin is not a valid position';
  END;
  IF v_lat IS NULL OR v_lng IS NULL THEN RAISE EXCEPTION 'place the pin on the map'; END IF;
  -- The United States, including Alaska, Hawaii and Puerto Rico.
  IF v_lat NOT BETWEEN 17 AND 72 OR v_lng NOT BETWEEN -180 AND -64 THEN
    RAISE EXCEPTION 'the pin is outside the United States';
  END IF;
  IF v_status NOT IN ('active', 'temporarily_closed', 'permanently_closed') THEN
    RAISE EXCEPTION 'status % is not allowed for a new place', v_status;
  END IF;
  SELECT id INTO v_main FROM categories WHERE path::text = p_values->>'main_category' AND nlevel(path) = 1;
  IF v_main IS NULL THEN RAISE EXCEPTION 'choose a main category'; END IF;
  SELECT id, license INTO v_src, v_lic FROM sources WHERE code = 'manual_research';
  IF v_src IS NULL THEN RAISE EXCEPTION 'source manual_research is missing'; END IF;

  INSERT INTO entities (id, name, address, city, state, postal_code, phone, website, location, status,
                        needs_review, main_category_id)
  VALUES (v_id, v_name, blank_to_null(trim(p_values->>'address')), blank_to_null(trim(p_values->>'city')),
          upper(blank_to_null(trim(p_values->>'state'))), blank_to_null(trim(p_values->>'postal_code')),
          blank_to_null(trim(p_values->>'phone')), blank_to_null(trim(p_values->>'website')),
          ST_SetSRID(ST_MakePoint(v_lng, v_lat), 4326)::geography, v_status, false, v_main);

  INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
  SELECT v_id, f, v_src, NULL, v_lic, 'manual', now()
  FROM entities e, LATERAL (VALUES
    ('name', true), ('location', true), ('status', true), ('categories', true),
    ('address', COALESCE(e.address, e.city, e.state, e.postal_code) IS NOT NULL),
    ('phone', e.phone IS NOT NULL), ('website', e.website IS NOT NULL)) AS x(f, present)
  WHERE e.id = v_id AND x.present;

  SELECT jsonb_strip_nulls(jsonb_build_object('name', name, 'address', address, 'city', city, 'state', state,
           'postal_code', postal_code, 'phone', phone, 'website', website, 'status', status,
           'main_category', p_values->>'main_category', 'lat', v_lat, 'lng', v_lng))
  INTO v_vals FROM entities WHERE id = v_id;
  INSERT INTO change_events (event_type, entity_id, source_id, new_value, evidence, status, decided_by, decided_at, applied_at)
  VALUES ('new_candidate', v_id, v_src, v_vals, jsonb_build_object('note', p_note, 'added_by_hand', true),
          'approved', p_decided_by, now(), now());
  RETURN v_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_add_place(jsonb, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_add_place(jsonb, text, text) TO service_role;
