-- The place history names the other place in every merge and unmerge entry, including
-- merges made before merge entries recorded the name.
SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.place_history(p_entity uuid)
  RETURNS TABLE(at timestamptz, kind text, field text, old_value jsonb, new_value jsonb, status text,
                source text, by_whom text, detail jsonb)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  WITH RECURSIVE fam AS (
    SELECT p_entity AS id
    UNION SELECT e.id FROM entities e JOIN fam ON e.merged_into = fam.id
  )
  SELECT coalesce(c.applied_at, c.decided_at, c.created_at), c.event_type, c.field, c.old_value, c.new_value,
         c.status, s.name, c.decided_by,
         c.evidence
           || CASE WHEN c.entity_id <> p_entity THEN jsonb_build_object('on_merged_place', c.entity_id) ELSE '{}' END
           || CASE WHEN c.event_type IN ('merge', 'unmerge') AND NOT c.evidence ? 'duplicate_name' AND dn.name IS NOT NULL
                   THEN jsonb_build_object('duplicate_name', dn.name) ELSE '{}' END
  FROM change_events c JOIN fam ON fam.id = c.entity_id
  LEFT JOIN sources s ON s.id = c.source_id
  LEFT JOIN entities dn ON dn.id = CASE WHEN c.old_value ? 'duplicate' THEN (c.old_value->>'duplicate')::uuid END
  UNION ALL
  SELECT v.recorded_at, 'source version', NULL,
         NULL, jsonb_strip_nulls(jsonb_build_object('name', v.name, 'address', v.address, 'city', v.city,
           'state', v.state, 'postal_code', v.postal_code, 'phone', v.phone, 'website', v.website,
           'operating_status', v.operating_status, 'category', cat.name)),
         CASE WHEN v.superseded_run IS NULL THEN 'current' ELSE 'replaced' END, s.name, NULL,
         jsonb_build_object('source_record_id', sr.source_record_id, 'version', v.version,
                            'from_release', fr.release, 'replaced_in_release', rr.release)
  FROM source_records sr JOIN fam ON fam.id = sr.entity_id
  JOIN source_record_versions v ON v.source_record_pk = sr.id
  JOIN sources s ON s.id = v.source_id
  LEFT JOIN categories cat ON cat.id = v.category_id
  LEFT JOIN source_runs fr ON fr.id = v.from_run
  LEFT JOIN source_runs rr ON rr.id = v.superseded_run
  ORDER BY 1 DESC;
$$;
