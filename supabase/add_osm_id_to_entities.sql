-- Adds osm_id to entities: the numeric OpenStreetMap element id an entity
-- was matched to, backfilled by scripts/backfill-osm-id.mjs against a
-- fresh Overpass pull (same Arlington query as
-- scripts/bulk-import-overpass.mjs). Nullable - entities with no
-- confident OSM match keep it null indefinitely, not just until the next
-- run.
--
-- Caveat worth knowing: OSM element ids are only unique *within* an
-- element type (a node and a way can share the same numeric id) - this
-- column stores the id alone, no type. Fine in practice here since the
-- Overpass query only pulls nodes/ways tagged as restaurant/cafe/bar/pub
-- within one county, making a same-id collision between a node and a way
-- both matching this filter effectively theoretical - but worth
-- remembering if this ever needs to round-trip back to a specific OSM
-- element via the API (which requires knowing node vs way).
--
-- No new grants needed: service_role already has GRANT ALL on entities
-- (see supabase/grants_reference.sql), and column additions are
-- automatically covered by a table's existing grants.
--
-- Safe to re-run (idempotent).

ALTER TABLE entities ADD COLUMN IF NOT EXISTS osm_id bigint;

NOTIFY pgrst, 'reload schema';
