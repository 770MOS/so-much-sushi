-- Scenario checks for Favorites, Lists and one list (20261113010000_favorites_and_lists.sql):
-- the ready-made Want to try list, my_favorites, list_page and lists_overview for the owner,
-- a friend, someone else and a visitor, and who can call what.
-- Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
grant all on table r to authenticated;

-- u1 is the viewer; u2 is u1's friend; u3 is someone else; u4 has only a pending request.
insert into auth.users(id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle":"u1","first_name":"Johnny","last_name":"Doe"}'),
  ('22222222-2222-2222-2222-222222222222', '{"handle":"u2","first_name":"Priya","last_name":"Shah"}'),
  ('33333333-3333-3333-3333-333333333333', '{"handle":"u3"}'),
  ('44444444-4444-4444-4444-444444444444', '{"handle":"u4"}');
update profiles set display_name = 'Priya Shah' where handle = 'u2';
update profiles set display_name = 'Sam Okafor' where handle = 'u3';
insert into friendships(requester_id, addressee_id, status) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted'),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'pending');

insert into entities(name, address, city, state, location, main_category_id, status) values
  ('Mazaro', '2909 Wilson Blvd', 'Arlington', 'VA', 'SRID=4326;POINT(-77.0936 38.8886)'::extensions.geography,
   (select id from categories where path = 'restaurants'), 'active'),
  ('Kilwins', '3101 Wilson Blvd', 'Arlington', 'VA', 'SRID=4326;POINT(-77.0960 38.8870)'::extensions.geography,
   (select id from categories where path = 'restaurants'), 'active'),
  ('Doyle', '1500 New Hampshire Ave NW', 'Washington', 'DC', 'SRID=4326;POINT(-77.0430 38.9100)'::extensions.geography,
   (select id from categories where path = 'drinks'), 'active'),
  ('Yum''s', '1413 14th St NW', 'Washington', 'DC', 'SRID=4326;POINT(-77.0320 38.9090)'::extensions.geography,
   (select id from categories where path = 'restaurants'), 'active'),
  ('Capo Deli', '109 N Washington St', 'Alexandria', 'VA', 'SRID=4326;POINT(-77.0470 38.8060)'::extensions.geography,
   (select id from categories where path = 'restaurants'), 'temporarily_closed');
create function pid(n text) returns uuid language sql as $$ select id from entities where name = n $$;
insert into entity_categories(entity_id, category_id)
select pid('Mazaro'), id from categories where path = 'restaurants.italian';

insert into stars(user_id, entity_id, created_at) values
  ('11111111-1111-1111-1111-111111111111', pid('Mazaro'), now() - interval '2 days'),
  ('11111111-1111-1111-1111-111111111111', pid('Doyle'), now() - interval '1 day'),
  ('22222222-2222-2222-2222-222222222222', pid('Mazaro'), now());

insert into lists(id, owner_id, name, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Date night', 'friends'),
  ('aaaaaaaa-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Brunch spots', 'private'),
  ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Priya''s picks', 'friends'),
  ('bbbbbbbb-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Public eats', 'public'),
  ('bbbbbbbb-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'Secret', 'private'),
  ('cccccccc-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'Stranger''s public', 'public');
insert into list_items(list_id, entity_id, added_at) values
  ('aaaaaaaa-0000-0000-0000-000000000002', pid('Mazaro'), now() - interval '3 days'),
  ('aaaaaaaa-0000-0000-0000-000000000002', pid('Doyle'), now() - interval '2 days'),
  ('aaaaaaaa-0000-0000-0000-000000000002', pid('Capo Deli'), now() - interval '1 day'),
  ('bbbbbbbb-0000-0000-0000-000000000001', pid('Doyle'), now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', pid('Yum''s'), now()),
  ('cccccccc-0000-0000-0000-000000000001', pid('Mazaro'), now());
insert into list_items(list_id, entity_id)
select l.id, pid('Kilwins') from lists l
where l.owner_id = '11111111-1111-1111-1111-111111111111' and l.is_default_list;

-- ------------------------------------------------------------ Want to try
insert into r select 'every account gets one ready-made Want to try list, Just you',
  (select count(*) = 4 and bool_and(name = 'Want to try' and visibility = 'private')
   from lists where is_default_list)
  and (select count(distinct owner_id) = 4 from lists where is_default_list);

do $$ begin
  update lists set name = 'Maybe' where owner_id = '11111111-1111-1111-1111-111111111111' and is_default_list;
  insert into r values ('Want to try can''t be renamed', false);
exception when check_violation then
  insert into r values ('Want to try can''t be renamed', true);
end $$;
do $$ begin
  update lists set is_default_list = true where id = 'aaaaaaaa-0000-0000-0000-000000000003';
  insert into r values ('no other list can become Want to try', false);
exception when check_violation or unique_violation then
  insert into r values ('no other list can become Want to try', true);
end $$;
update lists set visibility = 'friends' where owner_id = '11111111-1111-1111-1111-111111111111' and is_default_list;
insert into r select 'who can see Want to try can change',
  (select visibility = 'friends' from lists where owner_id = '11111111-1111-1111-1111-111111111111' and is_default_list);
update lists set visibility = 'private' where owner_id = '11111111-1111-1111-1111-111111111111' and is_default_list;
update lists set name = 'Brunch' where id = 'aaaaaaaa-0000-0000-0000-000000000003';
insert into r select 'other lists can be renamed',
  (select name = 'Brunch' from lists where id = 'aaaaaaaa-0000-0000-0000-000000000003');

-- Deleting, as the signed-in owner (row rules apply).
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \gset
set row_security = on;
set role authenticated;
delete from lists where owner_id = '11111111-1111-1111-1111-111111111111' and is_default_list;
delete from lists where id = 'aaaaaaaa-0000-0000-0000-000000000003';
delete from lists where id = 'bbbbbbbb-0000-0000-0000-000000000001';
reset role;
insert into r select 'the owner can''t delete Want to try',
  exists (select 1 from lists where owner_id = '11111111-1111-1111-1111-111111111111' and is_default_list);
insert into r select 'the owner can delete their other lists, not someone else''s',
  not exists (select 1 from lists where id = 'aaaaaaaa-0000-0000-0000-000000000003')
  and exists (select 1 from lists where id = 'bbbbbbbb-0000-0000-0000-000000000001');
delete from profiles where id = '44444444-4444-4444-4444-444444444444';
insert into r select 'deleting an account still removes its Want to try',
  not exists (select 1 from lists where owner_id = '44444444-4444-4444-4444-444444444444');

-- ------------------------------------------------------------ my_favorites
create temp table f as select * from my_favorites();
insert into r select 'favorites: the viewer''s own, A-Z',
  (select array_agg(name order by name) = array['Doyle', 'Mazaro'] from f)
  and (select count(*) = 2 from f);
insert into r select 'favorites: street, town and kinds as in search results',
  (select street = '2909 Wilson Blvd' and city = 'Arlington' and state = 'VA'
          and address = '2909 Wilson Blvd · Arlington'
          and categories = array['Restaurants', 'Italian'] and category_paths[1] = 'restaurants'
          and abs(lat - 38.8886) < 1e-9 and is_starred and not is_want and added_at is not null
   from f where name = 'Mazaro');
insert into r select 'favorites: friends who favorited it too',
  (select recommended_count = 1 and recommended_by = '[{"name":"Priya Shah","handle":"u2"}]'::jsonb
   from f where name = 'Mazaro')
  and (select recommended_count = 0 and recommended_by is null from f where name = 'Doyle');
select set_config('request.jwt.claim.sub', '', false) \gset
insert into r select 'favorites: nothing for a visitor', (select count(*) = 0 from my_favorites());

-- ------------------------------------------------------------ list_page
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \gset
create temp table lp as select list_page('aaaaaaaa-0000-0000-0000-000000000002') as j;
insert into r select 'list: the owner sees it, places A-Z',
  (select (j->>'is_owner')::boolean and j->>'name' = 'Date night' and j->>'visibility' = 'friends'
          and not (j->>'is_default')::boolean
          and jsonb_path_query_array(j->'places', '$[*].name') = '["Capo Deli","Doyle","Mazaro"]'::jsonb from lp);
insert into r select 'list: hearts are the viewer''s own favorites; status kept',
  (select jsonb_path_query_array(j->'places', '$[*].is_starred') = '[false,true,true]'::jsonb
          and j->'places'->0->>'status' = 'temporarily_closed' and j->'places'->0->>'added_at' is not null from lp);
insert into r select 'list: the owner sees their own full name',
  (select j->'owner' = '{"name":"Johnny","handle":"u1"}'::jsonb from lp);
insert into r select 'list: Want to try flagged as the ready-made list',
  (select (list_page(id)->>'is_default')::boolean and list_page(id)->'places'->0->>'name' = 'Kilwins'
   from lists where owner_id = '11111111-1111-1111-1111-111111111111' and is_default_list);
insert into list_items(list_id, entity_id)
select id, pid('Yum''s') from lists where owner_id = '11111111-1111-1111-1111-111111111111' and is_default_list;
insert into r select 'list: someone else''s list marks places on the viewer''s Want to try',
  (select (list_page('bbbbbbbb-0000-0000-0000-000000000002')->'places'->0->>'is_want')::boolean);

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false) \gset
insert into r select 'list: a friend sees a Friends list, with the owner''s full name',
  (select not (j->>'is_owner')::boolean and j->'owner'->>'name' = 'Johnny' and jsonb_array_length(j->'places') = 3
   from (select list_page('aaaaaaaa-0000-0000-0000-000000000002') as j) t);
insert into r select 'list: a friend doesn''t see a Just you list',
  (select list_page(id) = jsonb_build_object('id', id, 'hidden', true)
   from lists where owner_id = '11111111-1111-1111-1111-111111111111' and is_default_list);

select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false) \gset
insert into r select 'list: someone else doesn''t see a Friends list',
  (select list_page('aaaaaaaa-0000-0000-0000-000000000002') = '{"id":"aaaaaaaa-0000-0000-0000-000000000002","hidden":true}'::jsonb);

select set_config('request.jwt.claim.sub', '', false) \gset
insert into r select 'list: a visitor sees a Public list, with first name and last initial',
  (select j->>'name' = 'Public eats' and j->'owner'->>'name' = 'Priya S.' and not (j->>'is_owner')::boolean
          and j->'places'->0->>'name' = 'Yum''s' and not (j->'places'->0->>'is_starred')::boolean
          and not (j->'places'->0->>'is_want')::boolean and (j->'places'->0->>'recommended_count')::int = 0
   from (select list_page('bbbbbbbb-0000-0000-0000-000000000002') as j) t);
insert into r select 'list: a visitor doesn''t see Friends or Just you lists',
  (select (list_page('bbbbbbbb-0000-0000-0000-000000000001')->>'hidden')::boolean
          and (list_page('bbbbbbbb-0000-0000-0000-000000000003')->>'hidden')::boolean);
insert into r select 'list: no such list, nothing',
  (select list_page('00000000-0000-0000-0000-000000000000') is null);

-- ------------------------------------------------------------ lists_overview
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \gset
create temp table o as select * from lists_overview(38.8880, -77.0940);
insert into r select 'overview: own lists first (Want to try at the top), then friends'' shared lists',
  (select array_agg(name order by ord) from (select name, row_number() over () as ord from o) t)
    = array['Want to try', 'Date night', 'Priya''s picks', 'Public eats'];
insert into r select 'overview: friends'' Just you lists and strangers'' lists left out',
  not exists (select 1 from o where name in ('Secret', 'Stranger''s public'));
insert into r select 'overview: counts, towns with the most places first, and town count',
  (select place_count = 3 and towns = array['Alexandria', 'Arlington', 'Washington'] and town_count = 3
          and is_mine and owner_name is null and visibility = 'friends' from o where name = 'Date night');
insert into r select 'overview: closest place from the point given',
  (select closest_miles < 0.1 from o where name = 'Date night')
  and (select closest_miles between 2 and 5 from o where name = 'Public eats');
insert into r select 'overview: points for the card map',
  (select jsonb_array_length(points) = 3 and (points->0->>0)::float between 38 and 39 from o where name = 'Date night');
insert into r select 'overview: a friend''s list names its owner in full',
  (select not is_mine and owner_name = 'Priya Shah' and owner_handle = 'u2' and place_count = 1
   from o where name = 'Public eats');
insert into r select 'overview: no point, no distances',
  (select bool_and(closest_miles is null) from lists_overview());
select set_config('request.jwt.claim.sub', '', false) \gset
insert into r select 'overview: nothing for a visitor', (select count(*) = 0 from lists_overview(38.9, -77.0));

-- ------------------------------------------------------------ names
insert into r select 'names: first name and last initial; from a display name; a handle alone',
  person_name('Priya', 'Shah', 'Priya', 'u2', false) = 'Priya S.'
  and person_name(null, null, 'Sam Okafor', 'u3', false) = 'Sam O.'
  and person_name(null, null, null, 'u9', false) = 'u9'
  and person_name('Priya', 'Shah', null, 'u2', true) = 'Priya Shah';

-- ------------------------------------------------------------ grants
insert into r select 'anyone can call list_page; the Favorites and Lists functions are callable too',
  has_function_privilege('anon', 'list_page(uuid)', 'execute')
  and has_function_privilege('authenticated', 'my_favorites()', 'execute')
  and has_function_privilege('authenticated', 'lists_overview(double precision, double precision)', 'execute');
insert into r select 'the internal helpers aren''t callable through the API',
  not has_function_privilege('anon', 'places_for_viewer(uuid, uuid[])', 'execute')
  and not has_function_privilege('authenticated', 'places_for_viewer(uuid, uuid[])', 'execute')
  and not has_function_privilege('authenticated', 'person_name(text, text, text, text, boolean)', 'execute');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
