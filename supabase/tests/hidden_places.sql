-- Scenario checks for the Hidden places page (20261124000000_hidden_places.sql): my_hidden for
-- the person who hid, someone else and a visitor, who can call it, and place_detail saying
-- whether the viewer hid a place.
-- Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
grant all on table r to authenticated;

-- u1 hides places; u2 is u1's friend; u3 is someone else.
insert into auth.users(id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle":"u1","first_name":"Johnny","last_name":"Doe"}'),
  ('22222222-2222-2222-2222-222222222222', '{"handle":"u2","first_name":"Priya","last_name":"Shah"}'),
  ('33333333-3333-3333-3333-333333333333', '{"handle":"u3"}');
insert into friendships(requester_id, addressee_id, status) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted');

insert into entities(name, address, city, state, location, main_category_id, status) values
  ('Mazaro', '2909 Wilson Blvd', 'Arlington', 'VA', 'SRID=4326;POINT(-77.0936 38.8886)'::extensions.geography,
   (select id from categories where path = 'restaurants'), 'active'),
  ('Kilwins', '3101 Wilson Blvd', 'Arlington', 'VA', 'SRID=4326;POINT(-77.0960 38.8870)'::extensions.geography,
   (select id from categories where path = 'restaurants'), 'active'),
  ('Doyle', '1500 New Hampshire Ave NW', 'Washington', 'DC', 'SRID=4326;POINT(-77.0430 38.9100)'::extensions.geography,
   (select id from categories where path = 'drinks'), 'active'),
  ('Capo Deli', '109 N Washington St', 'Alexandria', 'VA', 'SRID=4326;POINT(-77.0470 38.8060)'::extensions.geography,
   (select id from categories where path = 'restaurants'), 'permanently_closed'),
  ('Old Name', '1 Main St', 'Arlington', 'VA', 'SRID=4326;POINT(-77.1000 38.8800)'::extensions.geography,
   (select id from categories where path = 'restaurants'), 'removed');
create function pid(n text) returns uuid language sql as $$ select id from entities where name = n $$;
insert into entity_categories(entity_id, category_id)
select pid('Mazaro'), id from categories where path = 'restaurants.italian';

insert into hidden_entities(user_id, entity_id, created_at) values
  ('11111111-1111-1111-1111-111111111111', pid('Mazaro'), now() - interval '2 days'),
  ('11111111-1111-1111-1111-111111111111', pid('Doyle'), now() - interval '1 day'),
  ('11111111-1111-1111-1111-111111111111', pid('Capo Deli'), now()),
  ('11111111-1111-1111-1111-111111111111', pid('Old Name'), now()),
  ('33333333-3333-3333-3333-333333333333', pid('Kilwins'), now());
-- A hidden place can still be a friend's favorite.
insert into stars(user_id, entity_id) values ('22222222-2222-2222-2222-222222222222', pid('Mazaro'));

-- ------------------------------------------------------------ my_hidden
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \gset
create temp table h as select * from my_hidden();
insert into r select 'hidden: the viewer''s own, A-Z, closed places too',
  (select array_agg(name order by lower(name)) = array['Capo Deli', 'Doyle', 'Mazaro'] from h)
  and (select count(*) = 3 from h);
insert into r select 'hidden: removed places are left out', not exists (select 1 from h where name = 'Old Name');
insert into r select 'hidden: nobody else''s', not exists (select 1 from h where name = 'Kilwins');
insert into r select 'hidden: street, town and kinds as in search results',
  (select street = '2909 Wilson Blvd' and city = 'Arlington' and state = 'VA'
          and address = '2909 Wilson Blvd · Arlington'
          and categories = array['Restaurants', 'Italian'] and category_paths[1] = 'restaurants'
          and abs(lat - 38.8886) < 1e-9 and not is_starred and added_at is not null
          and recommended_count = 1
   from h where name = 'Mazaro');
insert into r select 'hidden: status kept', (select status = 'permanently_closed' from h where name = 'Capo Deli');
insert into r select 'place page: says so when the viewer hid the place, and not when someone else did',
  (select (place_detail(pid('Mazaro'))->>'is_hidden')::boolean)
  and (select not (place_detail(pid('Kilwins'))->>'is_hidden')::boolean);
insert into r select 'place page: the rest of the place is as before',
  (select j->>'name' = 'Mazaro' and j->>'street' = '2909 Wilson Blvd' and not (j->>'is_starred')::boolean
          and (j->>'friends_count')::integer = 1 and jsonb_array_length(j->'categories') = 2
   from (select place_detail(pid('Mazaro')) as j) t);

-- The page shows a place again by deleting the person's own row, as the results page does.
create temp table ids as select name, id from entities;
grant select on table ids to authenticated;
set row_security = on;
set role authenticated;
delete from hidden_entities
where user_id = '11111111-1111-1111-1111-111111111111' and entity_id = (select id from ids where name = 'Doyle');
insert into r select 'hidden: shown again, it leaves the list',
  (select array_agg(name order by lower(name)) = array['Capo Deli', 'Mazaro'] from my_hidden());
delete from hidden_entities where entity_id = (select id from ids where name = 'Kilwins');
reset role;
insert into r select 'hidden: nobody can show someone else''s hidden place again',
  exists (select 1 from hidden_entities where entity_id = pid('Kilwins'));

select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false) \gset
insert into r select 'hidden: someone else sees only their own',
  (select array_agg(name) = array['Kilwins'] from my_hidden());
select set_config('request.jwt.claim.sub', '', false) \gset
insert into r select 'hidden: nothing for a visitor', (select count(*) = 0 from my_hidden());
insert into r select 'place page: never hidden for a visitor',
  (select not (place_detail(pid('Mazaro'))->>'is_hidden')::boolean);

-- ------------------------------------------------------------ grants
insert into r select 'my_hidden is callable through the API',
  has_function_privilege('authenticated', 'my_hidden()', 'execute');
insert into r select 'place_detail keeps its grants: anyone through the API, not PUBLIC',
  has_function_privilege('anon', 'place_detail(uuid)', 'execute')
  and has_function_privilege('authenticated', 'place_detail(uuid)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.proname = 'place_detail' and a.grantee = 0 and a.privilege_type = 'EXECUTE');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
