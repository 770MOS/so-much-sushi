-- Blank text ("" or spaces) is treated as no value. Some records arrived with an empty
-- state, phone or website instead of none, so the place looked like it had a value: the
-- field was never filled from another source, and an empty state was proposed for review
-- as a change ("" to "DC").
--
-- 1. blank_to_null(): "" and spaces become NULL.
-- 2. Records are stored without blanks from now on.
-- 3. reconcile_field treats a blank as empty, so it is filled rather than proposed.
-- 4. Existing blanks in records and places are cleared, and pending proposals whose
--    current value was blank are closed (the fill is re-run separately).
SET search_path = public, extensions;

CREATE FUNCTION public.blank_to_null(p text)
  RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path TO '' AS $$
  SELECT CASE WHEN trim(p) = '' THEN NULL ELSE p END;
$$;
REVOKE EXECUTE ON FUNCTION public.blank_to_null(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.blank_to_null(text) TO service_role;

CREATE OR REPLACE FUNCTION public.ingest_source_records(p_run_id bigint, p_records jsonb) RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_source smallint; v_count integer;
BEGIN
  SELECT source_id INTO v_source FROM source_runs WHERE id = p_run_id AND status = 'running';
  IF v_source IS NULL THEN RAISE EXCEPTION 'run % does not exist or is not running', p_run_id; END IF;

  INSERT INTO source_records (source_id, source_record_id, upstream_dataset, license, name, address, city, state,
                              postal_code, phone, website, location, source_category, category_id,
                              source_confidence, payload, first_seen_run, last_seen_run)
  SELECT v_source, r->>'source_record_id', r->>'upstream_dataset', r->>'license', blank_to_null(r->>'name'),
         blank_to_null(r->>'address'), blank_to_null(r->>'city'), blank_to_null(r->>'state'),
         blank_to_null(r->>'postal_code'), blank_to_null(r->>'phone'), blank_to_null(r->>'website'),
         CASE WHEN r->>'lon' IS NOT NULL AND r->>'lat' IS NOT NULL
              THEN ST_SetSRID(ST_MakePoint((r->>'lon')::float8, (r->>'lat')::float8), 4326)::geography END,
         r->>'source_category',
         (SELECT c.id FROM categories c WHERE c.slug = r->>'category_slug'),
         (r->>'source_confidence')::numeric, COALESCE(r->'payload', '{}'::jsonb), p_run_id, p_run_id
  FROM jsonb_array_elements(p_records) r
  ON CONFLICT (source_id, source_record_id) DO UPDATE SET
    upstream_dataset = EXCLUDED.upstream_dataset, license = EXCLUDED.license, name = EXCLUDED.name,
    address = EXCLUDED.address, city = EXCLUDED.city, state = EXCLUDED.state, postal_code = EXCLUDED.postal_code,
    phone = EXCLUDED.phone, website = EXCLUDED.website, location = EXCLUDED.location,
    source_category = EXCLUDED.source_category, category_id = EXCLUDED.category_id,
    source_confidence = EXCLUDED.source_confidence, payload = EXCLUDED.payload,
    last_seen_run = EXCLUDED.last_seen_run,
    prev_values = CASE
      WHEN source_record_values(source_records.name, source_records.address, source_records.city, source_records.state,
             source_records.postal_code, source_records.phone, source_records.website, source_records.location,
             source_records.category_id, source_records.payload)
           IS DISTINCT FROM
           source_record_values(EXCLUDED.name, EXCLUDED.address, EXCLUDED.city, EXCLUDED.state, EXCLUDED.postal_code,
             EXCLUDED.phone, EXCLUDED.website, EXCLUDED.location, EXCLUDED.category_id, EXCLUDED.payload)
      THEN source_record_values(source_records.name, source_records.address, source_records.city, source_records.state,
             source_records.postal_code, source_records.phone, source_records.website, source_records.location,
             source_records.category_id, source_records.payload)
      ELSE source_records.prev_values END,
    changed_run = CASE
      WHEN source_record_values(source_records.name, source_records.address, source_records.city, source_records.state,
             source_records.postal_code, source_records.phone, source_records.website, source_records.location,
             source_records.category_id, source_records.payload)
           IS DISTINCT FROM
           source_record_values(EXCLUDED.name, EXCLUDED.address, EXCLUDED.city, EXCLUDED.state, EXCLUDED.postal_code,
             EXCLUDED.phone, EXCLUDED.website, EXCLUDED.location, EXCLUDED.category_id, EXCLUDED.payload)
      THEN p_run_id ELSE source_records.changed_run END;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_field(p_entity uuid, p_record bigint, p_run bigint, p_field text,
                                       p_old text, p_new text, p_is_new boolean, p_decided_by text)
  RETURNS text
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v_src smallint; v_trust integer; v_prov entity_field_provenance%ROWTYPE; v_cur text; v_pf text;
BEGIN
  -- A blank value is no value.
  p_old := blank_to_null(p_old); p_new := blank_to_null(p_new);
  SELECT source_id INTO v_src FROM source_records WHERE id = p_record;
  v_pf := CASE WHEN p_field IN ('city', 'state', 'postal_code') THEN 'address' ELSE p_field END;
  v_trust := source_trust(v_src, v_pf);
  IF v_trust <= 0 THEN RETURN NULL; END IF;
  SELECT blank_to_null(to_jsonb(e) ->> p_field) INTO v_cur FROM entities e WHERE e.id = p_entity;
  IF v_cur IS NOT DISTINCT FROM p_new THEN RETURN NULL; END IF;
  -- The same value written differently is not a change worth a person's time.
  IF v_cur IS NOT NULL AND p_new IS NOT NULL AND values_equivalent(p_field, v_cur, p_new) THEN RETURN NULL; END IF;
  SELECT * INTO v_prov FROM entity_field_provenance WHERE entity_id = p_entity AND field = v_pf;

  -- The place has nothing here: fill it from this source.
  IF v_cur IS NULL AND p_new IS NOT NULL AND (v_prov.method IS NULL OR v_prov.method = 'survivorship') THEN
    PERFORM apply_source_value(p_entity, p_field, p_new, p_record, p_run, p_decided_by, 'filled an empty field');
    RETURN 'auto';
  END IF;

  -- A hand edit: never changed. A record already on the place proposes when it changes.
  IF v_prov.method = 'manual' THEN
    IF p_is_new THEN RETURN NULL; END IF;
    PERFORM propose_change('attribute_change', p_entity, v_src, p_record, p_run, p_field, to_jsonb(v_cur), to_jsonb(p_new),
      jsonb_build_object('reason', 'the source changed a value that was edited by hand', 'source_before', p_old));
    RETURN 'proposed';
  END IF;

  -- This record supplies the field: follow it, unless it dropped the value or we drifted.
  IF v_prov.source_record_pk = p_record THEN
    IF p_new IS NOT NULL AND v_cur IS NOT DISTINCT FROM p_old THEN
      PERFORM apply_source_value(p_entity, p_field, p_new, p_record, p_run, p_decided_by, 'source updated a value it supplied');
      RETURN 'auto';
    END IF;
    PERFORM propose_change('attribute_change', p_entity, v_src, p_record, p_run, p_field, to_jsonb(v_cur), to_jsonb(p_new),
      jsonb_build_object('reason', CASE WHEN p_new IS NULL THEN 'the source no longer has a value'
                                        ELSE 'the source changed a value that differs from ours' END,
                         'source_before', p_old));
    RETURN 'proposed';
  END IF;

  -- Another source supplies the field: propose only if this one ranks higher. Town and
  -- ZIP are only ever filled from another source, never proposed (neighbourhood names
  -- and ZIP+4 differ between sources without either being wrong).
  IF p_new IS NOT NULL AND p_field NOT IN ('city', 'postal_code')
     AND v_trust > source_trust(v_prov.source_id, v_pf) THEN
    PERFORM propose_change('attribute_change', p_entity, v_src, p_record, p_run, p_field, to_jsonb(v_cur), to_jsonb(p_new),
      jsonb_build_object('reason', 'a source we trust more for this field disagrees',
                         'current_source', (SELECT name FROM sources WHERE id = v_prov.source_id)));
    RETURN 'proposed';
  END IF;
  RETURN NULL;
END $$;

UPDATE public.source_records SET
  address = public.blank_to_null(address), city = public.blank_to_null(city), state = public.blank_to_null(state),
  postal_code = public.blank_to_null(postal_code), phone = public.blank_to_null(phone), website = public.blank_to_null(website)
WHERE trim(address) = '' OR trim(city) = '' OR trim(state) = '' OR trim(postal_code) = ''
   OR trim(phone) = '' OR trim(website) = '';

UPDATE public.entities SET
  address = public.blank_to_null(address), city = public.blank_to_null(city), state = public.blank_to_null(state),
  postal_code = public.blank_to_null(postal_code), phone = public.blank_to_null(phone), website = public.blank_to_null(website)
WHERE trim(address) = '' OR trim(city) = '' OR trim(state) = '' OR trim(postal_code) = ''
   OR trim(phone) = '' OR trim(website) = '';

UPDATE public.change_events
SET status = 'superseded', decided_by = 'migration: current value was blank', decided_at = now()
WHERE status = 'pending' AND event_type = 'attribute_change'
  AND jsonb_typeof(old_value) = 'string' AND trim(old_value #>> '{}') = '';
