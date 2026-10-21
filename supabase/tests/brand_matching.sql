-- Scenario checks for chain locations named differently across sources.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
update sources set license_class = 'permissive' where code = 'overture_places';
create function pg_temp.rec(id text, name text, brand text, phone text, website text, lon float8, lat float8) returns jsonb
  language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'x', 'license', 'CC0-1.0',
    'name', name, 'address', '1 Main St', 'city', 'Arlington', 'state', 'VA', 'postal_code', '22201', 'phone', phone,
    'website', website, 'lon', lon, 'lat', lat, 'source_category', 'cafe', 'category_slug', 'coffee',
    'payload', jsonb_build_object('operating_status', 'open', 'category_mapped', true, 'brand', brand)) $$;
create function pg_temp.load(src text, records jsonb) returns jsonb language plpgsql as $$
declare v bigint;
begin
  insert into source_runs (source_id, scope, status) select id, 'state:VA', 'running' from sources where code = src returning id into v;
  perform ingest_source_records(v, records);
  update source_runs set status = 'succeeded', finished_at = now() where id = v;
  return reconcile_run(v, 'test');
end $$;

select pg_temp.load('overture_places', jsonb_build_array(
  pg_temp.rec('o1','Starbucks Coffee Company',null,'7035550001','https://www.starbucks.com',-77.10,38.88),
  pg_temp.rec('o2','Chipotle Mexican Grill',null,'7035550002',null,-77.11,38.88),
  pg_temp.rec('o3','Wendy''s Wonderful Snow Cones',null,'7035550003',null,-77.12,38.88),
  pg_temp.rec('o4','Five Guys Burgers and Fries',null,null,null,-77.13,38.88))) \gset

select pg_temp.load('alltheplaces', jsonb_build_array(
  pg_temp.rec('a1','Starbucks','Starbucks','7035550001','https://www.starbucks.com/store-locator/store/1',-77.1001,38.88),
  pg_temp.rec('a2','Chipotle','Chipotle','7035550002','https://locations.chipotle.com/va/arlington/1',-77.1101,38.88),
  pg_temp.rec('a3','Wendy''s','Wendy''s','7035559999','https://locations.wendys.com/1',-77.1201,38.88),
  pg_temp.rec('a4','Five Guys','Five Guys','7035554444','https://restaurants.fiveguys.com/1',-77.1301,38.88))) as s \gset

insert into r select 'chain matched despite a longer name (same phone)',
  (select entity_id from source_records where source_record_id = 'a1') = (select entity_id from source_records where source_record_id = 'o1');
insert into r select 'chain matched: Chipotle and Chipotle Mexican Grill',
  (select entity_id from source_records where source_record_id = 'a2') = (select entity_id from source_records where source_record_id = 'o2');
insert into r select 'website filled from the chain record',
  (select e.website from entities e join source_records s on s.entity_id = e.id where s.source_record_id = 'o2') like 'https://locations.chipotle.com/%';
insert into r select 'different business sharing a word is not matched (phone conflicts)',
  (select entity_id from source_records where source_record_id = 'a3') is distinct from (select entity_id from source_records where source_record_id = 'o3');
insert into r select 'no evidence: kept separate but proposed as a possible duplicate',
  (select entity_id from source_records where source_record_id = 'a4') is distinct from (select entity_id from source_records where source_record_id = 'o4')
  and exists (select 1 from admin_pending_merges() where a_name = 'Five Guys Burgers and Fries');
insert into r select 'names_match basics', names_match('Starbucks', 'Starbucks', 'Starbucks Coffee Company')
  and not names_match('Starbucks', null, 'Starbucks Coffee Company')
  and not names_match('Taco Town', 'Taco Town', 'Burger Barn');
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
