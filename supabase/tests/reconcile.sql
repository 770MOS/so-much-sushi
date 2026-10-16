-- Scenario checks for reconcile_run: four loads of the same area, with a hand edit,
-- source updates, a closure, a place that goes missing, and new records.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
update sources set license_class = 'permissive' where code = 'overture_places';
create function pg_temp.rec(id text, name text, phone text, lon float8, lat float8, status text default 'open') returns jsonb
  language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'meta', 'license', 'CDLA-Permissive-2.0',
    'name', name, 'address', '1 Main St', 'city', 'Arlington', 'state', 'VA', 'postal_code', '22201', 'phone', phone,
    'website', null, 'lon', lon, 'lat', lat, 'source_category', 'restaurant', 'category_slug', 'restaurants',
    'source_confidence', 0.9, 'payload', jsonb_build_object('operating_status', status, 'category_mapped', true)) $$;
create function pg_temp.load(records jsonb) returns jsonb language plpgsql as $$
declare v bigint;
begin
  insert into source_runs (source_id, scope, status) select id, 'bbox:-78,38,-76,40', 'running' from sources where code = 'overture_places' returning id into v;
  perform ingest_source_records(v, records);
  update source_runs set status = 'succeeded' where id = v;
  return reconcile_run(v, 'test');
end $$;

-- Load 1: six records, one outside the load's area.
select pg_temp.load(jsonb_build_array(
  pg_temp.rec('A','Pizza Roma','7035550001',-77.10,38.88), pg_temp.rec('B','Thai Place','7035550002',-77.11,38.88),
  pg_temp.rec('C','Gone Cafe','7035550003',-77.12,38.88), pg_temp.rec('D','Hand Edited','7035550004',-77.13,38.88),
  pg_temp.rec('E','Mover','7035550005',-77.14,38.88), pg_temp.rec('O','Outside Area','7035550009',-80,38.88))) as s1 \gset
insert into r select 'load 1 creates a place per record', (:'s1'::jsonb->'build'->>'entities_created')::int = 6;
select admin_update_place((select id from entities where name = 'Hand Edited'), '{"name":"Hand Edited (fixed)"}', 'me') \gset

-- Load 2: A closes, B's phone changes, C and O missing, D renamed by the source, E moves 87 m,
-- F is a second record for A's place, G is a near-identical new place next to B.
select pg_temp.load(jsonb_build_array(
  pg_temp.rec('A','Pizza Roma','7035550001',-77.10,38.88,'permanently_closed'), pg_temp.rec('B','Thai Place','7035559999',-77.11,38.88),
  pg_temp.rec('D','Hand Edited Renamed','7035550004',-77.13,38.88), pg_temp.rec('E','Mover','7035550005',-77.141,38.88),
  pg_temp.rec('F','Pizza Roma','7035550001',-77.1002,38.88), pg_temp.rec('G','Thai Place','7035558888',-77.1103,38.88))) as s2 \gset
insert into r select 'phone and small move applied automatically', (:'s2'::jsonb->>'values_updated_automatically')::int = 2;
insert into r select 'phone now follows the source', exists (select 1 from entities where name = 'Thai Place' and phone = '7035559999');
insert into r select 'hand edit kept, source value proposed', (:'s2'::jsonb->>'value_changes_for_review')::int = 1
  and exists (select 1 from entities where name = 'Hand Edited (fixed)');
insert into r select 'closure proposed, not applied', (:'s2'::jsonb->>'status_changes_for_review')::int = 1
  and (select status from entities where name = 'Pizza Roma') = 'active';
insert into r select 'second record attached to the existing place', (:'s2'::jsonb->>'attached_to_existing_places')::int = 1
  and (select count(*) from entities where name = 'Pizza Roma') = 1;
insert into r select 'near-identical new place proposed as duplicate', (:'s2'::jsonb->>'possible_duplicates_of_existing')::int = 1;
insert into r select 'one miss is ignored', (:'s2'::jsonb->>'missing_for_review')::int = 0;

-- Load 3: same as load 2, so C has now missed two loads; O is outside the area and never counts.
select pg_temp.load(jsonb_build_array(
  pg_temp.rec('A','Pizza Roma','7035550001',-77.10,38.88,'permanently_closed'), pg_temp.rec('B','Thai Place','7035559999',-77.11,38.88),
  pg_temp.rec('D','Hand Edited Renamed','7035550004',-77.13,38.88), pg_temp.rec('E','Mover','7035550005',-77.141,38.88),
  pg_temp.rec('F','Pizza Roma','7035550001',-77.1002,38.88), pg_temp.rec('G','Thai Place','7035558888',-77.1103,38.88))) as s3 \gset
insert into r select 'missing twice is proposed, outside area is not', (:'s3'::jsonb->>'missing_for_review')::int = 1
  and exists (select 1 from admin_pending_source_changes() where event_type = 'absent' and name = 'Gone Cafe');

-- Decisions.
select decide_source_changes(array(select event_id from admin_pending_source_changes() where event_type in ('closure_signal','absent')), true, 'me') as accepted \gset
select decide_source_changes(array(select event_id from admin_pending_source_changes() where event_type = 'attribute_change'), false, 'me') as rejected \gset
insert into r select 'accepting closes the places', (select count(*) from entities where name in ('Pizza Roma','Gone Cafe') and status = 'permanently_closed') = 2;
insert into r select 'rejecting keeps the hand edit', exists (select 1 from entities where name = 'Hand Edited (fixed)');

-- Load 4: nothing changed, so nothing new happens.
select pg_temp.load(jsonb_build_array(
  pg_temp.rec('A','Pizza Roma','7035550001',-77.10,38.88,'permanently_closed'), pg_temp.rec('B','Thai Place','7035559999',-77.11,38.88),
  pg_temp.rec('D','Hand Edited Renamed','7035550004',-77.13,38.88), pg_temp.rec('E','Mover','7035550005',-77.141,38.88),
  pg_temp.rec('F','Pizza Roma','7035550001',-77.1002,38.88), pg_temp.rec('G','Thai Place','7035558888',-77.1103,38.88))) as s4 \gset
insert into r select 'an unchanged load proposes nothing', (select count(*) from admin_pending_source_changes()) = 0
  and (:'s4'::jsonb->>'values_updated_automatically')::int = 0;
insert into r select 'licence audit stays clean', (select count(*) from provenance_license_audit) = 0;
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
