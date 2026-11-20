-- Review queue groups: sorting proposals, listing a group, deciding a group in batches.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
create function pg_temp.rec(id text, spider text, name text, addr text, web text, lon float8) returns jsonb language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', spider, 'license', 'CC0-1.0', 'name', name, 'address', addr,
    'city', 'Arlington', 'state', 'VA', 'postal_code', '22201', 'phone', null, 'website', web, 'lon', lon, 'lat', 38.88,
    'source_category', 'restaurant', 'category_slug', 'restaurants', 'payload', jsonb_build_object('operating_status','open','category_mapped',true,'brand',name)) $$;
create function pg_temp.load(records jsonb) returns jsonb language plpgsql as $$ declare v bigint; begin
  insert into source_runs (source_id, scope, status) select id, 'state:VA', 'running' from sources where code = 'alltheplaces' returning id into v;
  perform ingest_source_records(v, records); update source_runs set status = 'succeeded', finished_at = now() where id = v;
  return reconcile_run(v, 'test'); end $$;
create function pg_temp.place(n text, city text default 'Arlington', st text default 'VA', addr text default '1 Main St') returns uuid language sql as $$
  insert into entities (name, address, city, state, postal_code, location, main_category_id, status)
  values (n, addr, city, st, '22201', 'SRID=4326;POINT(-77.1 38.88)'::extensions.geography, (select id from categories where path = 'restaurants'), 'active')
  returning id $$;
create function pg_temp.dup(a uuid, b uuid, sim numeric, dist int) returns bigint language sql as $$
  insert into change_events (event_type, entity_id, old_value, new_value, evidence, status)
  values ('merge', a, jsonb_build_object('duplicate', b), jsonb_build_object('survivor', a),
          jsonb_build_object('name_similarity', sim, 'distance_m', dist, 'proposed_by', 'test'), 'pending')
  returning id $$;
create function pg_temp.chg(e uuid, f text, v text, kind text default 'attribute_change') returns bigint language sql as $$
  insert into change_events (event_type, entity_id, field, old_value, new_value, evidence, status, source_id)
  values (kind, e, f, null, to_jsonb(v), '{"reason": "test"}', 'pending', (select id from sources where code = 'alltheplaces'))
  returning id $$;
create function pg_temp.grp(id bigint) returns text language sql as $$ select review_group from change_events where id = $1 $$;

