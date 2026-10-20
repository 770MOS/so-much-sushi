-- Several sources, field by field.
--
-- 1. Field trust. sources.field_trust ranks each source per field, e.g.
--    {"website": 80, "phone": 70}. 0 or missing = never supplies that field.
--    Hand edits outrank every source.
-- 2. reconcile_run now treats every attached record, from any source, by these rules:
--    - a field a record already supplies follows that record (as before);
--    - an empty field is filled from any trusted source (enrichment, logged);
--    - a source that ranks higher than the one supplying a field, and disagrees,
--      produces a proposal, never an automatic switch;
--    - a field edited by hand is never changed; a trusted source that disagrees proposes;
--    - only the record the place's location came from can move it.
-- 3. Verify-only sources (license_class 'verify_only') never supply values and never
--    create places. Their records are matched to places and can raise closure or
--    missing proposals only.
-- 4. Load areas: a run's scope may be 'bbox:xmin,ymin,xmax,ymax', 'state:VA' or 'all'.
--    A place counts as missing only if no record of it, from any source, was seen in a
--    successful run in the last 45 days.
-- 5. AllThePlaces joins the source register (CC0-1.0, weekly, strong on chain locations).
SET search_path = public, extensions;

-- 1. Trust per source and field.
UPDATE public.sources SET field_trust =
  '{"name": 50, "address": 50, "phone": 50, "website": 50, "location": 50, "status": 50}'::jsonb
WHERE code = 'overture_places';
UPDATE public.sources SET field_trust =
  '{"name": 90, "address": 90, "phone": 90, "website": 100, "status": 90}'::jsonb
WHERE code = 'venue_website';
UPDATE public.sources SET field_trust = '{}'::jsonb WHERE code = 'user_report';
COMMENT ON COLUMN public.sources.field_trust IS
  'Rank per field (name, address, phone, website, location, status); higher wins. 0 or missing: never supplies that field. Hand edits outrank all sources.';

INSERT INTO public.sources (code, name, role, license, license_class, license_url, attribution, cadence,
                            adapter, field_trust, license_checked_on, license_notes)
VALUES ('alltheplaces', 'All the Places', 'base', 'CC0-1.0', 'permissive', 'https://www.alltheplaces.xyz/',
        'All the Places, alltheplaces.xyz', 'weekly', 'scripts/ingest/alltheplaces.py',
        '{"name": 60, "address": 60, "phone": 70, "website": 80, "location": 60, "status": 40}'::jsonb, current_date,
        'Store locations scraped from brands'' own websites; output released under CC0-1.0. Strong on chains, little on independents. Some Overture records also come from it.')
ON CONFLICT (code) DO NOTHING;

CREATE FUNCTION public.source_trust(p_source smallint, p_field text) RETURNS integer
  LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT COALESCE((SELECT (field_trust->>p_field)::integer FROM sources WHERE id = p_source), 0);
$$;
REVOKE EXECUTE ON FUNCTION public.source_trust(smallint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.source_trust(smallint, text) TO service_role;

-- Write a source value onto a place, record where it came from, and log it.
CREATE FUNCTION public.apply_source_value(p_entity uuid, p_field text, p_value text, p_record bigint,
                                          p_run bigint, p_decided_by text, p_reason text)
  RETURNS void
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_old text; v_src smallint; v_lic text; v_prov text;
BEGIN
  IF p_field NOT IN ('name', 'address', 'city', 'state', 'postal_code', 'phone', 'website') THEN
    RAISE EXCEPTION 'apply_source_value cannot set %', p_field;
  END IF;
  SELECT source_id, license INTO v_src, v_lic FROM source_records WHERE id = p_record;
  SELECT to_jsonb(e) ->> p_field INTO v_old FROM entities e WHERE e.id = p_entity;
  EXECUTE format('UPDATE entities SET %I = $1 WHERE id = $2', p_field) USING p_value, p_entity;
  v_prov := CASE WHEN p_field IN ('city', 'state', 'postal_code') THEN 'address' ELSE p_field END;
  -- Filling a town, state or ZIP does not take over the address's provenance from the
  -- record that supplied the street; the change log keeps which source filled it.
  IF p_field IN ('city', 'state', 'postal_code') THEN
    INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
    VALUES (p_entity, v_prov, v_src, p_record, v_lic, 'survivorship', now())
    ON CONFLICT (entity_id, field) DO NOTHING;
  ELSE
    INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
    VALUES (p_entity, v_prov, v_src, p_record, v_lic, 'survivorship', now())
    ON CONFLICT (entity_id, field) DO UPDATE SET source_id = EXCLUDED.source_id,
      source_record_pk = EXCLUDED.source_record_pk, license = EXCLUDED.license, method = 'survivorship', set_at = now();
  END IF;
  INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, run_id, field, old_value, new_value,
                             evidence, status, decided_by, decided_at, applied_at)
  VALUES ('attribute_change', p_entity, v_src, p_record, p_run, p_field, to_jsonb(v_old), to_jsonb(p_value),
          jsonb_build_object('reason', p_reason), 'auto_applied', p_decided_by, now(), now());
