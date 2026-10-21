-- Checks for comparing values written differently, and for the website matching rule.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
insert into r values
 ('phone formats', values_equivalent('phone', '+17039797275', '+1 703-979-7275')),
 ('phone different', not values_equivalent('phone', '7039797275', '7039797276')),
 ('website same domain', values_equivalent('website', 'http://www.pizzahut.com/', 'https://locations.pizzahut.com/va/alexandria/1')),
 ('website different domain', not values_equivalent('website', 'https://burgerking.com/x', 'https://www.bk.com/y')),
 ('zip+4', values_equivalent('postal_code', '20740-4205', '20740')),
 ('town case', values_equivalent('city', 'Washington', 'WASHINGTON')),
 ('street vs st', values_equivalent('address', '725 King St', '725 King Street')),
 ('road vs rd with dot', values_equivalent('address', '1438 Chain Bridge Rd', '1438 Chain Bridge Road.')),
 ('suite added', values_equivalent('address', '4220 Annandale Road', '4220 Annandale Road ste b')),
 ('different street number', not values_equivalent('address', '725 King St', '727 King St')),
 ('name contains brand', values_equivalent('name', 'Starbucks Coffee Company', 'Starbucks')),
 ('different name', not values_equivalent('name', 'Taco Town', 'Burger Barn')),
 ('url keeps path', match_url('https://www.Starbucks.com/store/1/?utm=x') = 'starbucks.com/store/1'),
 ('host is domain', match_host('https://locations.pizzahut.com/va') = 'pizzahut.com'),
 ('social sites ignored', match_host('https://www.facebook.com/joes') is null);

-- A chain location with the same phone but a different website domain now matches.
update sources set license_class = 'permissive' where code = 'overture_places';
create function pg_temp.rec(id text, name text, brand text, phone text, website text, lon float8, lat float8, city text default 'Arlington', zip text default '22201') returns jsonb
  language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'x', 'license', 'CC0-1.0',
    'name', name, 'address', '1 Main Street', 'city', city, 'state', 'VA', 'postal_code', zip, 'phone', phone,
    'website', website, 'lon', lon, 'lat', lat, 'source_category', 'fast_food', 'category_slug', 'burgers',
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
  pg_temp.rec('o1','Burger King',null,'+13014231909','https://burgerking.com/store-locator/store/2596',-77.10,38.88, 'Arlington', '22201-1234'))) \gset
select pg_temp.load('alltheplaces', jsonb_build_array(
  pg_temp.rec('a1','Burger King','Burger King','+1 301-423-1909','https://www.bk.com/store-locator/store/restaurant_1409',-77.1001,38.88, 'Rosslyn', '22201'))) as s \gset
insert into r select 'same phone matches despite a different website domain',
  (select entity_id from source_records where source_record_id = 'a1') = (select entity_id from source_records where source_record_id = 'o1');
insert into r select 'formatting, town and ZIP differences are not proposed',
  (select count(*) from change_events where event_type = 'attribute_change' and status = 'pending') = 1
  and exists (select 1 from change_events where status = 'pending' and field = 'website');
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
