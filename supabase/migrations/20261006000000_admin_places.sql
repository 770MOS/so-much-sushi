-- Functions behind /admin/places: browse every place with filters, open one,
-- edit it, and set its tags. Service role only, like the rest of the admin API.
-- Every edit is written to change_events and marks the field as manually set
-- in entity_field_provenance, so later source loads can tell a hand-corrected
-- value from a source-supplied one.
SET search_path = public, extensions;

-- Browse. A place matches the tag filter if any of its tags is one of the chosen
-- tags or sits beneath one. Merged tombstones are hidden unless asked for.
CREATE FUNCTION public.admin_search_places(
    p_q text DEFAULT NULL, p_state text DEFAULT NULL, p_city text DEFAULT NULL, p_zip text DEFAULT NULL,
    p_main text DEFAULT NULL, p_tags text[] DEFAULT NULL, p_status text DEFAULT NULL,
    p_needs_review boolean DEFAULT NULL, p_untagged boolean DEFAULT NULL,
    p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
  RETURNS TABLE(id uuid, name text, address text, city text, state text, postal_code text, phone text,
                website text, status text, needs_review boolean, main_category text, tags text[],
                updated_at timestamptz, total bigint)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT e.id, e.name, e.address, e.city, e.state, e.postal_code, e.phone, e.website, e.status,
         e.needs_review, m.name,
         COALESCE((SELECT array_agg(c.name ORDER BY c.path)
                   FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
                   WHERE ec.entity_id = e.id), '{}'),
         e.updated_at, count(*) OVER ()
  FROM entities e
  JOIN categories m ON m.id = e.main_category_id
  WHERE (CASE WHEN p_status IS NULL THEN e.status <> 'merged' ELSE e.status = p_status END)
    AND (NULLIF(trim(p_q), '') IS NULL OR e.name ILIKE '%' || trim(p_q) || '%')
    AND (p_state IS NULL OR e.state = p_state)
    AND (p_city IS NULL OR e.city = p_city)
    AND (NULLIF(trim(p_zip), '') IS NULL OR left(e.postal_code, 5) = left(trim(p_zip), 5))
    AND (p_main IS NULL OR m.path = p_main::ltree)
    AND (p_needs_review IS NULL OR e.needs_review = p_needs_review)
    AND (p_untagged IS NOT TRUE OR NOT EXISTS (SELECT 1 FROM entity_categories ec WHERE ec.entity_id = e.id))
    AND (p_tags IS NULL OR cardinality(p_tags) = 0 OR EXISTS (
          SELECT 1 FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
          WHERE ec.entity_id = e.id AND c.path <@ ANY (p_tags::ltree[])))
  ORDER BY e.name, e.id
  LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0);
$$;
REVOKE EXECUTE ON FUNCTION public.admin_search_places(text, text, text, text, text, text[], text, boolean, boolean, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_places(text, text, text, text, text, text[], text, boolean, boolean, integer, integer) TO service_role;

-- Values for the State and Town dropdowns, with counts. Towns narrow to the chosen state.
CREATE FUNCTION public.admin_place_filters(p_state text DEFAULT NULL)
  RETURNS jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'states', (SELECT COALESCE(jsonb_agg(jsonb_build_object('value', s, 'count', n) ORDER BY s), '[]'::jsonb)
               FROM (SELECT state AS s, count(*) AS n FROM entities
                     WHERE status <> 'merged' AND NULLIF(state, '') IS NOT NULL GROUP BY 1) x),
    'cities', (SELECT COALESCE(jsonb_agg(jsonb_build_object('value', c, 'count', n) ORDER BY c), '[]'::jsonb)
               FROM (SELECT city AS c, count(*) AS n FROM entities
                     WHERE status <> 'merged' AND NULLIF(city, '') IS NOT NULL
                       AND (p_state IS NULL OR state = p_state) GROUP BY 1) y));