-- One feed listing a store twice (as All the Places' Qdoba feed does, once per page).
select pg_temp.load(jsonb_build_array(
  pg_temp.rec('q1', 'qdoba', 'Qdoba', '1 Elm St', 'https://locations.qdoba.com/elm/tacos', -77.2000),
  pg_temp.rec('q2', 'qdoba', 'Qdoba', '1 Elm St', 'https://locations.qdoba.com/elm/salads', -77.2000),
  pg_temp.rec('q3', 'qdoba', 'Qdoba', '9 Oak Ave', 'https://locations.qdoba.com/oak/tacos', -77.2001))) \gset
select entity_id as q1 from source_records where source_record_id = 'q1' \gset
select entity_id as q2 from source_records where source_record_id = 'q2' \gset
select entity_id as q3 from source_records where source_record_id = 'q3' \gset
update change_events set status = 'superseded' where status = 'pending';  -- whatever the load proposed itself
insert into r select 'the test feed made three places', count(distinct v) = 3 from unnest(array[:'q1'::uuid, :'q2'::uuid, :'q3'::uuid]) v;

select pg_temp.dup(:'q1', :'q2', 1, 0) as d_feed \gset
select pg_temp.dup(:'q1', :'q3', 1, 8) as d_feed_addr \gset
select pg_temp.place('Sub Shop') as o1 \gset
select pg_temp.place('Sub Shop') as o2 \gset
select pg_temp.place('Sub Shop') as o3 \gset
select pg_temp.place('Sub Shop Express') as o4 \gset
select pg_temp.dup(:'o1', :'o2', 1, 10) as d_near \gset
select pg_temp.dup(:'o1', :'o3', 1, 60) as d_far \gset
select pg_temp.dup(:'o1', :'o4', 0.4, 5) as d_variant \gset

-- Census towns for the state check.
insert into localities (kind, code, name, state, label, location, source) values
  ('place', '2148000', 'Louisville', 'KY', 'Louisville, KY', 'SRID=4326;POINT(-85.7 38.2)'::extensions.geography, 'test'),
  ('place', '2914410', 'Clinton', 'MO', 'Clinton, MO', 'SRID=4326;POINT(-93.7 38.3)'::extensions.geography, 'test');
insert into locality_names (locality_id, name) select id, name from localities where source = 'test';
select pg_temp.place('Corner Deli', 'Louisville', 'KY') as louis \gset
select pg_temp.place('Chicken Spot', 'Clinton', 'WY') as clint \gset
select pg_temp.place('Nowhere Diner', 'Smallville', 'KS') as small \gset

select pg_temp.chg(:'o1', 'website', 'https://subshop.example/stores/1') as c_web \gset
select pg_temp.chg(:'o1', 'address', '1 Main Street, Suite 2') as c_addr_same \gset
select pg_temp.chg(:'o2', 'address', '44 Broad St') as c_addr_other \gset
select pg_temp.chg(:'louis', 'state', 'IN') as c_state_ours \gset
select pg_temp.chg(:'clint', 'state', 'MO') as c_state_theirs \gset
select pg_temp.chg(:'small', 'state', 'NE') as c_state_unclear \gset
select pg_temp.chg(:'o3', 'name', 'Sub Shop #12') as c_name \gset
select pg_temp.chg(:'o3', 'phone', '+17035550100') as c_phone \gset
select pg_temp.chg(:'o4', null, 'permanently_closed', 'closure_signal') as c_closed \gset
insert into change_events (event_type, entity_id, field, new_value, evidence, status)
values ('attribute_change', :'o4', 'categories', '{"add_category": "restaurants.pizza"}', '{}', 'pending') returning id as c_tag \gset

-- ---------------------------------------------------------------- sorting
select count(*) as groups_n from admin_review_groups() \gset
insert into r select 'same feed, same name and address', pg_temp.grp(:d_feed) = 'dup_feed_same';
insert into r select 'same feed, another address', pg_temp.grp(:d_feed_addr) = 'dup_feed_variant';
insert into r select 'same name within 25 m', pg_temp.grp(:d_near) = 'dup_name_near';
insert into r select 'same name 25-75 m', pg_temp.grp(:d_far) = 'dup_name_far';
insert into r select 'names differ', pg_temp.grp(:d_variant) = 'dup_variant';
insert into r select 'websites', pg_temp.grp(:c_web) = 'chg_website';
insert into r select 'addresses with the same house number', pg_temp.grp(:c_addr_same) = 'chg_address_same';
insert into r select 'other addresses', pg_temp.grp(:c_addr_other) = 'chg_address_other';
insert into r select 'state: the town is in ours (Louisville, KY, not IN)', pg_temp.grp(:c_state_ours) = 'chg_state_ours';
insert into r select 'state: the town is in theirs (Clinton, MO, not WY)', pg_temp.grp(:c_state_theirs) = 'chg_state_theirs';
insert into r select 'state: town not in the list', pg_temp.grp(:c_state_unclear) = 'chg_state_unclear';
insert into r select 'names and other fields', pg_temp.grp(:c_name) = 'chg_name' and pg_temp.grp(:c_phone) = 'chg_other';
insert into r select 'closures', pg_temp.grp(:c_closed) = 'chg_status';
insert into r select 'tag suggestions stay out (their own tab)', pg_temp.grp(:c_tag) is null;
insert into r select 'the group list: counts, kinds, examples',
  (select items from admin_review_groups() where review_group = 'dup_name_near') = 1
  and (select kind from admin_review_groups() where review_group = 'chg_website') = 'changes'
  and (select examples->>0 from admin_review_groups() where review_group = 'dup_feed_same') = 'Qdoba / Qdoba · 0 m · Arlington, VA'
  and (select examples->>0 from admin_review_groups() where review_group = 'chg_website') like 'Sub Shop · (none) → https://subshop.example/stores/1';

-- ---------------------------------------------------------------- listing
insert into r select 'a duplicates group, with its total',
  (select array_agg(event_id) from admin_review_duplicates('dup_feed_same')) = array[:d_feed::bigint]
  and (select total from admin_review_duplicates('dup_feed_same')) = 1
  and not exists (select 1 from admin_review_duplicates('chg_website'));
insert into r select 'a changes group shows today''s value and the proposed one',
  (select current_value is null and proposed_value = 'https://subshop.example/stores/1' from admin_review_changes('chg_website'))
  and (select current_value = 'KY' and proposed_value = 'IN' from admin_review_changes('chg_state_ours'));
insert into r select 'one pair', (select a_id = :'q1' and b_id = :'q2' and review_group = 'dup_feed_same' from admin_get_merge_proposal(:d_feed));
insert into r select 'its place in the group and the next pair',
  (select group_position = 1 and group_total = 1 and next_event_id is null from admin_get_merge_proposal(:d_feed))
  and (select group_position is null from admin_get_merge_proposal(:d_near)) is not true;

-- ---------------------------------------------------------------- deciding
select admin_decide_review_group('dup_feed_same', true, 'me') as res \gset
insert into r select 'accept a duplicates group', :'res'::jsonb = '{"decided": 1, "left": 0}'::jsonb
  and (select status = 'merged' and merged_into = :'q1' from entities where id = :'q2')
  and (select status from change_events where id = :d_feed) = 'approved';
select admin_decide_review_group('chg_state_ours', false, 'me') as res \gset
insert into r select 'decline a changes group', :'res'::jsonb = '{"decided": 1, "left": 0}'::jsonb
  and (select state from entities where id = :'louis') = 'KY'
  and (select status from change_events where id = :c_state_ours) = 'rejected';
select admin_decide_review_group('chg_website', true, 'me') as res \gset
insert into r select 'accept a changes group', :'res'::jsonb->>'left' = '0'
  and (select website from entities where id = :'o1') = 'https://subshop.example/stores/1';

-- Copies of one store: every pair proposed; accepting the group leaves one place.
select pg_temp.place('Pretzel Stand', addr => '5 Mall Way') as p1 \gset
select pg_temp.place('Pretzel Stand', addr => '5 Mall Way') as p2 \gset
select pg_temp.place('Pretzel Stand', addr => '5 Mall Way') as p3 \gset
select pg_temp.dup(:'p1', :'p2', 1, 0) as x12 \gset
select pg_temp.dup(:'p1', :'p3', 1, 0) as x13 \gset
select pg_temp.dup(:'p2', :'p3', 1, 0) as x23 \gset
update change_events set review_group = 'dup_feed_same' where id in (:x12, :x13, :x23);
insert into r select 'batches: two at a time', admin_decide_review_group('dup_feed_same', true, 'me', 2) = '{"decided": 2, "left": 1}'::jsonb;
select admin_decide_review_group('dup_feed_same', true, 'me', 2) as res \gset
insert into r select 'copies end up in one place', :'res'::jsonb = '{"decided": 1, "left": 0}'::jsonb
  and (select count(*) from entities where id in (:'p1', :'p2', :'p3') and status = 'active') = 1
  and (select status from change_events where id = :x23) = 'superseded';

insert into r select 'new proposals are sorted on the next visit',
  pg_temp.grp(pg_temp.dup(:'o1', :'o4', 1, 3)) is null
  and exists (select 1 from admin_review_groups() where review_group = 'dup_name_near' and items = 2);
do $$ begin
  perform admin_decide_review_group('everything', true, 'me');
  insert into r values ('unknown groups are refused', false);
exception when others then
  insert into r values ('unknown groups are refused', sqlerrm like 'unknown review group%');
end $$;

insert into r select 'not callable through the API',
  not has_function_privilege('authenticated', 'admin_review_groups()', 'execute')
  and not has_function_privilege('anon', 'admin_decide_review_group(text, boolean, text, integer)', 'execute')
  and not has_function_privilege('authenticated', 'admin_review_duplicates(text, integer, integer)', 'execute');
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
