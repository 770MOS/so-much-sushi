-- Admin All places at national scale: the no-source flag, the capped count, paging and filters.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
create function pg_temp.rec(id text, name text, lon float8) returns jsonb language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'x', 'license', 'CC0-1.0', 'name', name, 'address', '9 Elm St',
    'city', 'Arlington', 'state', 'VA', 'postal_code', '22201', 'phone', null, 'website', null, 'lon', lon, 'lat', 38.88,
    'source_category', 'cafe', 'category_slug', 'coffee', 'payload', jsonb_build_object('operating_status','open','category_mapped',true,'brand',name)) $$;
create function pg_temp.load(records jsonb) returns jsonb language plpgsql as $$ declare v bigint; begin
  insert into source_runs (source_id, scope, status) select id, 'state:VA', 'running' from sources where code = 'alltheplaces' returning id into v;
  perform ingest_source_records(v, records); update source_runs set status = 'succeeded', finished_at = now() where id = v;
  return reconcile_run(v, 'test'); end $$;

-- ---------------------------------------------------------------- the no-source flag
select admin_add_place('{"name":"Corner Cafe","address":"9 Elm St","city":"Arlington","state":"VA","lat":38.88,"lng":-77.20,"main_category":"coffee"}', 'me') as hand \gset
insert into r select 'a place added by hand has no source', (select no_source from entities where id = :'hand')
  and exists (select 1 from admin_search_places(p_origin => 'unconfirmed') where id = :'hand');

select pg_temp.load(jsonb_build_array(pg_temp.rec('c1', 'Corner Cafe', -77.2000), pg_temp.rec('n1', 'Brand New Bakery', -77.30))) \gset
insert into r select 'its first source record clears the flag',
  (select entity_id from source_records where source_record_id = 'c1') = :'hand'
  and not (select no_source from entities where id = :'hand')
  and not exists (select 1 from admin_search_places(p_origin => 'unconfirmed') where id = :'hand');
select entity_id as fresh from source_records where source_record_id = 'n1' \gset
insert into r select 'a place made from a source record has a source', not (select no_source from entities where id = :'fresh');

select updated_at as before from entities where id = :'hand' \gset
update source_records set name = 'Corner Cafe & Bakery' where source_record_id = 'c1';
insert into r select 'other changes to a source record leave the place alone', (select updated_at from entities where id = :'hand') = :'before';

update source_records set entity_id = :'fresh' where source_record_id = 'c1';
insert into r select 'moving its only record away sets the flag, the receiving place keeps none',
  (select no_source from entities where id = :'hand') and not (select no_source from entities where id = :'fresh');
update source_records set entity_id = :'hand' where source_record_id = 'c1';
insert into r select 'moving it back clears it', not (select no_source from entities where id = :'hand');
update source_records set entity_id = null, match_status = 'unmatched' where source_record_id = 'n1';
insert into r select 'unlinking the last record sets it', (select no_source from entities where id = :'fresh');

-- ---------------------------------------------------------------- count, paging, filters
insert into entities (name, address, city, state, postal_code, location, main_category_id, status, needs_review)
select format('Bulk %s', lpad(g::text, 5, '0')), '1 Main St', 'Springfield', 'IL', '62701-0001',
       'SRID=4326;POINT(-89.65 39.8)'::extensions.geography, (select id from categories where path = 'restaurants'), 'active', g % 1000 = 0
from generate_series(1, 10050) g;
insert into entities (name, location, main_category_id, state, city, postal_code)
select v.n, 'SRID=4326;POINT(-77.1 38.88)'::extensions.geography, (select id from categories where path = 'restaurants'), 'VA', 'Arlington', '22201'
from (values ('100% Juice'), ('Juice_Bar'), ('JuiceXBar')) v(n);

insert into r select 'the count stops at 10,000 (10001 = more than 10,000)',
  (select total from admin_search_places(p_q => 'bulk') limit 1) = 10001;
insert into r select 'a page is in name order', (select array_agg(name) from admin_search_places(p_q => 'bulk', p_limit => 3))
  = array['Bulk 00001', 'Bulk 00002', 'Bulk 00003'];
insert into r select 'pages follow on', (select array_agg(name) from admin_search_places(p_q => 'bulk', p_limit => 2, p_offset => 10048))
  = array['Bulk 10049', 'Bulk 10050'];
insert into r select 'up to 1,000 rows a call (bulk edits of all matching)', (select count(*) from admin_search_places(p_q => 'bulk', p_limit => 5000)) = 1000;
insert into r select 'small results are counted exactly',
  (select total from admin_search_places(p_q => 'bulk', p_needs_review => true) limit 1) = 10
  and (select count(*) from admin_search_places(p_q => 'bulk 1', p_needs_review => false)) = 50;
insert into r select 'state and town', (select total from admin_search_places(p_state => 'IL', p_city => 'Springfield') limit 1) = 10001
  and not exists (select 1 from admin_search_places(p_state => 'IL', p_city => 'Arlington'));
insert into r select 'ZIP+4 typed matches the first five digits', (select total from admin_search_places(p_zip => '62701-9999') limit 1) = 10001
  and (select count(*) from admin_search_places(p_zip => '22201', p_q => 'juice')) = 3;
insert into r select 'name contains: % and _ are plain characters',
  (select array_agg(name) from admin_search_places(p_q => '_')) = array['Juice_Bar']
  and (select array_agg(name) from admin_search_places(p_q => '100%')) = array['100% Juice']
  and (select count(*) from admin_search_places(p_q => 'juice')) = 3;
insert into r select 'an unknown main category finds nothing', not exists (select 1 from admin_search_places(p_main => 'nowhere'));
insert into r select 'no matches, no rows', not exists (select 1 from admin_search_places(p_q => 'zzzz'));
insert into r select 'filters: towns for the state given only', admin_place_filters('IL')->'towns' = '[{"state": "IL", "value": "Springfield", "count": 10050}]'::jsonb;
insert into entities (name, location, main_category_id, state, city)
select 'One More', 'SRID=4326;POINT(-89.65 39.8)'::extensions.geography, (select id from categories where path = 'restaurants'), 'IL', 'Springfield';
insert into r select 'menu counts are kept for a day', admin_place_filters('IL')->'towns'->0->>'count' = '10050';
update place_counts set refreshed_at = now() - interval '25 hours';
insert into r select 'then counted again', admin_place_filters('IL')->'towns'->0->>'count' = '10051'
  and (admin_place_filters()->'states') @> '[{"value": "IL", "count": 10051}]'::jsonb;

-- ---------------------------------------------------------------- the rest
insert into r select 'indexes for the list are there', (select count(*) from pg_indexes where schemaname = 'public' and indexname in
  ('entities_name_idx', 'entities_name_trgm_idx', 'entities_state_city_idx', 'entities_zip5_idx', 'entities_needs_review_idx',
   'entities_no_source_idx', 'entity_categories_category_idx', 'change_events_added_by_hand_idx')) = 8;
insert into r select 'the flag keeper is not callable through the API',
  not has_function_privilege('anon', 'track_place_sources()', 'execute')
  and not has_function_privilege('authenticated', 'track_place_sources()', 'execute')
  and not has_function_privilege('authenticated', 'admin_place_filters(text)', 'execute')
  and not has_function_privilege('authenticated', 'refresh_place_counts()', 'execute')
  and not has_table_privilege('anon', 'place_counts', 'select');
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
