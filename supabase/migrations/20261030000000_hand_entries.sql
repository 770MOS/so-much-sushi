-- Places we are responsible for (agreed 2026-10-29).
--
-- 1. A source joining a place for the first time now proposes where it disagrees with a
--    value entered by hand. Before, only later changes were proposed, so a first
--    disagreement went unnoticed. Formatting-only differences, town and ZIP still are not.
-- 2. "Last checked": any hand edit or hand-added place sets entities.last_verified, and
--    admin_mark_checked() records "checked, still correct" without changing anything.
-- 3. All places can show only places added by hand, places no source has, and places no
--    source has that nobody has checked in 6 months.
SET search_path = public, extensions;

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

  -- A hand edit: never changed. A source joining the place for the first time proposes
  -- where it disagrees (town and ZIP excepted, as everywhere); a record already on the
  -- place proposes when it changes.
  IF v_prov.method = 'manual' THEN
    IF p_is_new THEN
      IF p_new IS NULL OR p_field IN ('city', 'postal_code') THEN RETURN NULL; END IF;
      PERFORM propose_change('attribute_change', p_entity, v_src, p_record, p_run, p_field, to_jsonb(v_cur), to_jsonb(p_new),
        jsonb_build_object('reason', 'a source disagrees with a value entered by hand'));
      RETURN 'proposed';
    END IF;
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

-- Any decision made by hand on a place counts as checking it.
CREATE FUNCTION public.set_last_checked()
  RETURNS trigger
  LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
  UPDATE public.entities SET last_verified = COALESCE(NEW.applied_at, now()) WHERE id = NEW.entity_id;
  RETURN NULL;
END $$;
CREATE TRIGGER change_events_set_last_checked AFTER INSERT ON public.change_events
  FOR EACH ROW WHEN (NEW.event_type IN ('manual_edit', 'new_candidate') AND NEW.status = 'approved' AND NEW.entity_id IS NOT NULL)
  EXECUTE FUNCTION public.set_last_checked();

-- Hand-added places that already exist count as checked when they were added.
UPDATE public.entities e SET last_verified = c.at
FROM (SELECT entity_id, max(COALESCE(applied_at, created_at)) AS at FROM public.change_events
      WHERE event_type IN ('manual_edit', 'new_candidate') AND status = 'approved' GROUP BY 1) c
WHERE e.id = c.entity_id AND e.last_verified IS NULL;

CREATE FUNCTION public.admin_mark_checked(p_ids uuid[], p_decided_by text, p_note text DEFAULT NULL)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_src smallint; v_n integer;
BEGIN
  SELECT id INTO v_src FROM sources WHERE code = 'manual_research';
  INSERT INTO change_events (event_type, entity_id, source_id, field, old_value, new_value, evidence,
                             status, decided_by, decided_at, applied_at)
  SELECT 'manual_edit', e.id, v_src, 'last_checked', to_jsonb(e.last_verified), to_jsonb(now()),
         jsonb_build_object('note', p_note, 'checked', true), 'approved', p_decided_by, now(), now()
  FROM entities e WHERE e.id = ANY (p_ids) AND e.status <> 'merged';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_mark_checked(uuid[], text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mark_checked(uuid[], text, text) TO service_role;

DROP FUNCTION public.admin_search_places(text, text, text, text, text, text[], text, boolean, boolean, integer, integer);
CREATE FUNCTION public.admin_search_places(
    p_q text DEFAULT NULL, p_state text DEFAULT NULL, p_city text DEFAULT NULL, p_zip text DEFAULT NULL,
    p_main text DEFAULT NULL, p_tags text[] DEFAULT NULL, p_status text DEFAULT NULL,
    p_needs_review boolean DEFAULT NULL, p_untagged boolean DEFAULT NULL,
    p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_origin text DEFAULT NULL)
  RETURNS TABLE(id uuid, name text, address text, city text, state text, postal_code text, phone text,
                website text, status text, needs_review boolean, main_category text, tags text[],
                updated_at timestamptz, total bigint,
                added_by_hand boolean, source_records integer, last_checked timestamptz)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT e.id, e.name, e.address, e.city, e.state, e.postal_code, e.phone, e.website, e.status,
         e.needs_review, m.name,
         COALESCE((SELECT array_agg(c.name ORDER BY c.path)
                   FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
                   WHERE ec.entity_id = e.id), '{}'),
         e.updated_at, count(*) OVER (), o.by_hand, o.records, e.last_verified
  FROM entities e
  JOIN categories m ON m.id = e.main_category_id
  CROSS JOIN LATERAL (SELECT
      EXISTS (SELECT 1 FROM change_events c WHERE c.entity_id = e.id AND c.event_type = 'new_candidate'
                AND (c.evidence->>'added_by_hand')::boolean) AS by_hand,
      (SELECT count(*)::integer FROM source_records sr WHERE sr.entity_id = e.id) AS records) o
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
    -- hand: added by hand. unconfirmed: no source has it. stale: no source has it and
    -- nobody has checked it in 6 months.
    AND (p_origin IS NULL
         OR (p_origin = 'hand' AND o.by_hand)
         OR (p_origin = 'unconfirmed' AND o.records = 0)
         OR (p_origin = 'stale' AND o.records = 0
             AND COALESCE(e.last_verified, e.created_at) < now() - interval '6 months'))
  ORDER BY e.name, e.id
  LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0);
$$;
REVOKE EXECUTE ON FUNCTION public.admin_search_places(text, text, text, text, text, text[], text, boolean, boolean, integer, integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_places(text, text, text, text, text, text[], text, boolean, boolean, integer, integer, text) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_get_place(p_id uuid)
  RETURNS jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'name', e.name, 'address', e.address, 'city', e.city, 'state', e.state,
    'postal_code', e.postal_code, 'phone', e.phone, 'website', e.website, 'status', e.status,
    'needs_review', e.needs_review, 'merged_into', e.merged_into,
    'created_at', e.created_at, 'updated_at', e.updated_at, 'last_checked', e.last_verified,
    'added_by_hand', EXISTS (SELECT 1 FROM change_events c WHERE c.entity_id = e.id AND c.event_type = 'new_candidate'
                               AND (c.evidence->>'added_by_hand')::boolean),
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
