-- Reconciling a new source load against the places we already have.
--
-- 1. Ingest now remembers what changed: when a re-loaded record differs from the stored
--    one, its previous values are kept in prev_values and changed_run is set.
-- 2. reconcile_run(run) runs after a load succeeds:
--    a. Changed records: a field still holding the source's old value is updated
--       automatically (auto_applied, logged). A field someone edited by hand is never
--       overwritten; the source's new value is proposed for review instead. Removed
--       values, big moves (> 250 m) and closures are always proposed, never applied.
--    b. Missing records: a place whose record has been absent from 2 runs of the same
--       scope in a row is proposed as closed (err toward listing: one miss is ignored).
--    c. New records: attached to an existing place when the name is very similar,
--       within 75 m, and phone or website match with nothing conflicting. Otherwise
--       they become new places (build_entities_from_source), and any very similar
--       existing place nearby is proposed as a possible duplicate.
-- 3. decide_source_changes(events, accept) applies or rejects those proposals.
SET search_path = public, extensions;

ALTER TABLE public.source_records
  ADD COLUMN prev_values jsonb,
  ADD COLUMN changed_run bigint REFERENCES public.source_runs(id);
COMMENT ON COLUMN public.source_records.prev_values IS
  'The tracked values this record had before its last change (see source_record_values). Null until a reload changes it.';
CREATE INDEX source_records_changed_run_idx ON public.source_records (changed_run) WHERE changed_run IS NOT NULL;
CREATE INDEX source_records_first_seen_idx ON public.source_records (source_id, first_seen_run);

-- The values reconciliation compares, in one comparable shape.
CREATE FUNCTION public.source_record_values(p_name text, p_address text, p_city text, p_state text,
    p_postal_code text, p_phone text, p_website text, p_location geography, p_category_id uuid, p_payload jsonb)
  RETURNS jsonb
  LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'name', p_name, 'address', p_address, 'city', p_city, 'state', p_state, 'postal_code', p_postal_code,
    'phone', p_phone, 'website', p_website,
    'lat', round(ST_Y(p_location::geometry)::numeric, 6), 'lng', round(ST_X(p_location::geometry)::numeric, 6),
    'category_id', p_category_id, 'operating_status', p_payload->>'operating_status');
$$;
REVOKE EXECUTE ON FUNCTION public.source_record_values(text, text, text, text, text, text, text, geography, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.source_record_values(text, text, text, text, text, text, text, geography, uuid, jsonb) TO service_role;

-- Same as before, plus prev_values / changed_run when a reload changes a tracked value.
CREATE OR REPLACE FUNCTION public.ingest_source_records(p_run_id bigint, p_records jsonb) RETURNS integer
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

-- Close any older pending proposal for the same place and field, then add the new one.
CREATE FUNCTION public.propose_change(p_type text, p_entity uuid, p_source smallint, p_record bigint, p_run bigint,
                                      p_field text, p_old jsonb, p_new jsonb, p_evidence jsonb)
  RETURNS void
  LANGUAGE sql SET search_path = public, extensions AS $$
  UPDATE change_events SET status = 'superseded', decided_by = 'reconcile', decided_at = now()
  WHERE entity_id = p_entity AND status = 'pending' AND event_type = p_type AND field IS NOT DISTINCT FROM p_field;
  INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, run_id, field, old_value, new_value, evidence)
  VALUES (p_type, p_entity, p_source, p_record, p_run, p_field, p_old, p_new, p_evidence);
