-- Scenario checks for the place panel and page (20261113000000_place_panel.sql): what
-- place_detail shows a member and a visitor, merged places, and who can call it.
-- Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);

-- u1 looks at the place; u2, u3, u4 and u5 are u1's friends; u6 has only a pending request.
insert into auth.users(id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle":"u1"}'),
  ('22222222-2222-2222-2222-222222222222', '{"handle":"u2"}'),
  ('33333333-3333-3333-3333-333333333333', '{"handle":"u3"}'),
  ('44444444-4444-4444-4444-444444444444', '{"handle":"u4"}'),
  ('55555555-5555-5555-5555-555555555555', '{"handle":"u5"}'),
  ('66666666-6666-6666-6666-666666666666', '{"handle":"u6"}');
update profiles set display_name = 'Priya Shah' where handle = 'u2';
update profiles set display_name = 'Sam Okafor' where handle = 'u3';
insert into friendships(requester_id, addressee_id, status) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'accepted'),
  ('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444', 'accepted'),
  ('11111111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555', 'accepted'),
  ('66666666-6666-6666-6666-666666666666', '11111111-1111-1111-1111-111111111111', 'pending');

insert into entities(name, address, city, state, postal_code, phone, website, location, main_category_id, status, hours)
values ('Mazaro', '2909 Wilson Blvd', 'Arlington', 'VA', '22201-1234', '7032763099', 'https://mazarova.com',
        'SRID=4326;POINT(-77.0936 38.8886)'::extensions.geography,
        (select id from categories where path = 'restaurants'), 'active', '"Tu-Su 17:00-22:00"'::jsonb),
       ('Old Mazaro', '2909 Wilson Blvd', 'Arlington', 'VA', null, null, null,
        'SRID=4326;POINT(-77.0936 38.8886)'::extensions.geography,
        (select id from categories where path = 'restaurants'), 'active', null);
create function pid(n text) returns uuid language sql as $$ select id from entities where name = n $$;
insert into entity_categories(entity_id, category_id)
select pid('Mazaro'), id from categories where path = 'restaurants.italian';
update entities set status = 'merged', merged_into = pid('Mazaro') where name = 'Old Mazaro';

-- Friends' favorites in this order: u3, u2, u4, u5 (u6's request is still pending).
insert into stars(user_id, entity_id, created_at) values
  ('33333333-3333-3333-3333-333333333333', pid('Mazaro'), now() - interval '4 days'),
  ('22222222-2222-2222-2222-222222222222', pid('Mazaro'), now() - interval '3 days'),
  ('44444444-4444-4444-4444-444444444444', pid('Mazaro'), now() - interval '2 days'),
  ('55555555-5555-5555-5555-555555555555', pid('Mazaro'), now() - interval '1 day'),
  ('66666666-6666-6666-6666-666666666666', pid('Mazaro'), now()),
  ('11111111-1111-1111-1111-111111111111', pid('Mazaro'), now());
-- Want to try comes with the account (20261113010000_favorites_and_lists.sql); give it a known id.
update lists set id = 'aaaaaaaa-0000-0000-0000-000000000001'
where owner_id = '11111111-1111-1111-1111-111111111111' and is_default_list;
insert into lists(id, owner_id, name, is_default_list) values
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'date night', false),
  ('aaaaaaaa-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Brunch', false),
  ('aaaaaaaa-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'Priya''s picks', false);
insert into list_items(list_id, entity_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', pid('Mazaro')),
  ('aaaaaaaa-0000-0000-0000-000000000002', pid('Mazaro')),
  ('aaaaaaaa-0000-0000-0000-000000000003', pid('Mazaro')),
  ('aaaaaaaa-0000-0000-0000-000000000004', pid('Mazaro'));

-- Where the details come from: one Overture record.
do $$
declare v bigint;
begin
  insert into source_runs (source_id, scope, status) select id, 'state:VA', 'succeeded' from sources where code = 'overture_places'
    returning id into v;
  insert into source_records (source_id, source_record_id, license, payload, first_seen_run, last_seen_run, entity_id, match_status)
  select s.id, 'ov-1', 'CDLA-Permissive-2.0', '{}'::jsonb, v, v, pid('Mazaro'), 'auto' from sources s where s.code = 'overture_places';
end $$;

-- ------------------------------------------------------------ a member
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \gset
create temp table d as select place_detail(pid('Mazaro')) as j;
insert into r select 'member: the place, with its full address and formatted fields as stored',
  (select j->>'name' = 'Mazaro' and j->>'address' = '2909 Wilson Blvd, Arlington, VA 22201'
          and j->>'street' = '2909 Wilson Blvd' and j->>'city' = 'Arlington' and j->>'phone' = '7032763099'
          and j->>'website' = 'https://mazarova.com' and j->>'status' = 'active'
          and abs((j->>'lat')::float - 38.8886) < 1e-9 from d);
insert into r select 'member: hours given as text',
  (select j->>'hours' = 'Tu-Su 17:00-22:00' from d);
insert into r select 'member: the main category first, then finer kinds',
  (select j->'categories' = '[{"name":"Restaurants","path":"restaurants"},{"name":"Italian","path":"restaurants.italian"}]'::jsonb
     or (j->'categories'->0->>'path' = 'restaurants' and j->'categories'->1->>'path' = 'restaurants.italian') from d);
insert into r select 'member: own favorite and Want to try',
  (select (j->>'is_starred')::boolean and (j->>'is_want')::boolean from d);
insert into r select 'member: own other lists A-Z; Want to try and a friend''s list left out',
  (select jsonb_path_query_array(j->'lists', '$[*].name') = '["Brunch","date night"]'::jsonb from d);
insert into r select 'member: three friends named, earliest first, and all four counted (not the pending request)',
  (select jsonb_path_query_array(j->'friends', '$[*].name') = '["Sam Okafor","Priya Shah","u4"]'::jsonb
          and (j->>'friends_count')::int = 4 from d);
insert into r select 'member: where the details come from',
  (select j->'sources' = '["overture_places"]'::jsonb from d);

-- ------------------------------------------------------------ merged places
insert into r select 'a merged place shows its survivor (so the page can move to its link)',
  (select place_detail(pid('Old Mazaro'))->>'id' = pid('Mazaro')::text);
insert into r select 'no such place: nothing',
  (select place_detail('00000000-0000-0000-0000-000000000000') is null);

-- ------------------------------------------------------------ a visitor
select set_config('request.jwt.claim.sub', '', false) \gset
insert into r select 'visitor: the same place with no marks, lists or friends',
  (select j->>'name' = 'Mazaro' and not (j->>'is_starred')::boolean and not (j->>'is_want')::boolean
          and j->'lists' = '[]'::jsonb and j->'friends' = '[]'::jsonb and (j->>'friends_count')::int = 0
   from (select place_detail(pid('Mazaro')) as j) t);

-- ------------------------------------------------------------ grants
insert into r select 'anyone can call place_detail through the API; PUBLIC cannot',
  has_function_privilege('anon', 'place_detail(uuid)', 'execute')
  and has_function_privilege('authenticated', 'place_detail(uuid)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.proname = 'place_detail' and a.grantee = 0 and a.privilege_type = 'EXECUTE');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
