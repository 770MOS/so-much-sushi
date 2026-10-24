-- Full history of what each source said (agreed 2026-10-24).
--
-- source_record_versions keeps every version of every source record: a new row only
-- when a tracked value changes (name, address, town, state, ZIP, phone, website,
-- location, category, opening status), with the source's original record as it
-- arrived. Unchanged loads add nothing. Rows are never edited or deleted; the only
-- change allowed is closing the current version when a newer one replaces it.
--
-- place_history(entity) gives one timeline per place: every ledger entry (automatic
-- changes, proposals, decisions, merges, hand edits) for the place and anything merged
-- into it, plus every version of every source record attached to it.
SET search_path = public, extensions;

CREATE TABLE public.source_record_versions (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_record_pk bigint NOT NULL REFERENCES public.source_records(id) ON DELETE RESTRICT,
  source_id        smallint NOT NULL REFERENCES public.sources(id),
  version          integer NOT NULL CHECK (version >= 1),
  name             text,
  address          text,
  city             text,
  state            text,
  postal_code      text,
  phone            text,
  website          text,
  location         geography(Point, 4326),
  category_id      uuid REFERENCES public.categories(id),
  source_category  text,
  operating_status text,
  license          text,
  payload          jsonb,             -- the source's record as it arrived; empty for backfilled older versions
  from_run         bigint REFERENCES public.source_runs(id),
  superseded_run   bigint REFERENCES public.source_runs(id),   -- the load that replaced it; empty = current
  recorded_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_record_pk, version)
);
COMMENT ON TABLE public.source_record_versions IS
  'Every version of every source record. Append-only: a row changes only once, when a newer version closes it.';
CREATE UNIQUE INDEX source_record_versions_current ON public.source_record_versions (source_record_pk)
  WHERE superseded_run IS NULL;
CREATE INDEX source_record_versions_name ON public.source_record_versions USING gin (name gin_trgm_ops);

ALTER TABLE public.source_record_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.source_record_versions FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.source_record_versions TO service_role;

-- Append-only, enforced for everyone including the service role.
CREATE FUNCTION public.source_record_versions_guard()
  RETURNS trigger
  LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'source record versions are never deleted';
  END IF;
  IF OLD.superseded_run IS NOT NULL OR NEW.superseded_run IS NULL
     OR (to_jsonb(NEW) - 'superseded_run') IS DISTINCT FROM (to_jsonb(OLD) - 'superseded_run') THEN
    RAISE EXCEPTION 'source record versions are never edited (only the current version can be closed)';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER source_record_versions_append_only BEFORE UPDATE OR DELETE ON public.source_record_versions
  FOR EACH ROW EXECUTE FUNCTION public.source_record_versions_guard();

-- Adds a version for each given record whose tracked values differ from its current
-- version (or that has none yet), closing the old one.
CREATE FUNCTION public.record_versions(p_ids bigint[], p_run_id bigint)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_close bigint[]; v_new bigint[];
BEGIN
  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN RETURN 0; END IF;
  SELECT array_agg(v.id) FILTER (WHERE v.id IS NOT NULL), array_agg(sr.id)
  INTO v_close, v_new
  FROM source_records sr
  LEFT JOIN source_record_versions v ON v.source_record_pk = sr.id AND v.superseded_run IS NULL
  WHERE sr.id = ANY(p_ids)
    AND (v.id IS NULL
         OR source_record_values(v.name, v.address, v.city, v.state, v.postal_code, v.phone, v.website,
                                 v.location, v.category_id, jsonb_build_object('operating_status', v.operating_status))
            IS DISTINCT FROM
            source_record_values(sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website,
                                 sr.location, sr.category_id, sr.payload));
  IF v_new IS NULL THEN RETURN 0; END IF;

  UPDATE source_record_versions SET superseded_run = p_run_id WHERE id = ANY(v_close);
  INSERT INTO source_record_versions (source_record_pk, source_id, version, name, address, city, state, postal_code,
                                      phone, website, location, category_id, source_category, operating_status,
                                      license, payload, from_run)
  SELECT sr.id, sr.source_id,
         coalesce((SELECT max(version) FROM source_record_versions x WHERE x.source_record_pk = sr.id), 0) + 1,
         sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website, sr.location, sr.category_id,
         sr.source_category, sr.payload->>'operating_status', sr.license, sr.payload, p_run_id
  FROM source_records sr WHERE sr.id = ANY(v_new);
  RETURN cardinality(v_new);
