-- Fewer, better proposals when sources disagree, learned from the first All the Places load
-- (2,203 value proposals, almost all formatting; 122 same-phone chain locations not matched).
--
-- 1. values_equivalent(field, a, b): the same value written differently.
--    phone: same 10 digits. website: same domain. ZIP: same first 5 digits. town, state:
--    same ignoring case. address: same after normalising punctuation and common
--    abbreviations, or one is the other plus a suite or unit. name: one contains the other.
--    Equivalent values never produce a proposal.
-- 2. Town and ZIP from another source are only used to fill an empty field.
-- 3. Websites: match_host() now returns the site's domain (locations.pizzahut.com and
--    pizzahut.com are the same site) and is used to detect a conflict. Evidence that two
--    records are the same place needs the same page: match_url() (domain + path).
-- 4. Matching rule, as originally agreed: very similar name plus the same phone, or the
--    same website page with no conflicting phone. A different website domain no longer
--    blocks a phone match.
-- 5. Pending proposals that are only formatting are closed.
SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.match_host(p text)
  RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path TO '' AS $$
  SELECT CASE WHEN h IS NULL OR h = ''
                OR h ~ '(^|\.)(facebook|instagram|yelp|google|linktr|doordash|ubereats|grubhub|toasttab|squareup|square|opentable|resy|tripadvisor|twitter|x|tiktok|wixsite|business)\.(com|ee|site)$'
              THEN NULL
              ELSE substring(h from '([^.]+\.[^.]+)$') END
  FROM (SELECT regexp_replace(lower(coalesce(p, '')), '^https?://(www\.)?([^/?#:]+).*$', '\2') AS h) t;
$$;

CREATE FUNCTION public.match_url(p text)
  RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path TO '' AS $$
  SELECT CASE WHEN public.match_host(p) IS NULL THEN NULL
              ELSE rtrim(regexp_replace(lower(p), '^https?://(www\.)?([^?#]*).*$', '\2'), '/') END;
$$;
REVOKE EXECUTE ON FUNCTION public.match_url(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_url(text) TO service_role;

-- Street-type words, directions and unit words are dropped in both spellings, so
-- "725 King Street" and "725 King St" both become "725 king".
CREATE FUNCTION public.norm_address(p text)
  RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path TO '' AS $$
  SELECT regexp_replace(trim(regexp_replace(
           ' ' || regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]+', ' ', 'g') || ' ',
           ' (street|st|road|rd|drive|dr|avenue|ave|av|boulevard|blvd|lane|ln|court|ct|place|pl|highway|hwy|parkway|pkwy|terrace|ter|circle|cir|square|sq|north|n|south|s|east|e|west|w|northwest|nw|northeast|ne|southwest|sw|southeast|se|suite|ste|unit|apartment|apt|number|no)(?= )',
           ' ', 'g')), ' +', ' ', 'g');
