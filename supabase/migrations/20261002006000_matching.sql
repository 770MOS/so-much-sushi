-- Matching: turn unmatched source records into entities.
--   Auto-merge   near-identical names, close together, phone or website matching and the
--                other not disagreeing.
--   Review       near-identical names close together without that contact evidence. These
--                become separate entities plus a pending 'merge' proposal in the ledger.
--   Held back    records whose name is a legal entity ("... LLC"); they wait for review.
-- A shared phone or website alone never merges anything, and renamed places at one address
-- stay separate entities.
SET search_path = public, extensions;

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;

-- Name with case, punctuation, spacing, a leading "the" and "&"/"and" differences removed.
CREATE FUNCTION public.match_name(p text) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = '' AS $$
  SELECT regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p, '')), '&', ' and ', 'g'),
                                       '[^a-z0-9]+', '', 'g'), '^the', '');
$$;

CREATE FUNCTION public.match_phone(p text) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = '' AS $$
  SELECT CASE WHEN length(regexp_replace(coalesce(p, ''), '\D', '', 'g')) >= 10
              THEN right(regexp_replace(p, '\D', '', 'g'), 10) END;
$$;

-- Website host, or NULL when it is a shared platform that says nothing about identity.
CREATE FUNCTION public.match_host(p text) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = '' AS $$
  SELECT CASE WHEN h IS NULL OR h = '' OR h ~ '(^|\.)(facebook|instagram|yelp|google|linktr|doordash|ubereats|grubhub|toasttab|squareup|square|opentable|resy|tripadvisor|twitter|x|tiktok|wixsite|business)\.(com|ee|site)$'
              THEN NULL ELSE h END
  FROM (SELECT regexp_replace(lower(coalesce(p, '')), '^https?://(www\.)?([^/?#]+).*$', '\2') AS h) t;
$$;

CREATE FUNCTION public.is_legal_entity_name(p text) RETURNS boolean
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path = '' AS $$
  SELECT coalesce(p, '') ~* '\m(llc|l\.l\.c|inc|incorporated|lp|l\.p|llp|corp|corporation|ltd|lnc)\M\.?\s*$';
$$;
REVOKE EXECUTE ON FUNCTION public.match_name(text), public.match_phone(text), public.match_host(text),
                           public.is_legal_entity_name(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_name(text), public.match_phone(text), public.match_host(text),
                          public.is_legal_entity_name(text) TO service_role;

-- Candidate duplicate pairs among unmatched records of one source, with the evidence for each.
CREATE FUNCTION public.match_candidate_pairs(p_source_code text, p_max_m integer DEFAULT 75, p_min_sim real DEFAULT 0.6)
  RETURNS TABLE(record_a bigint, record_b bigint, distance_m integer, name_sim real,
                same_phone boolean, phone_conflict boolean, same_host boolean, host_conflict boolean)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  WITH r AS (
    SELECT sr.id, sr.location, match_name(sr.name) AS n, match_phone(sr.phone) AS ph, match_host(sr.website) AS host
    FROM source_records sr JOIN sources s ON s.id = sr.source_id
    WHERE s.code = p_source_code AND sr.match_status = 'unmatched' AND sr.location IS NOT NULL
      AND NOT is_legal_entity_name(sr.name))
  SELECT a.id, b.id, round(ST_Distance(a.location, b.location))::integer, similarity(a.n, b.n),
         a.ph = b.ph, a.ph <> b.ph, a.host = b.host, a.host <> b.host
  FROM r a JOIN r b ON a.id < b.id AND ST_DWithin(a.location, b.location, p_max_m)
  WHERE similarity(a.n, b.n) >= p_min_sim;
$$;
REVOKE EXECUTE ON FUNCTION public.match_candidate_pairs(text, integer, real) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_candidate_pairs(text, integer, real) TO service_role;

-- Create entities from the unmatched records of one source. Returns counts.
CREATE FUNCTION public.build_entities_from_source(p_source_code text, p_decided_by text,
                                                  p_auto_sim real DEFAULT 0.9, p_max_m integer DEFAULT 75)
  RETURNS jsonb
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v_source smallint; v_changed integer; v_held integer; v_entities integer; v_merged integer; v_review integer;
BEGIN
  SELECT id INTO v_source FROM sources WHERE code = p_source_code AND is_active;
  IF v_source IS NULL THEN RAISE EXCEPTION 'source % is missing or inactive', p_source_code; END IF;

  -- Legal-entity names wait for a person.
  UPDATE source_records SET match_status = 'needs_review', match_method = 'legal entity name'
  WHERE source_id = v_source AND match_status = 'unmatched' AND is_legal_entity_name(name);
  GET DIAGNOSTICS v_held = ROW_COUNT;

  CREATE TEMP TABLE _pairs ON COMMIT DROP AS
    SELECT *, (name_sim >= p_auto_sim
               AND (coalesce(same_phone, false) OR coalesce(same_host, false))
               AND NOT coalesce(phone_conflict, false) AND NOT coalesce(host_conflict, false)) AS auto
    FROM match_candidate_pairs(p_source_code, p_max_m, LEAST(p_auto_sim, 0.6::real));

  -- Group records joined by auto pairs (connected components, smallest id as the label).
  CREATE TEMP TABLE _grp ON COMMIT DROP AS
    SELECT sr.id AS record_id, sr.id AS grp FROM source_records sr
    WHERE sr.source_id = v_source AND sr.match_status = 'unmatched' AND sr.location IS NOT NULL;
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
           NOT coalesce((sr.payload->>'category_mapped')::boolean, false) AS needs_review
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
         match_method = CASE WHEN sr.id = n.best_record THEN 'new entity' ELSE 'auto: name + contact' END
  FROM _grp g JOIN _new n ON n.grp = g.grp WHERE sr.id = g.record_id;
  SELECT count(*) INTO v_merged FROM _grp g JOIN _new n ON n.grp = g.grp WHERE g.record_id <> n.best_record;

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
                            'merge_proposals_for_review', v_review, 'legal_name_records_held', v_held);
END $$;
REVOKE EXECUTE ON FUNCTION public.build_entities_from_source(text, text, real, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.build_entities_from_source(text, text, real, integer) TO service_role;