END $$;
REVOKE EXECUTE ON FUNCTION public.record_versions(bigint[], bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_versions(bigint[], bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.ingest_source_records(p_run_id bigint, p_records jsonb) RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_source smallint; v_count integer; v_ids bigint[];
BEGIN
  SELECT source_id INTO v_source FROM source_runs WHERE id = p_run_id AND status = 'running';
  IF v_source IS NULL THEN RAISE EXCEPTION 'run % does not exist or is not running', p_run_id; END IF;

  WITH up AS (
  INSERT INTO source_records (source_id, source_record_id, upstream_dataset, license, name, address, city, state,
                              postal_code, phone, website, location, source_category, category_id,
                              source_confidence, payload, first_seen_run, last_seen_run)
  SELECT v_source, r->>'source_record_id', r->>'upstream_dataset', r->>'license', blank_to_null(r->>'name'),
         blank_to_null(r->>'address'), blank_to_null(r->>'city'), blank_to_null(r->>'state'),
         blank_to_null(r->>'postal_code'), blank_to_null(r->>'phone'), blank_to_null(r->>'website'),
         CASE WHEN r->>'lon' IS NOT NULL AND r->>'lat' IS NOT NULL
              THEN ST_SetSRID(ST_MakePoint((r->>'lon')::float8, (r->>'lat')::float8), 4326)::geography END,
         r->>'source_category',
         (SELECT c.id FROM categories c WHERE c.slug = r->>'category_slug'),
         (r->>'source_confidence')::numeric, COALESCE(r->'payload', '{}'::jsonb), p_run_id, p_run_id
  FROM jsonb_array_elements(p_records) r
  ON CONFLICT (source_id, source_record_id) DO UPDATE SET
    upstream_dataset = EXCLUDED.upstream_dataset, license = EXCLUDED.license, name = EXCLUDED.name,
    address = EXCLUDED.address, city = EXCLUDED.city, state = EXCLUDED.state, postal_code = EXCLUDED.postal_code,
    phone = EXCLUDED.phone, website = EXCLUDED.website, location = EXCLUDED.location,
    source_category = EXCLUDED.source_category, category_id = EXCLUDED.category_id,
    source_confidence = EXCLUDED.source_confidence, payload = EXCLUDED.payload,
    last_seen_run = EXCLUDED.last_seen_run,
    prev_values = CASE
      WHEN source_record_values(source_records.name, source_records.address, source_records.city, source_records.state,
             source_records.postal_code, source_records.phone, source_records.website, source_records.location,
             source_records.category_id, source_records.payload)
           IS DISTINCT FROM
           source_record_values(EXCLUDED.name, EXCLUDED.address, EXCLUDED.city, EXCLUDED.state, EXCLUDED.postal_code,
             EXCLUDED.phone, EXCLUDED.website, EXCLUDED.location, EXCLUDED.category_id, EXCLUDED.payload)
      THEN source_record_values(source_records.name, source_records.address, source_records.city, source_records.state,
             source_records.postal_code, source_records.phone, source_records.website, source_records.location,
             source_records.category_id, source_records.payload)
      ELSE source_records.prev_values END,
    changed_run = CASE
      WHEN source_record_values(source_records.name, source_records.address, source_records.city, source_records.state,
             source_records.postal_code, source_records.phone, source_records.website, source_records.location,
             source_records.category_id, source_records.payload)
           IS DISTINCT FROM
           source_record_values(EXCLUDED.name, EXCLUDED.address, EXCLUDED.city, EXCLUDED.state, EXCLUDED.postal_code,
             EXCLUDED.phone, EXCLUDED.website, EXCLUDED.location, EXCLUDED.category_id, EXCLUDED.payload)
      THEN p_run_id ELSE source_records.changed_run END
  RETURNING id)
  SELECT array_agg(id) INTO v_ids FROM up;
  v_count := coalesce(cardinality(v_ids), 0);

  PERFORM record_versions(v_ids, p_run_id);
  RETURN v_count;
END $$;

-- Backfill: the earlier version we kept for changed records, then the current values.
INSERT INTO public.source_record_versions (source_record_pk, source_id, version, name, address, city, state,
    postal_code, phone, website, location, category_id, operating_status, license, from_run, superseded_run, recorded_at)
SELECT sr.id, sr.source_id, 1, p->>'name', p->>'address', p->>'city', p->>'state', p->>'postal_code',
       p->>'phone', p->>'website',
       CASE WHEN p->>'lat' IS NOT NULL THEN ST_SetSRID(ST_MakePoint((p->>'lng')::float8, (p->>'lat')::float8), 4326)::geography END,
       (p->>'category_id')::uuid, p->>'operating_status', sr.license, sr.first_seen_run, sr.changed_run,
       coalesce(fr.finished_at, fr.started_at, now())
FROM public.source_records sr
CROSS JOIN LATERAL (SELECT sr.prev_values AS p) x
LEFT JOIN public.source_runs fr ON fr.id = sr.first_seen_run
WHERE sr.prev_values IS NOT NULL AND sr.changed_run IS NOT NULL;

INSERT INTO public.source_record_versions (source_record_pk, source_id, version, name, address, city, state,
    postal_code, phone, website, location, category_id, source_category, operating_status, license, payload,
    from_run, recorded_at)
SELECT sr.id, sr.source_id, CASE WHEN sr.prev_values IS NOT NULL AND sr.changed_run IS NOT NULL THEN 2 ELSE 1 END,
       sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website, sr.location, sr.category_id,
       sr.source_category, sr.payload->>'operating_status', sr.license, sr.payload,
       coalesce(sr.changed_run, sr.first_seen_run), coalesce(r.finished_at, r.started_at, now())
FROM public.source_records sr
LEFT JOIN public.source_runs r ON r.id = coalesce(sr.changed_run, sr.first_seen_run);

-- One timeline per place, newest first.
CREATE FUNCTION public.place_history(p_entity uuid)
  RETURNS TABLE(at timestamptz, kind text, field text, old_value jsonb, new_value jsonb, status text,
                source text, by_whom text, detail jsonb)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  WITH RECURSIVE fam AS (
    SELECT p_entity AS id
    UNION SELECT e.id FROM entities e JOIN fam ON e.merged_into = fam.id
  )
  SELECT coalesce(c.applied_at, c.decided_at, c.created_at), c.event_type, c.field, c.old_value, c.new_value,
         c.status, s.name, c.decided_by,
         c.evidence || CASE WHEN c.entity_id <> p_entity THEN jsonb_build_object('on_merged_place', c.entity_id) ELSE '{}' END
  FROM change_events c JOIN fam ON fam.id = c.entity_id
  LEFT JOIN sources s ON s.id = c.source_id
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
REVOKE EXECUTE ON FUNCTION public.place_history(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_history(uuid) TO service_role;
