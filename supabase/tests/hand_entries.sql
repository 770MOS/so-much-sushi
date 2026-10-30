-- Places we are responsible for: added by hand, compared with sources, kept checked.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
create function pg_temp.rec(id text, name text, phone text, website text, city text, lon float8) returns jsonb language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'x', 'license', 'CC0-1.0', 'name', name, 'address', '1 Main St',
    'city', city, 'state', 'VA', 'postal_code', '22201', 'phone', phone, 'website', website, 'lon', lon, 'lat', 38.88,
    'source_category', 'cafe', 'category_slug', 'coffee', 'payload', jsonb_build_object('operating_status','open','category_mapped',true,'brand',name)) $$;
create function pg_temp.load(records jsonb) returns jsonb language plpgsql as $$ declare v bigint; begin
  insert into source_runs (source_id, scope, status) select id, 'state:VA', 'running' from sources where code = 'alltheplaces' returning id into v;
  perform ingest_source_records(v, records); update source_runs set status = 'succeeded', finished_at = now() where id = v;
  return reconcile_run(v, 'test'); end $$;

select admin_add_place('{"name":"Hand Cafe A","address":"1 Main St","city":"Arlington","state":"VA","phone":"7035550001","website":"https://hand-a.example","lat":38.88,"lng":-77.10,"main_category":"coffee"}', 'me') as a \gset
select admin_add_place('{"name":"Hand Cafe B","phone":"(703) 555-0002","website":"https://www.hand-b.example","lat":38.88,"lng":-77.11,"main_category":"coffee"}', 'me') as b \gset
insert into r select 'adding a place counts as checking it', (select last_verified is not null from entities where id = :'a');

select pg_temp.load(jsonb_build_array(
  pg_temp.rec('a', 'Hand Cafe A', '7035550001', 'https://other.example', 'North Arlington', -77.1001),
  pg_temp.rec('b', 'Hand Cafe B', '+1 703-555-0002', 'https://hand-b.example/locations/1', 'Arlington', -77.1101))) \gset
insert into r select 'first match: source joins the hand-added place', (select entity_id from source_records where source_record_id = 'a') = :'a';
insert into r select 'first match: disagreement with a hand value is proposed',
  exists (select 1 from change_events where entity_id = :'a' and status = 'pending' and field = 'website'
            and evidence->>'reason' = 'a source disagrees with a value entered by hand');
insert into r select 'hand value itself is kept', (select website from entities where id = :'a') = 'https://hand-a.example';
insert into r select 'town differences are not proposed', not exists (select 1 from change_events where entity_id = :'a' and status = 'pending' and field = 'city');
insert into r select 'formatting-only differences are not proposed', not exists (select 1 from change_events where entity_id = :'b' and status = 'pending');
insert into r select 'empty hand fields filled from the source', (select postal_code from entities where id = :'b') = '22201';

-- Filters
insert into r select 'filter: added by hand', (select count(*) from admin_search_places(p_origin => 'hand')) = 2
  and (select bool_and(added_by_hand) from admin_search_places(p_origin => 'hand'));
insert into entities (id, name, location, main_category_id, created_at)
select 'cccccccc-0000-0000-0000-000000000001', 'Lonely Diner', 'SRID=4326;POINT(-77.3 38.9)', id, now() - interval '1 year' from categories where path = 'restaurants';
insert into r select 'filter: no source has it', exists (select 1 from admin_search_places(p_origin => 'unconfirmed') where name = 'Lonely Diner')
  and not exists (select 1 from admin_search_places(p_origin => 'unconfirmed') where name like 'Hand Cafe%');
insert into r select 'filter: not checked in 6 months', (select array_agg(name) from admin_search_places(p_origin => 'stale')) = array['Lonely Diner'];

-- Checked, still correct
select admin_mark_checked(array['cccccccc-0000-0000-0000-000000000001']::uuid[], 'me', 'walked past') as n \gset
insert into r select 'marking checked clears it from the 6-month list', :n = 1 and not exists (select 1 from admin_search_places(p_origin => 'stale'));
insert into r select 'checking is in the ledger', exists (select 1 from change_events where entity_id = 'cccccccc-0000-0000-0000-000000000001'
  and field = 'last_checked' and evidence->>'note' = 'walked past');
update entities set last_verified = now() - interval '1 year' where id = 'cccccccc-0000-0000-0000-000000000001';
select admin_update_place('cccccccc-0000-0000-0000-000000000001', '{"phone": "7035550999"}', 'me') \gset
insert into r select 'a hand edit counts as checking', (select last_verified > now() - interval '1 minute' from entities where id = 'cccccccc-0000-0000-0000-000000000001');
insert into r select 'place page shows hand-added and last checked',
  (admin_get_place(:'a')->>'added_by_hand')::boolean and admin_get_place(:'a') ? 'last_checked';
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
