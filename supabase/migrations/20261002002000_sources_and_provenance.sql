-- Sources as data, run records, the current record from each source, and value-level provenance.
-- None of these tables is exposed to the app: row-level security is on with no policies,
-- and only the service role (ingest scripts) is granted access.

-- 1. Source register. Doubles as the licence decision log.
CREATE TABLE public.sources (
  id                 smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code               text NOT NULL UNIQUE,
  name               text NOT NULL,
  role               text NOT NULL CHECK (role IN ('base', 'registry', 'first_party', 'user', 'internal')),
  license            text NOT NULL,
  license_class      text NOT NULL CHECK (license_class IN ('own', 'permissive', 'attribution', 'verify_only', 'share_alike')),
  license_url        text,
  terms_url          text,
  attribution        text,
  license_checked_on date,
  license_notes      text,
  adapter            text,
  cadence            text,
  field_trust        jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active          boolean NOT NULL DEFAULT true,
  retired_at         timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now()
);
COMMENT ON COLUMN public.sources.license_class IS
  'own/permissive/attribution: values may be copied into entities. verify_only: may confirm or flag, never supplies a stored value. share_alike: must not be ingested.';

-- 2. One row per pull of a source (the run manifest).
CREATE TABLE public.source_runs (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_id     smallint NOT NULL REFERENCES public.sources(id),
  release       text,
  scope         text NOT NULL,
  license       text,
  status        text NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'succeeded', 'failed')),
  record_count  integer,
  checksum      text,
  artifact_uri  text,
  stats         jsonb NOT NULL DEFAULT '{}'::jsonb,
  error         text,
  started_at    timestamptz NOT NULL DEFAULT now(),
  finished_at   timestamptz
);
COMMENT ON COLUMN public.source_runs.license IS 'Licence of this release as verified at download time.';
COMMENT ON COLUMN public.source_runs.artifact_uri IS 'Where the full snapshot (Parquet) is archived. Snapshot history is not kept in Postgres.';
CREATE INDEX source_runs_source_idx ON public.source_runs (source_id, started_at DESC);

