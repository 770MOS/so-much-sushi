-- Batch upsert for ingest scripts. A plain REST upsert would overwrite first_seen_run and
-- could not build the geography value, so ingest goes through this function instead.
-- An existing record keeps its first_seen_run and its entity link; only the source's own
-- values and last_seen_run are refreshed.
CREATE FUNCTION public.ingest_source_records(p_run_id bigint, p_records jsonb) RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_source smallint; v_count integer;
BEGIN
  SELECT source_id INTO v_source FROM source_runs WHERE id = p_run_id AND status = 'running';
  IF v_source IS NULL THEN RAISE EXCEPTION 'run % does not exist or is not running', p_run_id; END IF;

  INSERT INTO source_records (source_id, source_record_id, upstream_dataset, license, name, address, city, state,
                              postal_code, phone, website, location, source_category, category_id,
                              source_confidence, payload, first_seen_run, last_seen_run)
  SELECT v_source, r->>'source_record_id', r->>'upstream_dataset', r->>'license', r->>'name', r->>'address',
         r->>'city', r->>'state', r->>'postal_code', r->>'phone', r->>'website',
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
    last_seen_run = EXCLUDED.last_seen_run;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END $$;
REVOKE EXECUTE ON FUNCTION public.ingest_source_records(bigint, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ingest_source_records(bigint, jsonb) TO service_role;
