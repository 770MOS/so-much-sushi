-- Adds needs_review to entities: flags rows where automated category
-- mapping was a low-confidence guess (used by scripts/bulk-import-overpass.mjs
-- when an OSM place has no recognized cuisine tag and falls back to the
-- top-level "restaurants" category), so they're easy to filter to first in
-- NocoDB for a human to actually categorize.
--
-- No new grants needed: service_role already has GRANT ALL on entities (see
-- supabase/grants_reference.sql), and Postgres privileges are table-level,
-- not column-level, so an added column is automatically covered by the
-- table's existing grants. NocoDB also connects as the `postgres` role via
-- the session pooler, not through anon/authenticated/service_role, so it
-- already sees every column regardless of REST API grants.
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

ALTER TABLE entities ADD COLUMN IF NOT EXISTS needs_review boolean NOT NULL DEFAULT false;

NOTIFY pgrst, 'reload schema';
