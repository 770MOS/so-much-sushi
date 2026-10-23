-- Blank text is no value: stored as none, and filled from another source rather than proposed.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
update sources set license_class = 'permissive' where code = 'overture_places';
create function pg_temp.rec(id text, name text, state text, phone text, website text, lon float8, lat float8) returns jsonb
  language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'x', 'license', 'CC0-1.0',
    'name', name, 'address', '1 Main St', 'city', 'Arlington', 'state', state, 'postal_code', '22201', 'phone', phone,
    'website', website, 'lon', lon, 'lat', lat, 'source_category', 'cafe', 'category_slug', 'coffee',
    'payload', jsonb_build_object('operating_status', 'open', 'category_mapped', true, 'brand', name)) $$;
create function pg_temp.load(src text, records jsonb) returns jsonb language plpgsql as $$
declare v bigint;
begin
  insert into source_runs (source_id, scope, status) select id, 'state:VA', 'running' from sources where code = src returning id into v;
  perform ingest_source_records(v, records);
  update source_runs set status = 'succeeded', finished_at = now() where id = v;
  return reconcile_run(v, 'test');
end $$;

select pg_temp.load('overture_places', jsonb_build_array(
  pg_temp.rec('o1','Bean Counter','','  ','https://beancounter.example/arlington',-77.10,38.88))) \gset
insert into r select 'blank state and phone stored as none',
  (select state is null and phone is null from source_records where source_record_id = 'o1');
insert into r select 'place has no state or phone',
  (select e.state is null and e.phone is null from entities e join source_records s on s.entity_id = e.id where s.source_record_id = 'o1');

select pg_temp.load('alltheplaces', jsonb_build_array(
  pg_temp.rec('a1','Bean Counter','VA','7035550001','https://beancounter.example/arlington',-77.1001,38.88))) as s \gset
insert into r select 'second source joined the place',
  (select entity_id from source_records where source_record_id = 'a1') = (select entity_id from source_records where source_record_id = 'o1');
insert into r select 'state and phone filled, not proposed',
  (select e.state = 'VA' and e.phone = '7035550001' from entities e join source_records s on s.entity_id = e.id where s.source_record_id = 'o1')
  and not exists (select 1 from change_events where status = 'pending' and field in ('state', 'phone'));
insert into r select 'blank_to_null', blank_to_null('') is null and blank_to_null('   ') is null and blank_to_null('x') = 'x' and blank_to_null(null) is null;
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
