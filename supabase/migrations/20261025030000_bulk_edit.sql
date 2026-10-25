-- Manual tools, part 4: bulk edits from the All places list.
--
-- admin_bulk_update(ids, changes, add_tags, remove_tags, by, note)
--   changes may hold main_category, status and needs_review; each place goes through
--   admin_update_place(), so every changed field is a hand edit with its own ledger entry
--   (the note says it was a bulk edit and how many places it covered). Tags are added
--   and removed with admin_set_place_tags(). Merged places are skipped. All or nothing:
--   one bad value stops the whole edit.
SET search_path = public, extensions;

CREATE FUNCTION public.admin_bulk_update(p_ids uuid[], p_changes jsonb, p_add_tags text[], p_remove_tags text[],
                                         p_decided_by text, p_note text DEFAULT NULL)
  RETURNS jsonb
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v_id uuid; v_changes jsonb; v_note text; v_tags text[]; v_new text[]; v_fields integer;
  n_places integer := 0; n_fields integer := 0; n_tags integer := 0; n_skipped integer := 0; v_changed boolean;
  k text;
BEGIN
  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN RAISE EXCEPTION 'no places were chosen'; END IF;
  IF cardinality(p_ids) > 5000 THEN RAISE EXCEPTION 'at most 5,000 places can be edited at once'; END IF;
  v_changes := COALESCE(p_changes, '{}');
  FOR k IN SELECT jsonb_object_keys(v_changes) LOOP
    IF k NOT IN ('main_category', 'status', 'needs_review') THEN
      RAISE EXCEPTION 'field % cannot be changed in a bulk edit', k;
    END IF;
  END LOOP;
  IF v_changes = '{}' AND COALESCE(cardinality(p_add_tags), 0) = 0 AND COALESCE(cardinality(p_remove_tags), 0) = 0 THEN
    RAISE EXCEPTION 'nothing to change';
  END IF;
  v_note := 'Bulk edit of ' || cardinality(p_ids) || CASE WHEN cardinality(p_ids) = 1 THEN ' place' ELSE ' places' END
            || COALESCE(': ' || NULLIF(trim(p_note), ''), '');

  FOR v_id IN SELECT DISTINCT unnest(p_ids) LOOP
    IF NOT EXISTS (SELECT 1 FROM entities WHERE id = v_id AND status <> 'merged') THEN
      n_skipped := n_skipped + 1;
      CONTINUE;
    END IF;
    v_changed := false;
    IF v_changes <> '{}' THEN
      v_fields := admin_update_place(v_id, v_changes, p_decided_by, v_note);
      n_fields := n_fields + v_fields;
      v_changed := v_fields > 0;
    END IF;
    IF COALESCE(cardinality(p_add_tags), 0) > 0 OR COALESCE(cardinality(p_remove_tags), 0) > 0 THEN
      SELECT COALESCE(array_agg(c.path::text), '{}') INTO v_tags
      FROM entity_categories ec JOIN categories c ON c.id = ec.category_id WHERE ec.entity_id = v_id;
      SELECT COALESCE(array_agg(DISTINCT t), '{}') INTO v_new
      FROM unnest(v_tags || COALESCE(p_add_tags, '{}')) t
      WHERE NOT t = ANY (COALESCE(p_remove_tags, '{}'));
      IF admin_set_place_tags(v_id, v_new, p_decided_by) THEN
        n_tags := n_tags + 1;
        v_changed := true;
      END IF;
    END IF;
    IF v_changed THEN n_places := n_places + 1; END IF;
  END LOOP;
  RETURN jsonb_build_object('places_changed', n_places, 'fields_changed', n_fields, 'places_with_tag_changes', n_tags,
                            'skipped_merged', n_skipped);
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_bulk_update(uuid[], jsonb, text[], text[], text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bulk_update(uuid[], jsonb, text[], text[], text, text) TO service_role;
