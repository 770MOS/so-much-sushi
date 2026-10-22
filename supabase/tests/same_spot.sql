-- Scenario checks for rule 2: the identical name within 25 m, nothing conflicting.
-- 0.0001 degrees of longitude is about 9 m here; 0.0005 is about 43 m.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
update sources set license_class = 'permissive' where code = 'overture_places';
create function pg_temp.rec(id text, name text, phone text, website text, lon float8, lat float8) returns jsonb
  language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'x', 'license', 'CC0-1.0',
    'name', name, 'address', '1 Main St', 'city', 'Arlington', 'state', 'VA', 'postal_code', '22201', 'phone', phone,
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
create function pg_temp.same(a text, b text) returns boolean language sql as $$
  select (select entity_id from source_records where source_record_id = a)
       = (select entity_id from source_records where source_record_id = b) $$;

select pg_temp.load('overture_places', jsonb_build_array(
  pg_temp.rec('o1','Subway','7035550001','https://www.subway.com',-77.10,38.88),
  pg_temp.rec('o2','Chick-fil-A',null,null,-77.11,38.88),
  pg_temp.rec('o3','Taco Bell','7035550003',null,-77.12,38.88),
  pg_temp.rec('o4','Five Guys',null,'https://www.fiveguys.com',-77.13,38.88),
  pg_temp.rec('o5','Dunkin',null,null,-77.14,38.88),
  pg_temp.rec('o6','Dunkin',null,null,-77.14005,38.88),
  pg_temp.rec('o7','Sweetgreen',null,null,-77.15,38.88),
  pg_temp.rec('o8','Panera Bread',null,null,-77.16,38.88))) \gset

select pg_temp.load('alltheplaces', jsonb_build_array(
  pg_temp.rec('a1','Subway',null,null,-77.1001,38.88),
  pg_temp.rec('a2','Chick-fil-A','7035550002',null,-77.1105,38.88),
  pg_temp.rec('a3','Taco Bell','7035559999',null,-77.1201,38.88),
  pg_temp.rec('a4','Five Guys',null,'https://www.fiveguysburgers.net/1',-77.1301,38.88),
  pg_temp.rec('a5','Dunkin','7035550005',null,-77.14002,38.88),
  pg_temp.rec('a7','Sweetgreen','7035550007',null,-77.1501,38.88),
  pg_temp.rec('a7b','Sweetgreen','7035550077',null,-77.14992,38.88),
  pg_temp.rec('a8','Panera Bread','7035550008',null,-77.1601,38.88))) as s \gset

insert into r select 'same name 9 m apart, phone on one side only: joined', pg_temp.same('a1','o1');
insert into r select 'joined record is labelled with the rule',
  (select match_method from source_records where source_record_id = 'a1') = 'auto: same name, same spot';
insert into r select 'existing phone kept', (select e.phone from entities e join source_records s on s.entity_id = e.id
  where s.source_record_id = 'o1') = '7035550001';
insert into r select 'same name 43 m apart: not joined, proposed instead',
  not pg_temp.same('a2','o2') and exists (select 1 from admin_pending_merges() where a_name = 'Chick-fil-A');
insert into r select 'same name, phones differ: not joined', not pg_temp.same('a3','o3');
insert into r select 'same name, website domains differ: not joined', not pg_temp.same('a4','o4');
insert into r select 'two places with that name nearby: not joined to either',
  not pg_temp.same('a5','o5') and not pg_temp.same('a5','o6');
insert into r select 'within one source, same name and no phone: still two places', not pg_temp.same('o5','o6');
insert into r select 'two records of one chain at one spot: only one joins',
  pg_temp.same('a7','o7') and not pg_temp.same('a7b','o7');

-- A later load: the place already has a record from this source, so a new one is a new location.
select pg_temp.load('alltheplaces', jsonb_build_array(
  pg_temp.rec('a8','Panera Bread','7035550008',null,-77.1601,38.88),
  pg_temp.rec('a8b','Panera Bread',null,null,-77.16005,38.88))) as s2 \gset
insert into r select 'first Panera joined', pg_temp.same('a8','o8');
insert into r select 'place already has a record from this source: not joined again', not pg_temp.same('a8b','o8');
insert into r select 'too-short names never match on name alone',
  not same_name_same_spot('BP', null, null, 'POINT(-77 38)'::geography, 'BP', null, null, 'POINT(-77 38)'::geography);
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