END $$;
REVOKE EXECUTE ON FUNCTION public.apply_source_value(uuid, text, text, bigint, bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_source_value(uuid, text, text, bigint, bigint, text, text) TO service_role;

-- Compare one record's value for one field with the place, and update, propose or skip.
-- p_old is the record's previous value (NULL for a record new to this place).
-- Returns 'auto', 'proposed' or NULL.
CREATE FUNCTION public.reconcile_field(p_entity uuid, p_record bigint, p_run bigint, p_field text,
                                       p_old text, p_new text, p_is_new boolean, p_decided_by text)
  RETURNS text
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v_src smallint; v_trust integer; v_prov entity_field_provenance%ROWTYPE; v_cur text; v_pf text;
BEGIN
  SELECT source_id INTO v_src FROM source_records WHERE id = p_record;
  v_pf := CASE WHEN p_field IN ('city', 'state', 'postal_code') THEN 'address' ELSE p_field END;
  v_trust := source_trust(v_src, v_pf);
  IF v_trust <= 0 THEN RETURN NULL; END IF;
  SELECT to_jsonb(e) ->> p_field INTO v_cur FROM entities e WHERE e.id = p_entity;
  IF v_cur IS NOT DISTINCT FROM p_new THEN RETURN NULL; END IF;
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

  -- Another source supplies the field: propose only if this one ranks higher.
  IF p_new IS NOT NULL AND v_trust > source_trust(v_prov.source_id, v_pf) THEN
    PERFORM propose_change('attribute_change', p_entity, v_src, p_record, p_run, p_field, to_jsonb(v_cur), to_jsonb(p_new),
      jsonb_build_object('reason', 'a source we trust more for this field disagrees',
                         'current_source', (SELECT name FROM sources WHERE id = v_prov.source_id)));
    RETURN 'proposed';
  END IF;
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.reconcile_field(uuid, bigint, bigint, text, text, text, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reconcile_field(uuid, bigint, bigint, text, text, text, boolean, text) TO service_role;

-- Is this record inside the run's area?
CREATE FUNCTION public.record_in_scope(p_scope text, p_location geography, p_state text)
  RETURNS boolean
  LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE b float8[];
BEGIN
  IF p_scope = 'all' THEN RETURN true; END IF;
  IF p_scope LIKE 'state:%' THEN RETURN upper(p_state) = upper(substr(p_scope, 7)); END IF;
  IF p_scope LIKE 'bbox:%' THEN
    b := string_to_array(substr(p_scope, 6), ',')::float8[];
    RETURN p_location IS NOT NULL
       AND ST_X(p_location::geometry) BETWEEN b[1] AND b[3] AND ST_Y(p_location::geometry) BETWEEN b[2] AND b[4];
  END IF;
  RAISE EXCEPTION 'unknown run scope %', p_scope;
END $$;
REVOKE EXECUTE ON FUNCTION public.record_in_scope(text, geography, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_in_scope(text, geography, text) TO service_role;

DROP FUNCTION public.reconcile_run(bigint, text);
CREATE FUNCTION public.reconcile_run(p_run_id bigint, p_decided_by text)
  RETURNS jsonb
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v_run source_runs%ROWTYPE; v_code text; v_class text; v_verify boolean;
  v_started timestamptz := now();  -- transaction start: places built in this call carry this created_at
  r record; f text; v_res text; v_dist double precision; v_attached integer := 0; v_build jsonb; v_n integer;
  s_auto integer := 0; s_proposed integer := 0; s_closures integer := 0; s_absent integer := 0; s_dupes integer := 0;
BEGIN
  SELECT * INTO v_run FROM source_runs WHERE id = p_run_id;
  IF v_run.id IS NULL OR v_run.status <> 'succeeded' THEN
    RAISE EXCEPTION 'run % does not exist or has not succeeded', p_run_id;
  END IF;
  PERFORM record_in_scope(v_run.scope, NULL, NULL);  -- rejects an unknown scope early
  SELECT code, license_class INTO v_code, v_class FROM sources WHERE id = v_run.source_id;
  v_verify := v_class = 'verify_only';
  IF v_class = 'share_alike' THEN RAISE EXCEPTION 'source % is share-alike and must not be reconciled', v_code; END IF;

  -- a. Records on a place whose values changed in this load.
  FOR r IN
    SELECT sr.id, sr.entity_id, sr.prev_values AS old, sr.location,
           source_record_values(sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website,
                                sr.location, sr.category_id, sr.payload) AS new,
           e.status AS entity_status,
           EXISTS (SELECT 1 FROM entity_field_provenance lp WHERE lp.entity_id = sr.entity_id
                     AND lp.field = 'location' AND lp.source_record_pk = sr.id) AS is_location_record
    FROM source_records sr JOIN entities e ON e.id = sr.entity_id
    WHERE sr.source_id = v_run.source_id AND sr.changed_run = p_run_id AND sr.prev_values IS NOT NULL
      AND e.status NOT IN ('merged', 'removed')
  LOOP
    IF NOT v_verify THEN
      FOREACH f IN ARRAY ARRAY['name', 'address', 'city', 'state', 'postal_code', 'phone', 'website'] LOOP
        CONTINUE WHEN (r.old->>f) IS NOT DISTINCT FROM (r.new->>f);
        v_res := reconcile_field(r.entity_id, r.id, p_run_id, f, r.old->>f, r.new->>f, false, p_decided_by);
        IF v_res = 'auto' THEN s_auto := s_auto + 1; ELSIF v_res = 'proposed' THEN s_proposed := s_proposed + 1; END IF;
      END LOOP;

      -- Only the record the location came from can move the place.
      IF r.is_location_record AND r.location IS NOT NULL
         AND (r.old->>'lat', r.old->>'lng') IS DISTINCT FROM (r.new->>'lat', r.new->>'lng') THEN
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
    END IF;

    -- Opening status: always proposed, from any source trusted for it (verify-only included).
    IF (r.old->>'operating_status') IS DISTINCT FROM (r.new->>'operating_status')
       AND (v_verify OR source_trust(v_run.source_id, 'status') > 0) THEN
      IF r.new->>'operating_status' IN ('permanently_closed', 'temporarily_closed') AND r.entity_status = 'active' THEN
        PERFORM propose_change('closure_signal', r.entity_id, v_run.source_id, r.id, p_run_id, 'status',
          to_jsonb(r.entity_status), to_jsonb(r.new->>'operating_status'),
          jsonb_build_object('reason', v_code || ' now marks this place ' || replace(r.new->>'operating_status', '_', ' ')));
        s_closures := s_closures + 1;
      ELSIF COALESCE(r.new->>'operating_status', 'open') = 'open' AND r.entity_status IN ('permanently_closed', 'temporarily_closed') THEN
        PERFORM propose_change('status_change', r.entity_id, v_run.source_id, r.id, p_run_id, 'status',
          to_jsonb(r.entity_status), to_jsonb('active'::text),
          jsonb_build_object('reason', v_code || ' now marks this place open'));
        s_closures := s_closures + 1;
      END IF;
    END IF;
  END LOOP;

  -- b. Records missing from the last 2 runs of this source over the same area.
  FOR r IN
    SELECT sr.id, sr.entity_id, sr.last_seen_run, e.status AS entity_status, lr.release AS last_release,
           (SELECT count(*) FROM source_runs x
            WHERE x.source_id = v_run.source_id AND x.scope = v_run.scope AND x.status = 'succeeded'
              AND x.id > sr.last_seen_run AND x.id <= p_run_id) AS missed
    FROM source_records sr
    JOIN entities e ON e.id = sr.entity_id
    LEFT JOIN source_runs lr ON lr.id = sr.last_seen_run
    WHERE sr.source_id = v_run.source_id AND sr.last_seen_run < p_run_id
      AND e.status IN ('active', 'temporarily_closed')
      AND record_in_scope(v_run.scope, sr.location, sr.state)
  LOOP
    CONTINUE WHEN r.missed < 2;
    -- Any record of this place, from any source, seen recently keeps it listed.
    CONTINUE WHEN EXISTS (SELECT 1 FROM source_records o JOIN source_runs orun ON orun.id = o.last_seen_run
                          WHERE o.entity_id = r.entity_id AND o.id <> r.id AND orun.status = 'succeeded'
                            AND COALESCE(orun.finished_at, orun.started_at) >= now() - interval '45 days');
    CONTINUE WHEN EXISTS (SELECT 1 FROM change_events c WHERE c.entity_id = r.entity_id AND c.event_type = 'absent'
                            AND (c.status = 'pending' OR (c.status = 'rejected' AND c.source_record_pk = r.id
                                 AND (c.evidence->>'last_seen_run')::bigint = r.last_seen_run)));
    INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, run_id, field, old_value, new_value, evidence)
    VALUES ('absent', r.entity_id, v_run.source_id, r.id, p_run_id, 'status', to_jsonb(r.entity_status),
            to_jsonb('permanently_closed'::text),
            jsonb_build_object('reason', 'missing from the last ' || r.missed || ' loads of ' || v_code || ' for this area',
                               'missed_runs', r.missed, 'last_seen_release', r.last_release, 'last_seen_run', r.last_seen_run));
    s_absent := s_absent + 1;
  END LOOP;

  -- c. New records: attach to a place we already have on strong evidence.
  FOR r IN
    SELECT DISTINCT ON (sr.id) sr.id, e.id AS entity_id,
           source_record_values(sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website,
                                sr.location, sr.category_id, sr.payload) AS new
    FROM source_records sr
    JOIN entities e ON ST_DWithin(e.location, sr.location, 75)
    WHERE sr.source_id = v_run.source_id AND sr.first_seen_run = p_run_id AND sr.match_status = 'unmatched'
      AND sr.location IS NOT NULL AND NOT is_legal_entity_name(sr.name)
      AND e.status NOT IN ('merged', 'removed') AND e.created_at < v_started
      AND similarity(match_name(sr.name), match_name(e.name)) >= 0.9
      AND (match_phone(sr.phone) = match_phone(e.phone) OR match_host(sr.website) = match_host(e.website))
      AND NOT COALESCE(match_phone(sr.phone) <> match_phone(e.phone), false)
      AND NOT COALESCE(match_host(sr.website) <> match_host(e.website), false)
    ORDER BY sr.id, ST_Distance(e.location, sr.location)
  LOOP
    UPDATE source_records SET entity_id = r.entity_id, match_status = 'auto', matched_at = now(),
                              match_method = 'auto: matched existing place'
    WHERE id = r.id;
    v_attached := v_attached + 1;
    -- A second source fills gaps and, where it ranks higher and disagrees, proposes.
    IF NOT v_verify THEN
      FOREACH f IN ARRAY ARRAY['name', 'address', 'city', 'state', 'postal_code', 'phone', 'website'] LOOP
        v_res := reconcile_field(r.entity_id, r.id, p_run_id, f, NULL, r.new->>f, true, p_decided_by);
        IF v_res = 'auto' THEN s_auto := s_auto + 1; ELSIF v_res = 'proposed' THEN s_proposed := s_proposed + 1; END IF;
      END LOOP;
    END IF;
  END LOOP;

  -- New places from what is left. Verify-only sources never create places.
  IF NOT v_verify AND EXISTS (SELECT 1 FROM source_records WHERE source_id = v_run.source_id
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
      'source', v_code, 'verify_only', v_verify,
      'new_records', v_n, 'attached_to_existing_places', v_attached, 'build', v_build,
      'unmatched_records', (SELECT count(*) FROM source_records WHERE source_id = v_run.source_id AND match_status = 'unmatched'),
      'possible_duplicates_of_existing', s_dupes, 'values_updated_automatically', s_auto,
      'value_changes_for_review', s_proposed, 'status_changes_for_review', s_closures,
      'missing_for_review', s_absent, 'finished_at', now()))
  WHERE id = p_run_id;
  RETURN (SELECT stats->'reconcile' FROM source_runs WHERE id = p_run_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.reconcile_run(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reconcile_run(bigint, text) TO service_role;
