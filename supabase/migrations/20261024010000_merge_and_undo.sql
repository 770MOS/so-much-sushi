-- Manual tools, part 1 (agreed 2026-10-24): merge any two places choosing field by field,
-- and undo a merge.
--
-- admin_merge_places(survivor, duplicate, take, ...)
--   take lists the fields whose value comes from the duplicate: name, address (street,
--   town, state and ZIP together), phone, website, location, main_category, status.
--   With p_fill_empty (default true), any field the survivor lacks is also taken from
--   the duplicate. A taken value keeps its source attribution (provenance is copied), so
--   it goes on following that source. Tags from both places are kept. Then the existing
--   merge_entities() moves records, stars, hidden marks and list items and leaves the
--   duplicate as a pointer. Everything needed to undo is written to the merge's ledger
--   entry.
--
-- admin_undo_merge(merge event, ...)
--   Splits the places again: the duplicate comes back with its status, its source records
--   return, stars / hidden marks / list items move back (unless the person removed them
--   since), tags added by the merge are removed, and the survivor's fields go back to
--   what they were, except fields edited since the merge, which are left alone and
--   reported. The proposal that led to the merge is marked "different places". Both
--   places get an "unmerge" ledger entry.
--
-- decide_merge_proposals() now merges through admin_merge_places(), so batch merges also
-- fill empty fields and keep both places' tags.
SET search_path = public, extensions;

CREATE FUNCTION public.merge_field_values(e entities)
  RETURNS jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'name', e.name,
    'address', jsonb_build_object('address', e.address, 'city', e.city, 'state', e.state, 'postal_code', e.postal_code),
    'phone', e.phone, 'website', e.website,
    'location', ST_AsText(e.location),
    'main_category', (SELECT path::text FROM categories WHERE id = e.main_category_id),
    'status', e.status);
$$;
REVOKE EXECUTE ON FUNCTION public.merge_field_values(entities) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merge_field_values(entities) TO service_role;

CREATE FUNCTION public.admin_merge_places(p_survivor uuid, p_duplicate uuid, p_take text[], p_decided_by text,
                                          p_note text DEFAULT NULL, p_proposal bigint DEFAULT NULL,
                                          p_fill_empty boolean DEFAULT true)
  RETURNS bigint
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v_sur entities%ROWTYPE; v_dup entities%ROWTYPE; v_take text[]; f text;
  v_before jsonb; v_after jsonb; v_prov jsonb; v_tags jsonb; v_event bigint;
  c_fields constant text[] := ARRAY['name', 'address', 'phone', 'website', 'location', 'main_category', 'status'];
