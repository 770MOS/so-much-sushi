-- Scenario checks for several sources: field trust, enrichment, proposals from a
-- higher-ranked source, verify-only sources, and state-scoped loads.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
update sources set license_class = 'permissive' where code = 'overture_places';
insert into sources (code, name, role, license, license_class, cadence, field_trust)
values ('test_registry', 'Test business registry', 'registry', 'Public record', 'verify_only', 'monthly', '{"status": 50}');

create function pg_temp.rec(id text, name text, phone text, website text, lon float8, lat float8,
                            status text default 'open', city text default 'Arlington', state text default 'VA') returns jsonb
  language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'x', 'license', 'CC0-1.0',
    'name', name, 'address', '1 Main St', 'city', city, 'state', state, 'postal_code', '22201', 'phone', phone,
    'website', website, 'lon', lon, 'lat', lat, 'source_category', 'restaurant', 'category_slug', 'restaurants',
    'payload', jsonb_build_object('operating_status', status, 'category_mapped', true)) $$;
create function pg_temp.load(src text, scope text, records jsonb) returns jsonb language plpgsql as $$
declare v bigint;
begin
  insert into source_runs (source_id, scope, status) select id, scope, 'running' from sources where code = src returning id into v;
  perform ingest_source_records(v, records);
  update source_runs set status = 'succeeded', finished_at = now() where id = v;
  return reconcile_run(v, 'test');
end $$;

-- Overture: three places in Virginia, one in Maryland. B has no website.
select pg_temp.load('overture_places', 'state:VA', jsonb_build_array(
  pg_temp.rec('oA','Burger Barn','7035550001','https://burgerbarn.example',-77.10,38.88),
  pg_temp.rec('oB','Taco Town','7035550002',null,-77.11,38.88),
  pg_temp.rec('oC','Noodle Nook','7035550003',null,-77.12,38.88))) as o1 \gset
select pg_temp.load('overture_places', 'state:MD', jsonb_build_array(
  pg_temp.rec('oM','Crab Shack','3015550009',null,-77.00,39.00, 'open', 'Bethesda', 'MD'))) as om \gset
select admin_update_place((select id from entities where name = 'Noodle Nook'), '{"phone":"7035559000"}', 'me') \gset

-- AllThePlaces: same Taco Town (same phone) with a website; Burger Barn with a different
-- website (ATP ranks higher for websites); Noodle Nook with a different phone (hand-edited);
-- and a brand-new place.
select pg_temp.load('alltheplaces', 'state:VA', jsonb_build_array(
  pg_temp.rec('aB','Taco Town','7035550002','https://tacotown.example/arlington',-77.1101,38.88),
  pg_temp.rec('aA','Burger Barn','7035550001','https://order.burgerbarnfranchise.example/arlington',-77.1001,38.88),
  pg_temp.rec('aC','Noodle Nook','7035550003',null,-77.1201,38.88),
  pg_temp.rec('aN','Pizza Planet','7035550004','https://pizzaplanet.example',-77.13,38.88))) as a1 \gset
insert into r select 'second source attaches to existing places', (:'a1'::jsonb->>'attached_to_existing_places')::int = 2;
insert into r select 'empty website filled from the second source',
  (select website from entities where name = 'Taco Town') = 'https://tacotown.example/arlington'
  and (select p.source_id from entity_field_provenance p join entities e on e.id = p.entity_id
       where e.name = 'Taco Town' and p.field = 'website') = (select id from sources where code = 'alltheplaces');
insert into r select 'higher-ranked disagreeing source proposes, does not switch',
  (select website from entities where name = 'Burger Barn') = 'https://burgerbarn.example'
  and exists (select 1 from admin_pending_source_changes() where name = 'Burger Barn' and field = 'website');
-- Noodle Nook's phone was edited by hand, so ATP's record conflicts on phone: it is not
-- attached, becomes its own place, and the pair is proposed as a possible duplicate.
insert into r select 'hand edit untouched',
  exists (select 1 from entities where name = 'Noodle Nook' and phone = '7035559000');