$$;
REVOKE EXECUTE ON FUNCTION public.admin_place_filters(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_place_filters(text) TO service_role;

-- Everything the place screen shows, in one call.
CREATE FUNCTION public.admin_get_place(p_id uuid)
  RETURNS jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'name', e.name, 'address', e.address, 'city', e.city, 'state', e.state,
    'postal_code', e.postal_code, 'phone', e.phone, 'website', e.website, 'status', e.status,
    'needs_review', e.needs_review, 'merged_into', e.merged_into,
    'created_at', e.created_at, 'updated_at', e.updated_at,
    'lat', ST_Y(e.location::geometry), 'lng', ST_X(e.location::geometry),
    'main_category', m.path::text,
    'tags', COALESCE((SELECT jsonb_agg(c.path::text ORDER BY c.path)
                      FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
                      WHERE ec.entity_id = e.id), '[]'::jsonb),
    'saved', jsonb_build_object(
      'stars', (SELECT count(*) FROM stars s WHERE s.entity_id = e.id),
      'lists', (SELECT count(*) FROM list_items li WHERE li.entity_id = e.id)),
    'provenance', COALESCE((SELECT jsonb_object_agg(p.field, jsonb_build_object(
                              'source', s.name, 'license', p.license, 'method', p.method, 'set_at', p.set_at))
                            FROM entity_field_provenance p JOIN sources s ON s.id = p.source_id
                            WHERE p.entity_id = e.id), '{}'::jsonb),
    'source_records', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                              'id', r.id, 'source', s.name, 'contributor', r.upstream_dataset, 'license', r.license,
                              'name', r.name, 'address', r.address, 'phone', r.phone, 'website', r.website,
                              'category', r.source_category, 'confidence', r.source_confidence,
                              'operating_status', r.payload->>'operating_status', 'match_method', r.match_method)
                              ORDER BY r.source_confidence DESC NULLS LAST, r.id)
                            FROM source_records r JOIN sources s ON s.id = r.source_id
                            WHERE r.entity_id = e.id), '[]'::jsonb),
    'history', COALESCE((SELECT jsonb_agg(h ORDER BY (h->>'at') DESC)
                         FROM (SELECT jsonb_build_object(
                                 'id', c.id, 'type', c.event_type, 'field', c.field, 'status', c.status,
                                 'old', c.old_value, 'new', c.new_value, 'by', c.decided_by,
                                 'note', c.evidence->>'note', 'at', COALESCE(c.decided_at, c.created_at)) AS h
                               FROM change_events c WHERE c.entity_id = e.id
                               ORDER BY c.id DESC LIMIT 50) hh), '[]'::jsonb))
  FROM entities e JOIN categories m ON m.id = e.main_category_id
  WHERE e.id = p_id;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_get_place(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_place(uuid) TO service_role;

-- Edit a place by hand. p_changes may hold any of: name, address, city, state,
-- postal_code, phone, website, status, main_category (a root path), needs_review.
-- Only values that actually differ are changed. Returns how many fields changed.
CREATE FUNCTION public.admin_update_place(p_id uuid, p_changes jsonb, p_decided_by text, p_note text DEFAULT NULL)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v entities%ROWTYPE; v_key text; v_new text; v_old text; v_n integer := 0;
  v_src smallint; v_lic text; v_main uuid; v_prov text;
BEGIN
  SELECT * INTO v FROM entities WHERE id = p_id FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'place % not found', p_id; END IF;
  IF v.status = 'merged' THEN RAISE EXCEPTION 'this place was merged into another; edit that one instead'; END IF;
  SELECT id, license INTO v_src, v_lic FROM sources WHERE code = 'manual_research';
  IF v_src IS NULL THEN RAISE EXCEPTION 'source manual_research is missing'; END IF;

  FOR v_key IN SELECT jsonb_object_keys(p_changes) LOOP
    IF v_key NOT IN ('name', 'address', 'city', 'state', 'postal_code', 'phone', 'website',
                     'status', 'main_category', 'needs_review') THEN
      RAISE EXCEPTION 'field % cannot be edited here', v_key;
    END IF;
    v_new := NULLIF(trim(p_changes->>v_key), '');
    v_old := CASE v_key
      WHEN 'name' THEN v.name WHEN 'address' THEN v.address WHEN 'city' THEN v.city
      WHEN 'state' THEN v.state WHEN 'postal_code' THEN v.postal_code WHEN 'phone' THEN v.phone
      WHEN 'website' THEN v.website WHEN 'status' THEN v.status
      WHEN 'needs_review' THEN v.needs_review::text
      WHEN 'main_category' THEN (SELECT path::text FROM categories WHERE id = v.main_category_id) END;
    IF v_key = 'needs_review' THEN v_new := COALESCE(v_new::boolean, false)::text; END IF;
    CONTINUE WHEN v_new IS NOT DISTINCT FROM v_old;

    IF v_key = 'name' AND v_new IS NULL THEN RAISE EXCEPTION 'a place needs a name'; END IF;
    IF v_key = 'status' AND v_new NOT IN ('active', 'temporarily_closed', 'permanently_closed', 'removed') THEN
      RAISE EXCEPTION 'status % is not allowed here', v_new;
    END IF;

    IF v_key = 'main_category' THEN
      SELECT id INTO v_main FROM categories WHERE path = v_new::ltree AND nlevel(path) = 1;
      IF v_main IS NULL THEN RAISE EXCEPTION '% is not a main category', v_new; END IF;
      UPDATE entities SET main_category_id = v_main WHERE id = p_id;
    ELSIF v_key = 'needs_review' THEN
      UPDATE entities SET needs_review = v_new::boolean WHERE id = p_id;
    ELSE
      EXECUTE format('UPDATE entities SET %I = $1 WHERE id = $2', v_key) USING v_new, p_id;
    END IF;

    v_prov := CASE WHEN v_key IN ('city', 'state', 'postal_code') THEN 'address'
                   WHEN v_key = 'main_category' THEN 'categories'
                   WHEN v_key = 'needs_review' THEN NULL ELSE v_key END;
    IF v_prov IS NOT NULL THEN
      INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
      VALUES (p_id, v_prov, v_src, NULL, v_lic, 'manual', now())
      ON CONFLICT (entity_id, field) DO UPDATE
        SET source_id = EXCLUDED.source_id, source_record_pk = NULL, license = EXCLUDED.license,
            method = 'manual', set_at = now();
    END IF;

    INSERT INTO change_events (event_type, entity_id, source_id, field, old_value, new_value, evidence,
                               status, decided_by, decided_at, applied_at)
    VALUES ('manual_edit', p_id, v_src, v_key, to_jsonb(v_old), to_jsonb(v_new),
            jsonb_build_object('note', p_note), 'approved', p_decided_by, now(), now());
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_update_place(uuid, jsonb, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_place(uuid, jsonb, text, text) TO service_role;

-- Replace a place's tags with the given set of category paths (main categories are
-- not tags and are refused). Pending suggestions for a tag that is now set are closed.
-- Returns true if anything changed.
CREATE FUNCTION public.admin_set_place_tags(p_id uuid, p_tags text[], p_decided_by text)
  RETURNS boolean
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_status text; v_old text[]; v_new text[]; v_src smallint; v_lic text;
BEGIN
  SELECT status INTO v_status FROM entities WHERE id = p_id FOR UPDATE;
  IF v_status IS NULL THEN RAISE EXCEPTION 'place % not found', p_id; END IF;
  IF v_status = 'merged' THEN RAISE EXCEPTION 'this place was merged into another; edit that one instead'; END IF;

  SELECT COALESCE(array_agg(DISTINCT t ORDER BY t), '{}') INTO v_new FROM unnest(COALESCE(p_tags, '{}')) t;
  IF EXISTS (SELECT 1 FROM unnest(v_new) t
             WHERE NOT EXISTS (SELECT 1 FROM categories c WHERE c.path = t::ltree AND nlevel(c.path) > 1)) THEN
    RAISE EXCEPTION 'one of the tags does not exist or is a main category';
  END IF;
  SELECT COALESCE(array_agg(c.path::text ORDER BY c.path::text), '{}') INTO v_old
  FROM entity_categories ec JOIN categories c ON c.id = ec.category_id WHERE ec.entity_id = p_id;
  IF v_old = v_new THEN RETURN false; END IF;

  DELETE FROM entity_categories WHERE entity_id = p_id;
  INSERT INTO entity_categories (entity_id, category_id)
  SELECT p_id, c.id FROM categories c WHERE c.path::text = ANY (v_new);

  SELECT id, license INTO v_src, v_lic FROM sources WHERE code = 'manual_research';
  INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
  VALUES (p_id, 'categories', v_src, NULL, v_lic, 'manual', now())
  ON CONFLICT (entity_id, field) DO UPDATE
    SET source_id = EXCLUDED.source_id, source_record_pk = NULL, license = EXCLUDED.license,
        method = 'manual', set_at = now();

  INSERT INTO change_events (event_type, entity_id, source_id, field, old_value, new_value,
                             status, decided_by, decided_at, applied_at)
  VALUES ('manual_edit', p_id, v_src, 'tags', to_jsonb(v_old), to_jsonb(v_new), 'approved', p_decided_by, now(), now());

  UPDATE change_events SET status = 'superseded', decided_by = p_decided_by, decided_at = now()
  WHERE entity_id = p_id AND status = 'pending' AND field = 'categories'
    AND new_value->>'add_category' = ANY (v_new);
  RETURN true;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_set_place_tags(uuid, text[], text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_place_tags(uuid, text[], text) TO service_role;