BEGIN
  IF p_survivor = p_duplicate THEN RAISE EXCEPTION 'cannot merge a place into itself'; END IF;
  PERFORM 1 FROM entities WHERE id IN (p_survivor, p_duplicate) ORDER BY id FOR UPDATE;
  SELECT * INTO v_sur FROM entities WHERE id = p_survivor;
  SELECT * INTO v_dup FROM entities WHERE id = p_duplicate;
  IF v_sur.id IS NULL OR v_dup.id IS NULL THEN RAISE EXCEPTION 'both places must exist'; END IF;
  IF v_sur.status IN ('merged', 'removed') THEN RAISE EXCEPTION 'the place being kept is %', v_sur.status; END IF;
  IF v_dup.status = 'merged' THEN RAISE EXCEPTION 'the other place was already merged'; END IF;

  v_take := COALESCE(p_take, '{}');
  FOREACH f IN ARRAY v_take LOOP
    IF NOT f = ANY(c_fields) THEN RAISE EXCEPTION 'field % cannot be chosen in a merge', f; END IF;
  END LOOP;
  IF p_fill_empty THEN
    IF v_sur.address IS NULL AND v_sur.city IS NULL AND (v_dup.address IS NOT NULL OR v_dup.city IS NOT NULL) THEN v_take := v_take || 'address'::text; END IF;
    IF v_sur.phone IS NULL AND v_dup.phone IS NOT NULL THEN v_take := v_take || 'phone'::text; END IF;
    IF v_sur.website IS NULL AND v_dup.website IS NOT NULL THEN v_take := v_take || 'website'::text; END IF;
    IF v_sur.location IS NULL AND v_dup.location IS NOT NULL THEN v_take := v_take || 'location'::text; END IF;
  END IF;
  -- The duplicate's "removed" status is never carried over.
  IF 'status' = ANY(v_take) AND v_dup.status NOT IN ('active', 'temporarily_closed', 'permanently_closed') THEN
    v_take := array_remove(v_take, 'status');
  END IF;
  SELECT COALESCE(array_agg(DISTINCT x), '{}') INTO v_take FROM unnest(v_take) x;

  -- What the survivor had for every field it is about to take, and where it came from.
  v_before := (SELECT jsonb_object_agg(k, merge_field_values(v_sur)->k) FROM unnest(v_take) k);
  SELECT COALESCE(jsonb_object_agg(p.field, to_jsonb(p) - 'entity_id'), '{}') INTO v_prov
  FROM entity_field_provenance p
  WHERE p.entity_id = p_survivor
    AND p.field = ANY(SELECT CASE k WHEN 'main_category' THEN 'categories' ELSE k END FROM unnest(v_take) k);

  UPDATE entities e SET
    name        = CASE WHEN 'name'          = ANY(v_take) THEN v_dup.name        ELSE e.name END,
    address     = CASE WHEN 'address'       = ANY(v_take) THEN v_dup.address     ELSE e.address END,
    city        = CASE WHEN 'address'       = ANY(v_take) THEN v_dup.city        ELSE e.city END,
    state       = CASE WHEN 'address'       = ANY(v_take) THEN v_dup.state       ELSE e.state END,
    postal_code = CASE WHEN 'address'       = ANY(v_take) THEN v_dup.postal_code ELSE e.postal_code END,
    phone       = CASE WHEN 'phone'         = ANY(v_take) THEN v_dup.phone       ELSE e.phone END,
    website     = CASE WHEN 'website'       = ANY(v_take) THEN v_dup.website     ELSE e.website END,
    location    = CASE WHEN 'location'      = ANY(v_take) THEN v_dup.location    ELSE e.location END,
    main_category_id = CASE WHEN 'main_category' = ANY(v_take) THEN v_dup.main_category_id ELSE e.main_category_id END,
    status      = CASE WHEN 'status'        = ANY(v_take) THEN v_dup.status      ELSE e.status END
  WHERE e.id = p_survivor
  RETURNING merge_field_values(e) INTO v_after;
  v_after := (SELECT jsonb_object_agg(k, v_after->k) FROM unnest(v_take) k);

  -- A taken value keeps the duplicate's attribution.
  DELETE FROM entity_field_provenance
  WHERE entity_id = p_survivor
    AND field = ANY(SELECT CASE k WHEN 'main_category' THEN 'categories' ELSE k END FROM unnest(v_take) k);
  INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
  SELECT p_survivor, p.field, p.source_id, p.source_record_pk, p.license, p.method, now()
  FROM entity_field_provenance p
  WHERE p.entity_id = p_duplicate
    AND p.field = ANY(SELECT CASE k WHEN 'main_category' THEN 'categories' ELSE k END FROM unnest(v_take) k);

  -- Tags from both places are kept.
  WITH added AS (
    INSERT INTO entity_categories (entity_id, category_id)
    SELECT p_survivor, ec.category_id FROM entity_categories ec WHERE ec.entity_id = p_duplicate
    ON CONFLICT DO NOTHING RETURNING category_id)
  SELECT COALESCE(jsonb_agg(category_id), '[]') INTO v_tags FROM added;

  v_event := merge_entities(p_duplicate, p_survivor, p_decided_by, p_note);
  UPDATE change_events SET evidence = evidence || jsonb_build_object(
      'taken_from_duplicate', to_jsonb(v_take), 'survivor_before', COALESCE(v_before, '{}'),
      'survivor_after', COALESCE(v_after, '{}'), 'survivor_before_provenance', v_prov,
      'tags_added', v_tags, 'proposal', p_proposal, 'duplicate_name', v_dup.name)
  WHERE id = v_event;

  -- The proposal that asked for this merge, and any other open proposal for the same pair.
  UPDATE change_events SET status = 'approved', decided_by = p_decided_by, decided_at = now(), applied_at = now()
  WHERE id = p_proposal AND status = 'pending';
  UPDATE change_events SET status = 'superseded', decided_by = p_decided_by, decided_at = now()
  WHERE event_type = 'merge' AND status = 'pending' AND id IS DISTINCT FROM p_proposal
    AND ((entity_id = p_survivor AND old_value->>'duplicate' = p_duplicate::text)
      OR (entity_id = p_duplicate AND old_value->>'duplicate' = p_survivor::text));
  RETURN v_event;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_merge_places(uuid, uuid, text[], text, text, bigint, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_merge_places(uuid, uuid, text[], text, text, bigint, boolean) TO service_role;

CREATE FUNCTION public.admin_undo_merge(p_merge_event bigint, p_decided_by text, p_note text DEFAULT NULL)
  RETURNS jsonb
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  m change_events%ROWTYPE; v_sur uuid; v_dup uuid; d entities%ROWTYPE; s entities%ROWTYPE;
  k text; v_cur jsonb; v_restored text[] := '{}'; v_kept text[] := '{}'; v_records integer; v_unmerge bigint;
  v_prov_field text; v_saved jsonb; v_addr jsonb;
  v_stars integer := 0; v_hidden integer := 0; v_items integer := 0; v_n integer; v_proposal bigint;
BEGIN
  SELECT * INTO m FROM change_events WHERE id = p_merge_event FOR UPDATE;
  IF m.id IS NULL OR m.event_type <> 'merge' OR m.status <> 'approved' OR m.applied_at IS NULL
     OR NOT m.old_value ? 'duplicate' OR NOT m.evidence ? 'source_records' THEN
    RAISE EXCEPTION 'ledger entry % is not a completed merge', p_merge_event;
  END IF;
  IF m.evidence ? 'undone_by' THEN RAISE EXCEPTION 'this merge was already undone'; END IF;
  v_sur := m.entity_id;
  v_dup := (m.old_value->>'duplicate')::uuid;
  PERFORM 1 FROM entities WHERE id IN (v_sur, v_dup) ORDER BY id FOR UPDATE;
  SELECT * INTO d FROM entities WHERE id = v_dup;
  SELECT * INTO s FROM entities WHERE id = v_sur;
  IF d.status <> 'merged' OR d.merged_into IS DISTINCT FROM v_sur THEN
    RAISE EXCEPTION 'the merged place no longer points to this place, so this merge cannot be undone';
  END IF;
  IF s.status = 'merged' THEN
    RAISE EXCEPTION 'the kept place was itself merged into another since; undo that merge first';
  END IF;

  -- Source records go back.
  UPDATE source_records SET entity_id = v_dup
  WHERE entity_id = v_sur AND id IN (SELECT jsonb_array_elements_text(m.evidence->'source_records')::bigint);
  GET DIAGNOSTICS v_records = ROW_COUNT;

  -- The kept place's fields go back, unless someone changed them since the merge.
  FOR k IN SELECT jsonb_object_keys(COALESCE(m.evidence->'survivor_before', '{}')) LOOP
    v_cur := merge_field_values(s)->k;
    IF v_cur IS DISTINCT FROM m.evidence->'survivor_after'->k THEN
      v_kept := v_kept || k::text;
      CONTINUE;
    END IF;
    v_saved := m.evidence->'survivor_before'->k;
    IF k = 'address' THEN
      UPDATE entities SET address = v_saved->>'address', city = v_saved->>'city', state = v_saved->>'state',
                          postal_code = v_saved->>'postal_code' WHERE id = v_sur;
    ELSIF k = 'name' THEN UPDATE entities SET name = v_saved #>> '{}' WHERE id = v_sur;
    ELSIF k = 'phone' THEN UPDATE entities SET phone = v_saved #>> '{}' WHERE id = v_sur;
    ELSIF k = 'website' THEN UPDATE entities SET website = v_saved #>> '{}' WHERE id = v_sur;
    ELSIF k = 'status' THEN UPDATE entities SET status = v_saved #>> '{}' WHERE id = v_sur;
    ELSIF k = 'location' THEN
      UPDATE entities SET location = CASE WHEN v_saved #>> '{}' IS NULL THEN NULL
                                          ELSE ST_GeogFromText('SRID=4326;' || (v_saved #>> '{}')) END WHERE id = v_sur;
    ELSIF k = 'main_category' THEN
      UPDATE entities SET main_category_id = (SELECT id FROM categories WHERE path = (v_saved #>> '{}')::ltree) WHERE id = v_sur;
    END IF;
    v_prov_field := CASE k WHEN 'main_category' THEN 'categories' ELSE k END;
    DELETE FROM entity_field_provenance WHERE entity_id = v_sur AND field = v_prov_field;
    IF m.evidence->'survivor_before_provenance' ? v_prov_field THEN
      INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
      SELECT v_sur, v_prov_field, (p->>'source_id')::smallint, (p->>'source_record_pk')::bigint, p->>'license',
             p->>'method', (p->>'set_at')::timestamptz
      FROM (SELECT m.evidence->'survivor_before_provenance'->v_prov_field AS p) x;
    END IF;
    v_restored := v_restored || k::text;
  END LOOP;

  -- Tags the merge added to the kept place.
  DELETE FROM entity_categories
  WHERE entity_id = v_sur
    AND category_id IN (SELECT jsonb_array_elements_text(COALESCE(m.evidence->'tags_added', '[]'))::uuid);

  -- Stars, hidden marks and list items: moved ones go back if still there; dropped ones are restored.
  WITH back AS (
    DELETE FROM stars WHERE entity_id = v_sur
      AND user_id IN (SELECT jsonb_array_elements_text(m.evidence->'stars'->'moved')::uuid)
    RETURNING user_id, created_at)
  INSERT INTO stars (user_id, entity_id, created_at) SELECT user_id, v_dup, created_at FROM back
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_stars = ROW_COUNT;
  INSERT INTO stars (user_id, entity_id, created_at)
  SELECT (x->>'user_id')::uuid, v_dup, (x->>'created_at')::timestamptz
  FROM jsonb_array_elements(COALESCE(m.evidence->'stars'->'dropped', '[]')) x
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_stars := v_stars + v_n;

  WITH back AS (
    DELETE FROM hidden_entities WHERE entity_id = v_sur
      AND user_id IN (SELECT jsonb_array_elements_text(m.evidence->'hidden'->'moved')::uuid)
    RETURNING user_id, created_at)
  INSERT INTO hidden_entities (user_id, entity_id, created_at) SELECT user_id, v_dup, created_at FROM back
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_hidden = ROW_COUNT;
  INSERT INTO hidden_entities (user_id, entity_id, created_at)
  SELECT (x->>'user_id')::uuid, v_dup, (x->>'created_at')::timestamptz
  FROM jsonb_array_elements(COALESCE(m.evidence->'hidden'->'dropped', '[]')) x
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_hidden := v_hidden + v_n;

  WITH back AS (
    DELETE FROM list_items WHERE entity_id = v_sur
      AND list_id IN (SELECT jsonb_array_elements_text(m.evidence->'list_items'->'moved')::uuid)
    RETURNING list_id, note, position, added_at)
  INSERT INTO list_items (list_id, entity_id, note, position, added_at)
  SELECT list_id, v_dup, note, position, added_at FROM back
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_items = ROW_COUNT;
  INSERT INTO list_items (list_id, entity_id, note, position, added_at)
  SELECT (x->>'list_id')::uuid, v_dup, x->>'note', (x->>'position')::integer, (x->>'added_at')::timestamptz
  FROM jsonb_array_elements(COALESCE(m.evidence->'list_items'->'dropped', '[]')) x
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_items := v_items + v_n;

  -- The merged place comes back as it was.
  UPDATE entities SET status = COALESCE(m.old_value->>'duplicate_status', 'active'), merged_into = NULL WHERE id = v_dup;

  INSERT INTO change_events (event_type, entity_id, old_value, new_value, evidence, status, decided_by, decided_at, applied_at)
  VALUES ('unmerge', v_sur, jsonb_build_object('duplicate', v_dup), jsonb_build_object('restored', v_dup),
          jsonb_build_object('note', p_note, 'merge_event', m.id, 'fields_restored', to_jsonb(v_restored),
                             'fields_kept_edited_since', to_jsonb(v_kept), 'source_records_returned', v_records,
                             'stars_returned', v_stars, 'hidden_returned', v_hidden, 'list_items_returned', v_items,
                             'duplicate_name', d.name),
          'approved', p_decided_by, now(), now())
  RETURNING id INTO v_unmerge;
  INSERT INTO change_events (event_type, entity_id, old_value, new_value, evidence, status, decided_by, decided_at, applied_at)
  VALUES ('unmerge', v_dup, jsonb_build_object('merged_into', v_sur), jsonb_build_object('restored', v_dup),
          jsonb_build_object('note', p_note, 'merge_event', m.id, 'unmerge_event', v_unmerge, 'survivor_name', s.name),
          'approved', p_decided_by, now(), now());
  UPDATE change_events SET evidence = evidence || jsonb_build_object('undone_by', v_unmerge) WHERE id = m.id;

  -- The proposal that led here is now "different places", so it does not come back.
  v_proposal := COALESCE((m.evidence->>'proposal')::bigint,
                         substring(m.evidence->>'note' from '^review queue proposal (\d+)$')::bigint);
  UPDATE change_events SET status = 'rejected', decided_by = p_decided_by, decided_at = now(),
         evidence = evidence || jsonb_build_object('rejected_by_undo', v_unmerge)
  WHERE id = v_proposal AND event_type = 'merge';

  RETURN jsonb_build_object('unmerge_event', v_unmerge, 'restored_place', v_dup, 'fields_restored', to_jsonb(v_restored),
                            'fields_kept_edited_since', to_jsonb(v_kept), 'source_records_returned', v_records,
                            'stars_returned', v_stars, 'hidden_returned', v_hidden, 'list_items_returned', v_items);
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_undo_merge(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_undo_merge(bigint, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.decide_merge_proposals(p_events bigint[], p_accept boolean, p_decided_by text)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v change_events%ROWTYPE; v_dup uuid; v_sur uuid; v_n integer := 0;
BEGIN
  FOR v IN SELECT * FROM change_events c
           WHERE c.id = ANY(p_events) AND c.status = 'pending' AND c.event_type = 'merge'
           ORDER BY c.id FOR UPDATE LOOP
    v_sur := resolve_entity(v.entity_id);
    v_dup := resolve_entity((v.old_value->>'duplicate')::uuid);
    IF v_sur = v_dup THEN
      UPDATE change_events SET status = 'superseded', decided_by = p_decided_by, decided_at = now() WHERE id = v.id;
    ELSIF p_accept THEN
      PERFORM admin_merge_places(v_sur, v_dup, '{}', p_decided_by, 'review queue proposal ' || v.id, v.id);
    ELSE
      UPDATE change_events SET status = 'rejected', decided_by = p_decided_by, decided_at = now() WHERE id = v.id;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

-- Candidates for "merge with another place": nearby places, or a name search.
CREATE FUNCTION public.admin_merge_candidates(p_id uuid, p_q text DEFAULT NULL, p_limit integer DEFAULT 20)
  RETURNS TABLE(id uuid, name text, address text, city text, state text, phone text, distance_m integer)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT e.id, e.name, e.address, e.city, e.state, e.phone, round(ST_Distance(e.location, me.location))::integer
  FROM entities me
  JOIN entities e ON e.id <> me.id AND e.status NOT IN ('merged', 'removed')
  WHERE me.id = p_id
    AND CASE WHEN NULLIF(trim(p_q), '') IS NULL THEN ST_DWithin(e.location, me.location, 300)
             ELSE e.name ILIKE '%' || trim(p_q) || '%' END
  ORDER BY ST_Distance(e.location, me.location)
  LIMIT LEAST(GREATEST(p_limit, 1), 50);
$$;
REVOKE EXECUTE ON FUNCTION public.admin_merge_candidates(uuid, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_merge_candidates(uuid, text, integer) TO service_role;

-- Merges into a place, and the merge that turned a place into a pointer: for the Undo buttons.
CREATE FUNCTION public.admin_place_merges(p_id uuid)
  RETURNS TABLE(event_id bigint, role text, other_id uuid, other_name text, merged_at timestamptz,
                merged_by text, taken text[], undone boolean)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT c.id, 'kept', (c.old_value->>'duplicate')::uuid, d.name, c.applied_at, c.decided_by,
         ARRAY(SELECT jsonb_array_elements_text(COALESCE(c.evidence->'taken_from_duplicate', '[]'))),
         c.evidence ? 'undone_by'
  FROM change_events c JOIN entities d ON d.id = (c.old_value->>'duplicate')::uuid
  WHERE c.entity_id = p_id AND c.event_type = 'merge' AND c.status = 'approved' AND c.evidence ? 'source_records'
  UNION ALL
  SELECT c.id, 'merged', c.entity_id, s.name, c.applied_at, c.decided_by,
         ARRAY(SELECT jsonb_array_elements_text(COALESCE(c.evidence->'taken_from_duplicate', '[]'))),
         c.evidence ? 'undone_by'
  FROM change_events c JOIN entities s ON s.id = c.entity_id
  WHERE c.old_value->>'duplicate' = p_id::text AND c.event_type = 'merge' AND c.status = 'approved'
    AND c.evidence ? 'source_records'
  ORDER BY 5 DESC;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_place_merges(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_place_merges(uuid) TO service_role;