insert into r select 'conflicting record proposed as a duplicate, not attached',
  (select entity_id from source_records where source_record_id = 'aC') <> (select id from entities where name = 'Noodle Nook' and phone = '7035559000')
  and exists (select 1 from admin_pending_merges() where a_name = 'Noodle Nook');
insert into r select 'new place created from the second source', exists (select 1 from entities where name = 'Pizza Planet');

-- A verify-only registry: marks Taco Town closed, lists an unknown place.
select pg_temp.load('test_registry', 'state:VA', jsonb_build_array(
  pg_temp.rec('rB','Taco Town','7035550002',null,-77.11,38.88),
  pg_temp.rec('rX','Mystery Diner','7035550099',null,-77.20,38.90))) as v1 \gset
select pg_temp.load('test_registry', 'state:VA', jsonb_build_array(
  pg_temp.rec('rB','Taco Town','7035550002',null,-77.11,38.88,'permanently_closed'),
  pg_temp.rec('rX','Mystery Diner','7035550099',null,-77.20,38.90))) as v2 \gset
insert into r select 'verify-only source never creates places', not exists (select 1 from entities where name = 'Mystery Diner');
insert into r select 'verify-only source never supplies values',
  not exists (select 1 from entity_field_provenance p join sources s on s.id = p.source_id where s.code = 'test_registry');
insert into r select 'verify-only source can propose a closure',
  exists (select 1 from admin_pending_source_changes() where name = 'Taco Town' and event_type = 'closure_signal');

-- State scopes: two Virginia loads without Burger Barn's Overture record. ATP still lists it
-- recently, so it is not missing. Maryland's place is outside the Virginia scope.
select pg_temp.load('overture_places', 'state:VA', jsonb_build_array(
  pg_temp.rec('oB','Taco Town','7035550002',null,-77.11,38.88),
  pg_temp.rec('oC','Noodle Nook','7035550003',null,-77.12,38.88))) \gset
select pg_temp.load('overture_places', 'state:VA', jsonb_build_array(
  pg_temp.rec('oB','Taco Town','7035550002',null,-77.11,38.88),
  pg_temp.rec('oC','Noodle Nook','7035550003',null,-77.12,38.88))) as o3 \gset
insert into r select 'listed by another recent source, so not missing',
  not exists (select 1 from admin_pending_source_changes() where name = 'Burger Barn' and event_type = 'absent');
insert into r select 'other states are never counted as missing',
  not exists (select 1 from admin_pending_source_changes() where name = 'Crab Shack');
-- Once ATP's sighting is old, the place does count as missing.
update source_runs set finished_at = now() - interval '60 days', started_at = now() - interval '60 days'
where source_id = (select id from sources where code = 'alltheplaces');
select pg_temp.load('overture_places', 'state:VA', jsonb_build_array(
  pg_temp.rec('oB','Taco Town','7035550002',null,-77.11,38.88),
  pg_temp.rec('oC','Noodle Nook','7035550003',null,-77.12,38.88))) \gset
insert into r select 'missing from every source recently, so proposed',
  exists (select 1 from admin_pending_source_changes() where name = 'Burger Barn' and event_type = 'absent');

-- Accepting the higher-ranked website switches the field to that source.
select decide_source_changes(array(select event_id from admin_pending_source_changes() where name = 'Burger Barn' and field = 'website'), true, 'me') \gset
insert into r select 'accepted proposal switches the value and its source',
  (select website from entities where name = 'Burger Barn') = 'https://order.burgerbarnfranchise.example/arlington'
  and (select p.source_id from entity_field_provenance p join entities e on e.id = p.entity_id
       where e.name = 'Burger Barn' and p.field = 'website') = (select id from sources where code = 'alltheplaces');
do $$ begin insert into source_runs (source_id, scope, status) select id, 'county:x', 'succeeded' from sources where code = 'alltheplaces';
  perform reconcile_run((select max(id) from source_runs), 't'); insert into r values ('unknown scope refused', false);
exception when others then insert into r values ('unknown scope refused', true); end $$;
insert into r select 'licence audit stays clean', (select count(*) from provenance_license_audit) = 0;
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
