-- A second way for a new record to join a place we already have (agreed 2026-10-21):
-- the identical name within 25 m, where neither the phone nor the website conflicts.
-- Learned from the first All the Places load, where 164 of 223 possible duplicates were
-- the same chain location with a phone on one side only ("Subway" and "Subway", 8 m apart).
--
-- Guards, so two real locations of one chain are never joined:
--   * identical name after normalising (not just similar), at least 3 characters;
--   * only one place within 25 m has that name;
--   * the place has no record from this source yet;
--   * only across sources: records within one source still need a phone or website.
SET search_path = public, extensions;

CREATE FUNCTION public.same_name_same_spot(a_name text, a_phone text, a_website text, a_loc geography,
                                           b_name text, b_phone text, b_website text, b_loc geography)
  RETURNS boolean
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT length(match_name(a_name)) >= 3
     AND match_name(a_name) = match_name(b_name)
     AND ST_DWithin(a_loc, b_loc, 25)
     AND NOT COALESCE(match_phone(a_phone) <> match_phone(b_phone), false)
     AND NOT COALESCE(match_host(a_website) <> match_host(b_website), false);
$$;
REVOKE EXECUTE ON FUNCTION public.same_name_same_spot(text, text, text, geography, text, text, text, geography) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.same_name_same_spot(text, text, text, geography, text, text, text, geography) TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_run(p_run_id bigint, p_decided_by text)
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
  --    Rule 1: matching name (similar, or the chain's brand) within 75 m, plus the same phone,
  --            or the same website page with no conflicting phone.
  --    Rule 2: the identical name within 25 m, where neither phone nor website conflicts,
  --            only one place nearby has that name, and the place has no record from this
  --            source yet (two records of one chain at one spot are two locations).
  FOR r IN
    SELECT DISTINCT ON (sr.id) sr.id, e.id AS entity_id, m.rule,
           source_record_values(sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website,
                                sr.location, sr.category_id, sr.payload) AS new
    FROM source_records sr
    JOIN entities e ON ST_DWithin(e.location, sr.location, 75)
    CROSS JOIN LATERAL (SELECT CASE
        WHEN names_match(sr.name, sr.payload->>'brand', e.name)
             AND (match_phone(sr.phone) = match_phone(e.phone)
                  OR (match_url(sr.website) = match_url(e.website)
                      AND NOT COALESCE(match_phone(sr.phone) <> match_phone(e.phone), false)))
          THEN 1
        WHEN same_name_same_spot(sr.name, sr.phone, sr.website, sr.location, e.name, e.phone, e.website, e.location)
             AND NOT EXISTS (SELECT 1 FROM source_records o WHERE o.entity_id = e.id AND o.source_id = v_run.source_id)
             AND NOT EXISTS (SELECT 1 FROM entities e2 WHERE e2.id <> e.id AND e2.status NOT IN ('merged', 'removed')
                               AND e2.created_at < v_started AND ST_DWithin(e2.location, sr.location, 25)
                               AND match_name(e2.name) = match_name(sr.name))
          THEN 2 END AS rule) m
    WHERE sr.source_id = v_run.source_id AND sr.first_seen_run = p_run_id AND sr.match_status = 'unmatched'
      AND sr.location IS NOT NULL AND NOT is_legal_entity_name(sr.name)
      AND e.status NOT IN ('merged', 'removed') AND e.created_at < v_started
      AND m.rule IS NOT NULL
    ORDER BY sr.id, m.rule, ST_Distance(e.location, sr.location)
  LOOP
    -- Rule 2 is checked again here: an earlier record in this same load may have just
    -- taken the place.
    CONTINUE WHEN r.rule = 2 AND EXISTS (SELECT 1 FROM source_records o
                                         WHERE o.entity_id = r.entity_id AND o.source_id = v_run.source_id);
    UPDATE source_records SET entity_id = r.entity_id, match_status = 'auto', matched_at = now(),
                              match_method = CASE r.rule WHEN 1 THEN 'auto: matched existing place'
                                                         ELSE 'auto: same name, same spot' END
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
                            'same_website', match_url(n.website) = match_url(old.website),
                            'website_conflict', match_host(n.website) <> match_host(old.website),
                            'name_a', old.name, 'name_b', n.name, 'reason', 'new in this load, near a very similar existing place')
  FROM source_records sr
  JOIN entities n ON n.id = sr.entity_id AND n.created_at >= v_started
  JOIN entities old ON ST_DWithin(old.location, n.location, 75) AND old.created_at < v_started
                   AND old.status NOT IN ('merged', 'removed')
                   AND names_match(n.name, sr.payload->>'brand', old.name)
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