-- 3. The current record from each source: one row per (source, source's own id), updated in
--    place on each run. The link to our entity lives here; our entity id is never a source's id.
CREATE TABLE public.source_records (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_id        smallint NOT NULL REFERENCES public.sources(id),
  source_record_id text NOT NULL,
  upstream_dataset text,
  license          text NOT NULL,
  name             text,
  address          text,
  city             text,
  state            text,
  postal_code      text,
  phone            text,
  website          text,
  location         extensions.geography(Point, 4326),
  source_category  text,
  category_id      uuid REFERENCES public.categories(id),
  source_confidence numeric,
  payload          jsonb NOT NULL,
  first_seen_run   bigint NOT NULL REFERENCES public.source_runs(id),
  last_seen_run    bigint NOT NULL REFERENCES public.source_runs(id),
  entity_id        uuid REFERENCES public.entities(id) ON DELETE RESTRICT,
  match_status     text NOT NULL DEFAULT 'unmatched' CHECK (match_status IN ('unmatched', 'auto', 'confirmed', 'needs_review', 'rejected')),
  match_score      numeric,
  match_method     text,
  matched_at       timestamptz,
  UNIQUE (source_id, source_record_id),
  CHECK ((entity_id IS NOT NULL) = (match_status IN ('auto', 'confirmed')))
);
COMMENT ON COLUMN public.source_records.upstream_dataset IS
  'The dataset inside the source this record came from (e.g. Overture lists meta, Microsoft, Foursquare). Two records with the same upstream dataset do not corroborate each other.';
CREATE INDEX source_records_entity_idx   ON public.source_records (entity_id) WHERE entity_id IS NOT NULL;
CREATE INDEX source_records_location_idx ON public.source_records USING gist (location);
CREATE INDEX source_records_unmatched_idx ON public.source_records (source_id) WHERE match_status IN ('unmatched', 'needs_review');

-- 4. Which source each stored value on an entity came from, and under what licence.
CREATE TABLE public.entity_field_provenance (
  entity_id        uuid NOT NULL REFERENCES public.entities(id) ON DELETE CASCADE,
  field            text NOT NULL CHECK (field IN ('name', 'address', 'location', 'phone', 'website', 'hours', 'categories', 'status')),
  source_id        smallint NOT NULL REFERENCES public.sources(id),
  source_record_pk bigint REFERENCES public.source_records(id) ON DELETE SET NULL,
  license          text NOT NULL,
  method           text NOT NULL CHECK (method IN ('survivorship', 'manual', 'user_report')),
  set_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (entity_id, field)
);
CREATE INDEX entity_field_provenance_source_idx ON public.entity_field_provenance (source_id);

-- The licensing rule, enforced: a value can only be attributed to a source whose
-- licence class allows copying values.
CREATE FUNCTION public.check_provenance_source() RETURNS trigger
  LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE v_class text; v_code text;
BEGIN
  SELECT s.license_class, s.code INTO v_class, v_code FROM public.sources s WHERE s.id = NEW.source_id;
  IF v_class NOT IN ('own', 'permissive', 'attribution') THEN
    RAISE EXCEPTION 'source % has license_class %, so it cannot supply stored values', v_code, v_class
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.check_provenance_source() FROM PUBLIC;
CREATE TRIGGER entity_field_provenance_check_source BEFORE INSERT OR UPDATE ON public.entity_field_provenance
  FOR EACH ROW EXECUTE FUNCTION public.check_provenance_source();

-- 5. Convenience views (run with the caller's permissions).
CREATE VIEW public.entity_sources WITH (security_invoker = true) AS
  SELECT r.entity_id, s.code AS source, r.source_record_id, r.upstream_dataset, r.license,
         r.match_status, r.match_score, r.match_method, r.matched_at, r.first_seen_run, r.last_seen_run
  FROM public.source_records r JOIN public.sources s ON s.id = r.source_id
  WHERE r.entity_id IS NOT NULL;

-- Values that currently depend on a source we may no longer copy from (e.g. after its
-- class is changed). Empty means the stored data is clean. This is the re-sourcing worklist.
CREATE VIEW public.provenance_license_audit WITH (security_invoker = true) AS
  SELECT p.entity_id, p.field, s.code AS source, s.license_class, p.license, p.set_at
  FROM public.entity_field_provenance p JOIN public.sources s ON s.id = p.source_id
  WHERE s.license_class NOT IN ('own', 'permissive', 'attribution');

-- 6. Access: explicit, since new tables get no default grants here.
ALTER TABLE public.sources                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.source_runs             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.source_records          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entity_field_provenance ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sources, public.source_runs, public.source_records, public.entity_field_provenance,
              public.entity_sources, public.provenance_license_audit FROM anon, authenticated;
GRANT ALL ON public.sources, public.source_runs, public.source_records, public.entity_field_provenance TO service_role;
GRANT SELECT ON public.entity_sources, public.provenance_license_audit TO service_role;

-- 7. The decided sources. license_checked_on stays empty until the licence text itself
--    has been read and recorded; registries are added per jurisdiction as verify_only.
INSERT INTO public.sources (code, name, role, license, license_class, license_url, attribution, cadence, license_notes) VALUES
  ('overture_places', 'Overture Maps Foundation: Places theme', 'base', 'CDLA-Permissive-2.0', 'permissive',
   'https://docs.overturemaps.org/attribution/', 'Overture Maps Foundation, overturemaps.org', 'monthly',
   'Places theme only; other Overture themes are ODbL and must not be ingested. Licence varies per record by upstream dataset (CDLA-Permissive-2.0, Apache-2.0 for Foursquare, CC0-1.0 for AllThePlaces): record it per record.'),
  ('fsq_os_places', 'Foursquare Open Source Places', 'base', 'Apache-2.0', 'permissive',
   'https://huggingface.co/datasets/foursquare/fsq-os-places', 'Copyright Foursquare Labs, Inc.', 'monthly',
   'Releases from October 2025 need a Places Portal account and token; review the portal terms before first use. Also appears inside Overture Places, so the two are not independent.'),
  ('venue_website', 'The venue''s own website', 'first_party', 'Facts published by the business, established by us', 'own',
   NULL, NULL, 'manual', 'Looked up one venue at a time; no crawling.'),
  ('manual_research', 'Our own research and curation', 'internal', 'Own work', 'own', NULL, NULL, 'manual', NULL),
  ('user_report', 'Corrections and reports from users', 'user', 'Licensed to us under the terms of service', 'own',
   NULL, NULL, 'continuous', 'Requires the contribution-licence clause in the terms before any tester submits data.');
