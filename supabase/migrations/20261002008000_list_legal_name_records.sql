-- Decision: records whose name is a legal entity are listed rather than held back
-- (err toward listing). Each becomes its own place with needs_review = true so the
-- name can be corrected later.
SET search_path = public, extensions;

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
               AND (coalesce(same_phone, false) OR coalesce(same_host, false))
               AND NOT coalesce(phone_conflict, false) AND NOT coalesce(host_conflict, false)) AS auto
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