$$;
REVOKE EXECUTE ON FUNCTION public.propose_change(text, uuid, smallint, bigint, bigint, text, jsonb, jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.propose_change(text, uuid, smallint, bigint, bigint, text, jsonb, jsonb, jsonb) TO service_role;

CREATE FUNCTION public.reconcile_run(p_run_id bigint, p_decided_by text)
  RETURNS jsonb
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v_run source_runs%ROWTYPE; v_code text; v_started timestamptz := now();  -- transaction start: places built in this call carry this created_at
  r record; f text; v_method text; v_prov text; v_cur text; v_dist double precision;
  v_bbox float8[]; v_attached integer; v_build jsonb; v_n integer;
  s_auto integer := 0; s_proposed integer := 0; s_closures integer := 0; s_absent integer := 0;
  s_dupes integer := 0;
BEGIN
  SELECT * INTO v_run FROM source_runs WHERE id = p_run_id;
  IF v_run.id IS NULL OR v_run.status <> 'succeeded' THEN
    RAISE EXCEPTION 'run % does not exist or has not succeeded', p_run_id;
  END IF;
  SELECT code INTO v_code FROM sources WHERE id = v_run.source_id;

  -- a. Changed records. Only each place's primary record counts: the one its location came
  --    from. Secondary records (merged duplicates) never change a place.
  FOR r IN
    SELECT sr.id, sr.entity_id, sr.license, sr.prev_values AS old,
           source_record_values(sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website,
                                sr.location, sr.category_id, sr.payload) AS new,
           sr.location, e.status AS entity_status
    FROM source_records sr
    JOIN entities e ON e.id = sr.entity_id
    JOIN entity_field_provenance lp ON lp.entity_id = sr.entity_id AND lp.field = 'location' AND lp.source_record_pk = sr.id
    WHERE sr.source_id = v_run.source_id AND sr.changed_run = p_run_id AND sr.prev_values IS NOT NULL
      AND e.status NOT IN ('merged', 'removed')
  LOOP
    FOREACH f IN ARRAY ARRAY['name', 'address', 'city', 'state', 'postal_code', 'phone', 'website'] LOOP
      CONTINUE WHEN (r.old->>f) IS NOT DISTINCT FROM (r.new->>f);
      v_prov := CASE WHEN f IN ('city', 'state', 'postal_code') THEN 'address' ELSE f END;
      SELECT method INTO v_method FROM entity_field_provenance WHERE entity_id = r.entity_id AND field = v_prov;
      SELECT to_jsonb(e) ->> f INTO v_cur FROM entities e WHERE e.id = r.entity_id;
      CONTINUE WHEN v_cur IS NOT DISTINCT FROM (r.new->>f);
      IF (v_method IS NULL OR v_method = 'survivorship') AND (r.new->>f) IS NOT NULL
         AND v_cur IS NOT DISTINCT FROM (r.old->>f) THEN
        EXECUTE format('UPDATE entities SET %I = $1 WHERE id = $2', f) USING r.new->>f, r.entity_id;
        INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
        VALUES (r.entity_id, v_prov, v_run.source_id, r.id, r.license, 'survivorship', now())
        ON CONFLICT (entity_id, field) DO UPDATE SET source_id = EXCLUDED.source_id,
          source_record_pk = EXCLUDED.source_record_pk, license = EXCLUDED.license, method = 'survivorship', set_at = now();
        INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, run_id, field, old_value, new_value,
                                   evidence, status, decided_by, decided_at, applied_at)
        VALUES ('attribute_change', r.entity_id, v_run.source_id, r.id, p_run_id, f, to_jsonb(v_cur), r.new->f,
                jsonb_build_object('reason', 'source updated a value it supplied'), 'auto_applied', p_decided_by, now(), now());
        s_auto := s_auto + 1;
      ELSE
        PERFORM propose_change('attribute_change', r.entity_id, v_run.source_id, r.id, p_run_id, f, to_jsonb(v_cur), r.new->f,
          jsonb_build_object('reason', CASE
              WHEN (r.new->>f) IS NULL THEN 'the source no longer has a value'
              WHEN v_method = 'manual' THEN 'the source changed a value that was edited by hand'
              ELSE 'the source changed a value that differs from ours' END,
            'source_before', r.old->f));
        s_proposed := s_proposed + 1;
      END IF;
    END LOOP;

    -- Location: small moves follow the source; big ones are checked by a person.
    IF (r.old->>'lat', r.old->>'lng') IS DISTINCT FROM (r.new->>'lat', r.new->>'lng') AND r.location IS NOT NULL THEN
      SELECT ST_Distance(e.location, r.location) INTO v_dist FROM entities e WHERE e.id = r.entity_id;
      IF v_dist > 0 AND v_dist <= 250 THEN
        UPDATE entities SET location = r.location WHERE id = r.entity_id;
        INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, run_id, field, old_value, new_value,
                                   evidence, status, decided_by, decided_at, applied_at)
        VALUES ('attribute_change', r.entity_id, v_run.source_id, r.id, p_run_id, 'location',
                jsonb_build_object('lat', r.old->'lat', 'lng', r.old->'lng'),
                jsonb_build_object('lat', r.new->'lat', 'lng', r.new->'lng'),
                jsonb_build_object('reason', 'source moved the point', 'distance_m', round(v_dist)),
                'auto_applied', p_decided_by, now(), now());
        s_auto := s_auto + 1;
      ELSIF v_dist > 250 THEN
        PERFORM propose_change('attribute_change', r.entity_id, v_run.source_id, r.id, p_run_id, 'location',
          jsonb_build_object('lat', r.old->'lat', 'lng', r.old->'lng'),
          jsonb_build_object('lat', r.new->'lat', 'lng', r.new->'lng'),
          jsonb_build_object('reason', 'the source moved this place more than 250 m', 'distance_m', round(v_dist)));
        s_proposed := s_proposed + 1;
      END IF;
    END IF;

    -- Opening status: closures and reopenings are always proposed.
    IF (r.old->>'operating_status') IS DISTINCT FROM (r.new->>'operating_status') THEN
      IF r.new->>'operating_status' IN ('permanently_closed', 'temporarily_closed') AND r.entity_status = 'active' THEN
        PERFORM propose_change('closure_signal', r.entity_id, v_run.source_id, r.id, p_run_id, 'status',
          to_jsonb(r.entity_status), to_jsonb(r.new->>'operating_status'),
          jsonb_build_object('reason', 'the source now marks this place ' || replace(r.new->>'operating_status', '_', ' ')));
        s_closures := s_closures + 1;
      ELSIF COALESCE(r.new->>'operating_status', 'open') = 'open' AND r.entity_status IN ('permanently_closed', 'temporarily_closed') THEN
        PERFORM propose_change('status_change', r.entity_id, v_run.source_id, r.id, p_run_id, 'status',
          to_jsonb(r.entity_status), to_jsonb('active'::text),
          jsonb_build_object('reason', 'the source now marks this place open'));
        s_closures := s_closures + 1;
      END IF;
    END IF;
  END LOOP;

  -- b. Missing records: absent from the last 2 runs that covered the same area.
  IF v_run.scope LIKE 'bbox:%' THEN
    v_bbox := string_to_array(substr(v_run.scope, 6), ',')::float8[];
  END IF;
  FOR r IN
    SELECT sr.id, sr.entity_id, e.status AS entity_status, lr.release AS last_release,
           (SELECT count(*) FROM source_runs x
            WHERE x.source_id = v_run.source_id AND x.scope = v_run.scope AND x.status = 'succeeded'
              AND x.id > sr.last_seen_run AND x.id <= p_run_id) AS missed
    FROM source_records sr
    JOIN entities e ON e.id = sr.entity_id
    JOIN entity_field_provenance lp ON lp.entity_id = sr.entity_id AND lp.field = 'location' AND lp.source_record_pk = sr.id
    LEFT JOIN source_runs lr ON lr.id = sr.last_seen_run
    WHERE sr.source_id = v_run.source_id AND sr.last_seen_run < p_run_id
      AND e.status IN ('active', 'temporarily_closed')
      AND (v_bbox IS NULL OR (ST_X(sr.location::geometry) BETWEEN v_bbox[1] AND v_bbox[3]
                              AND ST_Y(sr.location::geometry) BETWEEN v_bbox[2] AND v_bbox[4]))
  LOOP
    CONTINUE WHEN r.missed < 2;
    -- Still listed by another record seen in this run? Then the place is not missing.
    CONTINUE WHEN EXISTS (SELECT 1 FROM source_records o WHERE o.entity_id = r.entity_id AND o.id <> r.id
                                                           AND o.last_seen_run = p_run_id);
    -- Already proposed, or already kept open by a person since the record was last seen.
    CONTINUE WHEN EXISTS (SELECT 1 FROM change_events c WHERE c.entity_id = r.entity_id AND c.event_type = 'absent'
                            AND (c.status = 'pending' OR (c.status = 'rejected' AND c.source_record_pk = r.id
                                 AND (c.evidence->>'last_seen_run')::bigint = (SELECT last_seen_run FROM source_records WHERE id = r.id))));
    INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, run_id, field, old_value, new_value, evidence)
    VALUES ('absent', r.entity_id, v_run.source_id, r.id, p_run_id, 'status', to_jsonb(r.entity_status),
            to_jsonb('permanently_closed'::text),
            jsonb_build_object('reason', 'missing from the last ' || r.missed || ' loads of this area',
                               'missed_runs', r.missed, 'last_seen_release', r.last_release,
                               'last_seen_run', (SELECT last_seen_run FROM source_records WHERE id = r.id)));
    s_absent := s_absent + 1;
  END LOOP;

  -- c. New records. First, attach any that are clearly a place we already have.
  WITH cand AS (
    SELECT DISTINCT ON (sr.id) sr.id AS record_id, e.id AS entity_id
    FROM source_records sr
    JOIN entities e ON ST_DWithin(e.location, sr.location, 75)
    WHERE sr.source_id = v_run.source_id AND sr.first_seen_run = p_run_id AND sr.match_status = 'unmatched'
      AND sr.location IS NOT NULL AND NOT is_legal_entity_name(sr.name)
      AND e.status NOT IN ('merged', 'removed') AND e.created_at < v_started
      AND similarity(match_name(sr.name), match_name(e.name)) >= 0.9
      AND (match_phone(sr.phone) = match_phone(e.phone) OR match_host(sr.website) = match_host(e.website))
      AND NOT COALESCE(match_phone(sr.phone) <> match_phone(e.phone), false)
      AND NOT COALESCE(match_host(sr.website) <> match_host(e.website), false)
    ORDER BY sr.id, ST_Distance(e.location, sr.location))
  UPDATE source_records sr SET entity_id = cand.entity_id, match_status = 'auto', matched_at = now(),
                               match_method = 'auto: matched existing place'
  FROM cand WHERE sr.id = cand.record_id;
  GET DIAGNOSTICS v_attached = ROW_COUNT;

  -- Then make places from what is left (including any earlier leftovers).
  IF EXISTS (SELECT 1 FROM source_records WHERE source_id = v_run.source_id
               AND (match_status = 'unmatched' OR (match_status = 'needs_review' AND match_method = 'legal entity name'))) THEN
    v_build := build_entities_from_source(v_code, p_decided_by);
  END IF;

  -- New places that look like an existing one become possible-duplicate proposals.
  INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, run_id, old_value, new_value, evidence)
  SELECT DISTINCT ON (n.id) 'merge', old.id, v_run.source_id, sr.id, p_run_id,
         jsonb_build_object('duplicate', n.id), jsonb_build_object('survivor', old.id),
         jsonb_build_object('proposed_by', p_decided_by, 'distance_m', round(ST_Distance(old.location, n.location)),
                            'name_similarity', round(similarity(match_name(n.name), match_name(old.name))::numeric, 2),
                            'same_phone', match_phone(n.phone) = match_phone(old.phone),
                            'phone_conflict', match_phone(n.phone) <> match_phone(old.phone),
                            'same_website', match_host(n.website) = match_host(old.website),
                            'website_conflict', match_host(n.website) <> match_host(old.website),
                            'name_a', old.name, 'name_b', n.name, 'reason', 'new in this load, near a very similar existing place')
  FROM source_records sr
  JOIN entities n ON n.id = sr.entity_id AND n.created_at >= v_started
  JOIN entities old ON ST_DWithin(old.location, n.location, 75) AND old.created_at < v_started
                   AND old.status NOT IN ('merged', 'removed')
                   AND similarity(match_name(n.name), match_name(old.name)) >= 0.9
  WHERE sr.source_id = v_run.source_id AND sr.first_seen_run = p_run_id
    AND NOT EXISTS (SELECT 1 FROM change_events c WHERE c.event_type = 'merge' AND c.status = 'pending'
                      AND c.entity_id = old.id AND c.old_value->>'duplicate' = n.id::text)
  ORDER BY n.id, ST_Distance(old.location, n.location);
  GET DIAGNOSTICS s_dupes = ROW_COUNT;

  v_n := (SELECT count(*) FROM source_records WHERE source_id = v_run.source_id AND first_seen_run = p_run_id);
  UPDATE source_runs SET stats = stats || jsonb_build_object('reconcile', jsonb_build_object(
      'new_records', v_n, 'attached_to_existing_places', v_attached, 'build', v_build,
      'possible_duplicates_of_existing', s_dupes, 'values_updated_automatically', s_auto,
      'value_changes_for_review', s_proposed, 'status_changes_for_review', s_closures,
      'missing_for_review', s_absent, 'finished_at', now()))
  WHERE id = p_run_id;
  RETURN (SELECT stats->'reconcile' FROM source_runs WHERE id = p_run_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.reconcile_run(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reconcile_run(bigint, text) TO service_role;

-- Accept or reject proposals made by reconcile_run. Returns how many were decided.
CREATE FUNCTION public.decide_source_changes(p_events bigint[], p_accept boolean, p_decided_by text)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v change_events%ROWTYPE; v_ent uuid; v_lic text; v_src smallint; v_n integer := 0; v_status text;
BEGIN
  FOR v IN SELECT * FROM change_events c
           WHERE c.id = ANY (p_events) AND c.status = 'pending'
             AND (c.event_type IN ('closure_signal', 'status_change', 'absent')
                  OR (c.event_type = 'attribute_change' AND c.field IS DISTINCT FROM 'categories'))
           ORDER BY c.id FOR UPDATE LOOP
    v_ent := resolve_entity(v.entity_id);
    IF p_accept THEN
      SELECT status INTO v_status FROM entities WHERE id = v_ent;
      IF v_status IN ('merged', 'removed') THEN
        UPDATE change_events SET status = 'superseded', decided_by = p_decided_by, decided_at = now() WHERE id = v.id;
        v_n := v_n + 1;
        CONTINUE;
      END IF;
      SELECT license INTO v_lic FROM source_records WHERE id = v.source_record_pk;
      IF v.event_type = 'attribute_change' AND v.field = 'location' THEN
        UPDATE entities SET location = ST_SetSRID(ST_MakePoint((v.new_value->>'lng')::float8, (v.new_value->>'lat')::float8), 4326)::geography
        WHERE id = v_ent;
      ELSIF v.event_type = 'attribute_change' THEN
        IF v.field NOT IN ('name', 'address', 'city', 'state', 'postal_code', 'phone', 'website') THEN
          RAISE EXCEPTION 'event % changes field %, which cannot be applied here', v.id, v.field;
        END IF;
        IF v.field = 'name' AND (v.new_value #>> '{}') IS NULL THEN RAISE EXCEPTION 'a place needs a name'; END IF;
        EXECUTE format('UPDATE entities SET %I = $1 WHERE id = $2', v.field) USING v.new_value #>> '{}', v_ent;
      ELSE
        UPDATE entities SET status = v.new_value #>> '{}' WHERE id = v_ent;
      END IF;
      -- The value now comes from the source record, or from our own judgement for an absence.
      IF v.event_type = 'absent' OR v_lic IS NULL THEN
        SELECT id, license INTO v_src, v_lic FROM sources WHERE code = 'manual_research';
        INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
        VALUES (v_ent, CASE WHEN v.field IN ('city', 'state', 'postal_code') THEN 'address' ELSE COALESCE(v.field, 'status') END,
                v_src, NULL, v_lic, 'manual', now())
        ON CONFLICT (entity_id, field) DO UPDATE SET source_id = EXCLUDED.source_id, source_record_pk = NULL,
          license = EXCLUDED.license, method = 'manual', set_at = now();
      ELSE
        INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
        VALUES (v_ent, CASE WHEN v.field IN ('city', 'state', 'postal_code') THEN 'address' ELSE COALESCE(v.field, 'status') END,
                v.source_id, v.source_record_pk, v_lic, 'survivorship', now())
        ON CONFLICT (entity_id, field) DO UPDATE SET source_id = EXCLUDED.source_id,
          source_record_pk = EXCLUDED.source_record_pk, license = EXCLUDED.license, method = 'survivorship', set_at = now();
      END IF;
      UPDATE change_events SET status = 'approved', decided_by = p_decided_by, decided_at = now(), applied_at = now()
      WHERE id = v.id;
    ELSE
      UPDATE change_events SET status = 'rejected', decided_by = p_decided_by, decided_at = now() WHERE id = v.id;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION public.decide_source_changes(bigint[], boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.decide_source_changes(bigint[], boolean, text) TO service_role;

-- Review-queue listing for those proposals.
CREATE FUNCTION public.admin_pending_source_changes()
  RETURNS TABLE(event_id bigint, event_type text, entity_id uuid, name text, city text, state text,
                field text, current_value text, proposed_value text, reason text, release text, created_at timestamptz)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT c.id, c.event_type, e.id, e.name, e.city, e.state, c.field,
         CASE WHEN c.field = 'location' THEN round(ST_Y(e.location::geometry)::numeric, 5) || ', ' || round(ST_X(e.location::geometry)::numeric, 5)
              ELSE to_jsonb(e) ->> COALESCE(c.field, 'status') END,
         CASE WHEN c.field = 'location' THEN (c.new_value->>'lat') || ', ' || (c.new_value->>'lng')
              ELSE c.new_value #>> '{}' END,
         c.evidence->>'reason', r.release, c.created_at
  FROM change_events c
  JOIN entities e ON e.id = c.entity_id
  LEFT JOIN source_runs r ON r.id = c.run_id
  WHERE c.status = 'pending'
    AND (c.event_type IN ('closure_signal', 'status_change', 'absent')
         OR (c.event_type = 'attribute_change' AND c.field IS DISTINCT FROM 'categories'))
  ORDER BY c.event_type, e.name, c.id;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_pending_source_changes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pending_source_changes() TO service_role;