$$;
REVOKE EXECUTE ON FUNCTION public.norm_address(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.norm_address(text) TO service_role;

CREATE FUNCTION public.values_equivalent(p_field text, a text, b text)
  RETURNS boolean
  LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
  SELECT CASE
    WHEN a IS NULL OR b IS NULL THEN a IS NOT DISTINCT FROM b
    WHEN p_field = 'phone' THEN match_phone(a) IS NOT NULL AND match_phone(a) = match_phone(b)
    WHEN p_field = 'website' THEN match_host(a) IS NOT NULL AND match_host(a) = match_host(b)
    WHEN p_field = 'postal_code' THEN left(regexp_replace(a, '\D', '', 'g'), 5) = left(regexp_replace(b, '\D', '', 'g'), 5)
    WHEN p_field IN ('city', 'state') THEN upper(trim(a)) = upper(trim(b))
    WHEN p_field = 'address' THEN norm_address(a) = norm_address(b)
         OR (length(norm_address(a)) >= 5 AND length(norm_address(b)) >= 5
             AND (norm_address(a) LIKE norm_address(b) || ' %' OR norm_address(b) LIKE norm_address(a) || ' %'))
    WHEN p_field = 'name' THEN match_name(a) = match_name(b)
         OR (least(length(match_name(a)), length(match_name(b))) >= 4
             AND (strpos(match_name(a), match_name(b)) > 0 OR strpos(match_name(b), match_name(a)) > 0))
    ELSE a = b END;
$$;
REVOKE EXECUTE ON FUNCTION public.values_equivalent(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.values_equivalent(text, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.match_candidate_pairs(p_source_code text, p_max_m integer DEFAULT 75, p_min_sim real DEFAULT 0.6)
  RETURNS TABLE(record_a bigint, record_b bigint, distance_m integer, name_sim real,
                same_phone boolean, phone_conflict boolean, same_host boolean, host_conflict boolean)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT a.id, b.id, round(ST_Distance(a.location, b.location))::integer,
         similarity(match_name(a.name), match_name(b.name)),
         match_phone(a.phone) = match_phone(b.phone), match_phone(a.phone) <> match_phone(b.phone),
         match_url(a.website) = match_url(b.website), match_host(a.website) <> match_host(b.website)
  FROM sources s
  JOIN source_records a ON a.source_id = s.id
  JOIN source_records b ON b.source_id = a.source_id AND a.id < b.id
                       AND ST_DWithin(a.location, b.location, p_max_m)
  WHERE s.code = p_source_code
    AND a.match_status = 'unmatched' AND b.match_status = 'unmatched'
    AND NOT is_legal_entity_name(a.name) AND NOT is_legal_entity_name(b.name)
    AND similarity(match_name(a.name), match_name(b.name)) >= p_min_sim;
$$;

CREATE OR REPLACE FUNCTION public.build_entities_from_source(p_source_code text, p_decided_by text,
                                                  p_auto_sim real DEFAULT 0.9, p_max_m integer DEFAULT 75)
  RETURNS jsonb
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v_source smallint; v_changed integer; v_held integer; v_entities integer; v_merged integer; v_review integer;
BEGIN
  SELECT id INTO v_source FROM sources WHERE code = p_source_code AND is_active;
  IF v_source IS NULL THEN RAISE EXCEPTION 'source % is missing or inactive', p_source_code; END IF;

  -- Legal-entity names ("Aloha Dc Llc") are listed as their own place and flagged for
  -- review. They are never paired with other records, so they cannot cause a merge.
  -- Records an earlier version held back are picked up here too.

  CREATE TEMP TABLE _pairs ON COMMIT DROP AS
    SELECT *, (name_sim >= p_auto_sim
               AND (coalesce(same_phone, false)
                    OR (coalesce(same_host, false) AND NOT coalesce(phone_conflict, false)))) AS auto
    FROM match_candidate_pairs(p_source_code, p_max_m, LEAST(p_auto_sim, 0.6::real));

  -- Group records joined by auto pairs (connected components, smallest id as the label).
  CREATE TEMP TABLE _grp ON COMMIT DROP AS
    SELECT sr.id AS record_id, sr.id AS grp FROM source_records sr
    WHERE sr.source_id = v_source AND sr.location IS NOT NULL
      AND (sr.match_status = 'unmatched'
           OR (sr.match_status = 'needs_review' AND sr.match_method = 'legal entity name'));
  CREATE INDEX ON _grp (record_id);
  LOOP
    UPDATE _grp g SET grp = m.new_grp
    FROM (SELECT x.record_id, min(y.grp) AS new_grp
          FROM (SELECT record_a AS record_id, record_b AS other FROM _pairs WHERE auto
                UNION ALL SELECT record_b, record_a FROM _pairs WHERE auto) x
          JOIN _grp y ON y.record_id = x.other GROUP BY x.record_id) m
    WHERE g.record_id = m.record_id AND m.new_grp < g.grp;
    GET DIAGNOSTICS v_changed = ROW_COUNT;
    EXIT WHEN v_changed = 0;
  END LOOP;

  -- One entity per group, taking values from its most trustworthy record
  -- (not closed first, then highest source confidence).
  CREATE TEMP TABLE _new ON COMMIT DROP AS
    SELECT DISTINCT ON (g.grp) g.grp, gen_random_uuid() AS entity_id, sr.id AS best_record, sr.license,
           sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website, sr.location,
           sr.category_id, c.path AS cat_path,
           CASE sr.payload->>'operating_status' WHEN 'permanently_closed' THEN 'permanently_closed'
                WHEN 'temporarily_closed' THEN 'temporarily_closed' ELSE 'active' END AS status,
           (NOT coalesce((sr.payload->>'category_mapped')::boolean, false)
            OR is_legal_entity_name(sr.name)) AS needs_review,
           is_legal_entity_name(sr.name) AS legal_name
    FROM _grp g JOIN source_records sr ON sr.id = g.record_id
    LEFT JOIN categories c ON c.id = sr.category_id
    WHERE sr.category_id IS NOT NULL
    ORDER BY g.grp, (sr.payload->>'operating_status' = 'permanently_closed'), sr.source_confidence DESC NULLS LAST, sr.id;

  INSERT INTO entities (id, name, address, city, state, postal_code, phone, website, location, status,
                        needs_review, main_category_id)
  SELECT n.entity_id, n.name, n.address, n.city, n.state, n.postal_code, n.phone, n.website, n.location, n.status,
         n.needs_review, root.id
  FROM _new n JOIN categories root ON root.path = subpath(n.cat_path, 0, 1);
  GET DIAGNOSTICS v_entities = ROW_COUNT;

  INSERT INTO entity_categories (entity_id, category_id)
  SELECT n.entity_id, n.category_id FROM _new n WHERE nlevel(n.cat_path) > 1;

  INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method)
  SELECT n.entity_id, f.field, v_source, n.best_record, n.license, 'survivorship'
  FROM _new n CROSS JOIN LATERAL (VALUES
    ('name', true), ('location', true), ('categories', true), ('status', true),
    ('address', n.address IS NOT NULL), ('phone', n.phone IS NOT NULL), ('website', n.website IS NOT NULL)
  ) AS f(field, present) WHERE f.present;

  UPDATE source_records sr SET entity_id = n.entity_id, match_status = 'auto', matched_at = now(),
         match_method = CASE WHEN n.legal_name THEN 'new entity: legal name'
                             WHEN sr.id = n.best_record THEN 'new entity' ELSE 'auto: name + contact' END
  FROM _grp g JOIN _new n ON n.grp = g.grp WHERE sr.id = g.record_id;
  SELECT count(*) INTO v_merged FROM _grp g JOIN _new n ON n.grp = g.grp WHERE g.record_id <> n.best_record;
  SELECT count(*) INTO v_held FROM _new WHERE legal_name;

  -- Similar names without enough evidence to merge: propose, do not act.
  INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, old_value, new_value, evidence)
  SELECT 'merge', ea.entity_id, v_source, p.record_b,
         jsonb_build_object('duplicate', eb.entity_id), jsonb_build_object('survivor', ea.entity_id),
         jsonb_build_object('proposed_by', p_decided_by, 'distance_m', p.distance_m, 'name_similarity', round(p.name_sim::numeric, 2),
                            'same_phone', p.same_phone, 'phone_conflict', p.phone_conflict,
                            'same_website', p.same_host, 'website_conflict', p.host_conflict,
                            'name_a', ra.name, 'name_b', rb.name)
  FROM _pairs p
  JOIN source_records ra ON ra.id = p.record_a JOIN source_records rb ON rb.id = p.record_b
  JOIN (SELECT g.record_id, n.entity_id FROM _grp g JOIN _new n ON n.grp = g.grp) ea ON ea.record_id = p.record_a
  JOIN (SELECT g.record_id, n.entity_id FROM _grp g JOIN _new n ON n.grp = g.grp) eb ON eb.record_id = p.record_b
  WHERE NOT p.auto AND ea.entity_id <> eb.entity_id AND p.name_sim >= p_auto_sim;
  GET DIAGNOSTICS v_review = ROW_COUNT;

  RETURN jsonb_build_object('entities_created', v_entities, 'records_merged_into_existing_groups', v_merged,
                            'merge_proposals_for_review', v_review, 'legal_name_places_flagged', v_held);
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_field(p_entity uuid, p_record bigint, p_run bigint, p_field text,
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
  FOR r IN
    SELECT DISTINCT ON (sr.id) sr.id, e.id AS entity_id,
           source_record_values(sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website,
                                sr.location, sr.category_id, sr.payload) AS new
    FROM source_records sr
    JOIN entities e ON ST_DWithin(e.location, sr.location, 75)
    WHERE sr.source_id = v_run.source_id AND sr.first_seen_run = p_run_id AND sr.match_status = 'unmatched'
      AND sr.location IS NOT NULL AND NOT is_legal_entity_name(sr.name)
      AND e.status NOT IN ('merged', 'removed') AND e.created_at < v_started
      AND names_match(sr.name, sr.payload->>'brand', e.name)
      AND (match_phone(sr.phone) = match_phone(e.phone)
           OR (match_url(sr.website) = match_url(e.website)
               AND NOT COALESCE(match_phone(sr.phone) <> match_phone(e.phone), false)))
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

-- 5. Close pending proposals that were only formatting, or a town/ZIP from another source.
UPDATE public.change_events
SET status = 'superseded', decided_by = 'migration: formatting only', decided_at = now()
WHERE status = 'pending' AND event_type = 'attribute_change'
  AND field IN ('name', 'address', 'city', 'state', 'postal_code', 'phone', 'website')
  AND (public.values_equivalent(field, old_value #>> '{}', new_value #>> '{}')
       OR (field IN ('city', 'postal_code') AND evidence->>'reason' = 'a source we trust more for this field disagrees'));
