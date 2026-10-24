-- Every version of every source record is kept; unchanged loads add nothing; nothing is edited or deleted.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
update sources set license_class = 'permissive' where code = 'overture_places';
create function pg_temp.rec(id text, name text, phone text) returns jsonb
  language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'x', 'license', 'CDLA-Permissive-2.0',
    'name', name, 'address', '1 Main St', 'city', 'Arlington', 'state', 'VA', 'postal_code', '22201', 'phone', phone,
    'website', null, 'lon', case id when 'x' then -77.10 else -77.20 end, 'lat', 38.88, 'source_category', 'cafe',
    'category_slug', 'coffee', 'payload', jsonb_build_object('operating_status', 'open', 'category_mapped', true, 'raw', id || name)) $$;
create function pg_temp.load(records jsonb) returns bigint language plpgsql as $$
declare v bigint;
begin
  insert into source_runs (source_id, scope, status) select id, 'state:VA', 'running' from sources where code = 'overture_places' returning id into v;
  perform ingest_source_records(v, records);
  update source_runs set status = 'succeeded', finished_at = now() where id = v;
  perform reconcile_run(v, 'test');
  return v;
end $$;
create function pg_temp.n() returns bigint language sql as $$ select count(*) from source_record_versions $$;
create function pg_temp.vx() returns setof source_record_versions language sql as $$
  select v.* from source_record_versions v join source_records s on s.id = v.source_record_pk
  where s.source_record_id = 'x' order by v.version $$;

select pg_temp.load(jsonb_build_array(pg_temp.rec('x','Joe''s Pizza','7035550101'), pg_temp.rec('y','Bean Counter','7035550202'))) as run1 \gset
insert into r select 'first load: one version per record', pg_temp.n() = 2;
insert into r select 'first version keeps the original record', (select payload->>'raw' from pg_temp.vx() where version = 1) = 'xJoe''s Pizza';

select pg_temp.load(jsonb_build_array(pg_temp.rec('x','Joe''s Pizza','7035550101'), pg_temp.rec('y','Bean Counter','7035550202'))) as run2 \gset
insert into r select 'unchanged load adds nothing', pg_temp.n() = 2;

select pg_temp.load(jsonb_build_array(pg_temp.rec('x','Joe''s Pizza & Pasta','7035550101'), pg_temp.rec('y','Bean Counter','7035550202'))) as run3 \gset
insert into r select 'a rename adds exactly one version', pg_temp.n() = 3;
insert into r select 'old version closed by the load that replaced it',
  (select superseded_run from pg_temp.vx() where version = 1) = :run3
  and (select superseded_run is null and from_run = :run3 from pg_temp.vx() where version = 2);

select pg_temp.load(jsonb_build_array(pg_temp.rec('x','Joe''s Pizza & Pasta','7035550199'))) as run4 \gset
insert into r select 'a phone change adds a version; every name is kept',
  (select array_agg(name order by version) from pg_temp.vx()) = array['Joe''s Pizza', 'Joe''s Pizza & Pasta', 'Joe''s Pizza & Pasta']
  and (select phone from pg_temp.vx() where version = 3) = '7035550199';
insert into r select 'exactly one current version per record',
  not exists (select source_record_pk from source_record_versions where superseded_run is null group by 1 having count(*) > 1);

-- The same records sent twice within one load add nothing the second time.
do $$ declare v bigint; begin
  insert into source_runs (source_id, scope, status) select id, 'state:VA', 'running' from sources where code = 'overture_places' returning id into v;
  perform ingest_source_records(v, jsonb_build_array(pg_temp.rec('y','Bean Counter Cafe','7035550202')));
  perform ingest_source_records(v, jsonb_build_array(pg_temp.rec('y','Bean Counter Cafe','7035550202')));
end $$;
insert into r select 'same record twice in one load: one new version', pg_temp.n() = 5;

do $$ begin
  begin update source_record_versions set name = 'Changed' where version = 1; insert into r values ('old version cannot be edited', false);
  exception when others then insert into r values ('old version cannot be edited', true); end;
  begin update source_record_versions set name = 'Changed' where superseded_run is null; insert into r values ('current version cannot be edited', false);
  exception when others then insert into r values ('current version cannot be edited', true); end;
  begin delete from source_record_versions; insert into r values ('versions cannot be deleted', false);
  exception when others then insert into r values ('versions cannot be deleted', true); end;
end $$;

insert into r select 'place history shows every source version and the ledger',
  (select count(*) from place_history((select entity_id from source_records where source_record_id = 'x')) where kind = 'source version') = 3
  and exists (select 1 from place_history((select entity_id from source_records where source_record_id = 'x')) where kind <> 'source version');
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
