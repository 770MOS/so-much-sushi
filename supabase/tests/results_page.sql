-- Scenario checks for the results page functions (20261112000000_results_page.sql).
-- Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);

-- People: u1 searches; u2, u3 and u4 are u1's friends; u5 has only a pending request.
insert into auth.users(id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle":"u1"}'),
  ('22222222-2222-2222-2222-222222222222', '{"handle":"u2"}'),
  ('33333333-3333-3333-3333-333333333333', '{"handle":"u3"}'),
  ('44444444-4444-4444-4444-444444444444', '{"handle":"u4"}'),
  ('55555555-5555-5555-5555-555555555555', '{"handle":"u5"}');
insert into friendships(requester_id, addressee_id, status) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'accepted'),
  ('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444', 'accepted'),
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', 'pending');

-- Places around (-77.1, 38.88), nearest first.
create temp table p(name text, lng float, main text, tag text, status text);
insert into p values
  ('Alpha Pizza',         -77.1001, 'restaurants', 'restaurants.italian.pizza',     'active'),
  ('Bella Italia',        -77.1002, 'restaurants', 'restaurants.italian',           'active'),
  ('Corner Bar',          -77.1003, 'drinks',      'drinks.bar.wine_bar',           'active'),
  ('Daily Grind Coffee',  -77.1004, 'coffee',      null,                            'active'),
  ('Hidden Gem',          -77.1005, 'restaurants', 'restaurants.italian',           'active'),
  ('Closed Trattoria',    -77.1000, 'restaurants', 'restaurants.italian',           'permanently_closed'),
  ('Far Sushi',           -77.66,   'restaurants', 'restaurants.asian.japanese.sushi', 'active');  -- about 30 miles west
insert into entities(name, location, main_category_id, status)
select p.name, ('SRID=4326;POINT(' || p.lng || ' 38.88)')::extensions.geography,
       (select id from categories where path = p.main::ltree), p.status
from p;
insert into entity_categories(entity_id, category_id)
select e.id, c.id from p join entities e on e.name = p.name join categories c on c.path = p.tag::ltree where p.tag is not null;

create function pid(n text) returns uuid language sql as $$ select id from entities where name = n $$;

-- u1: hides Hidden Gem, favorites Alpha Pizza, keeps Daily Grind on the ready-made list.
insert into hidden_entities(user_id, entity_id) values ('11111111-1111-1111-1111-111111111111', pid('Hidden Gem'));
insert into stars(user_id, entity_id) values ('11111111-1111-1111-1111-111111111111', pid('Alpha Pizza'));
insert into lists(id, owner_id, name, is_default_list) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Want to try', true),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Date night', false);
insert into list_items(list_id, entity_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', pid('Daily Grind Coffee')),
  ('aaaaaaaa-0000-0000-0000-000000000002', pid('Corner Bar'));
-- Friends' favorites: three friends on Bella Italia (and the pending person), one on Corner Bar.
insert into stars(user_id, entity_id, created_at) values
  ('22222222-2222-2222-2222-222222222222', pid('Bella Italia'), now() - interval '3 days'),
  ('33333333-3333-3333-3333-333333333333', pid('Bella Italia'), now() - interval '2 days'),
  ('44444444-4444-4444-4444-444444444444', pid('Bella Italia'), now() - interval '1 day'),
  ('55555555-5555-5555-5555-555555555555', pid('Bella Italia'), now()),
  ('22222222-2222-2222-2222-222222222222', pid('Corner Bar'), now());

create function names(rows text[]) returns text language sql as $$ select array_to_string(array(select unnest(rows) order by 1), ',') $$;

-- ------------------------------------------------------------ search_places, not signed in
select set_config('request.jwt.claim.sub', '', false) \gset
insert into r select 'visitor: everything active within the radius, nearest first, closed and far left out',
  (select array_agg(name order by ordinality) = array['Alpha Pizza','Bella Italia','Corner Bar','Daily Grind Coffee','Hidden Gem']
          and bool_and(total_count = 5)
   from search_places(38.88, -77.1, 10) with ordinality);
insert into r select 'visitor: nothing marked as theirs',
  (select not bool_or(is_starred or is_hidden or is_want) and bool_and(recommended_count = 0) from search_places(38.88, -77.1, 10));
insert into r select 'visitor: the three filters show nothing',
  (select count(*) = 0 from search_places(38.88, -77.1, 10, null, null, true, true, true));

-- ------------------------------------------------------------ search_places, signed in as u1
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \gset
insert into r select 'hidden place left out and not counted',
  (select count(*) = 4 and bool_and(total_count = 4) and count(*) filter (where name = 'Hidden Gem') = 0
   from search_places(38.88, -77.1, 10));
insert into r select 'show_hidden brings it back, marked',
  (select is_hidden from search_places(38.88, -77.1, 10, null, null, false, false, false, true) where name = 'Hidden Gem');
insert into r select 'own favorite marked',
  (select is_starred from search_places(38.88, -77.1, 10) where name = 'Alpha Pizza');
insert into r select 'Want to try marked from the ready-made list only',
  (select bool_and(is_want = (name = 'Daily Grind Coffee')) from search_places(38.88, -77.1, 10));
insert into r select 'three friends named, oldest first; the pending request not counted',
  (select recommended_count = 3 and jsonb_array_length(recommended_by) = 3
          and recommended_by->0->>'handle' = 'u2' and recommended_by->2->>'handle' = 'u4'
   from search_places(38.88, -77.1, 10) where name = 'Bella Italia');
insert into r select 'Favorites only',
  (select names(array_agg(name)) = 'Alpha Pizza' from search_places(38.88, -77.1, 10, null, null, true));
insert into r select 'Friends only',
  (select names(array_agg(name)) = 'Bella Italia,Corner Bar' and bool_and(total_count = 2)
   from search_places(38.88, -77.1, 10, null, null, false, true));
insert into r select 'Want to try only',
  (select names(array_agg(name)) = 'Daily Grind Coffee' from search_places(38.88, -77.1, 10, null, null, false, false, true));
insert into r select 'Favorites and Want to try together show either',
  (select names(array_agg(name)) = 'Alpha Pizza,Daily Grind Coffee' from search_places(38.88, -77.1, 10, null, null, true, false, true));
insert into r select 'all three together',
  (select names(array_agg(name)) = 'Alpha Pizza,Bella Italia,Corner Bar,Daily Grind Coffee'
   from search_places(38.88, -77.1, 10, null, null, true, true, true));
insert into r select 'a cuisine includes its finer kinds (pizza under Italian)',
  (select names(array_agg(name)) = 'Alpha Pizza,Bella Italia' from search_places(38.88, -77.1, 10, 'restaurants.italian'));
insert into r select 'filters combine with the cuisine',
  (select names(array_agg(name)) = 'Bella Italia' from search_places(38.88, -77.1, 10, 'restaurants.italian', null, false, true));
insert into r select 'name search',
  (select names(array_agg(name)) = 'Alpha Pizza' from search_places(38.88, -77.1, 10, null, 'pizza'));

-- ------------------------------------------------------------ search_facets
insert into r select 'facets: places per type, hidden left out',
  (select f->'types' = '{"all":4,"restaurants":2,"drinks":1,"coffee":1}'::jsonb from search_facets(38.88, -77.1, 10) f);
insert into r select 'facets: without a type, the finer kinds of every type',
  (select f->'cuisines' = '[{"n":1,"name":"Bar","path":"drinks.bar"},{"n":1,"name":"Wine Bar","path":"drinks.bar.wine_bar"},{"n":2,"name":"Italian","path":"restaurants.italian"},{"n":1,"name":"Pizza","path":"restaurants.italian.pizza"}]'::jsonb
   from search_facets(38.88, -77.1, 10) f);
insert into r select 'facets: favorites, friends, want and hidden counts',
  (select (f->>'favorites')::int = 1 and (f->>'friends')::int = 2 and (f->>'want')::int = 1 and (f->>'hidden')::int = 1
   from search_facets(38.88, -77.1, 10) f);
insert into r select 'facets: cuisines in the chosen type, a kind counted under its parents',
  (select f->'cuisines' = '[{"n":2,"name":"Italian","path":"restaurants.italian"},{"n":1,"name":"Pizza","path":"restaurants.italian.pizza"}]'::jsonb
   from search_facets(38.88, -77.1, 10, 'restaurants') f);
insert into r select 'facets: status counts follow the type',
  (select (f->>'favorites')::int = 1 and (f->>'friends')::int = 1 and (f->>'want')::int = 0 and (f->>'hidden')::int = 1
   from search_facets(38.88, -77.1, 10, 'restaurants') f);
insert into r select 'facets: type counts ignore the chosen type and cuisine',
  (select (f->'types'->>'all')::int = 4 and (f->>'friends')::int = 0
   from search_facets(38.88, -77.1, 10, 'restaurants', 'restaurants.italian.pizza') f);
insert into r select 'facets: type counts follow the Friends filter; its own count does not',
  (select f->'types' = '{"all":2,"restaurants":1,"drinks":1}'::jsonb and (f->>'friends')::int = 2
   from search_facets(38.88, -77.1, 10, null, null, null, false, true) f);
insert into r select 'facets: hidden is 0 while hidden places are shown',
  (select (f->>'hidden')::int = 0 and (f->'types'->>'all')::int = 5
   from search_facets(38.88, -77.1, 10, null, null, null, false, false, false, true) f);
insert into r select 'facets: name search narrows every count',
  (select (f->'types'->>'all')::int = 1 and (f->>'favorites')::int = 1 from search_facets(38.88, -77.1, 10, null, null, 'pizza') f);

-- ------------------------------------------------------------ suggest_what
insert into r select 'kinds: "ita" suggests Italian, with its type',
  (select count(*) = 1 and bool_and(label = 'Italian' and path = 'restaurants.italian' and type_key = 'restaurants')
   from suggest_what('ita', 38.88, -77.1) where kind = 'kind');
insert into r select 'kinds: whole-name starts first, broader kinds first, at most 4',
  (select array_agg(label order by ord) = array['Bar','Barbecue','Bar and Grill','Beer Bar and Beer Garden']
   from (select label, row_number() over () ord from suggest_what('bar', 38.88, -77.1) where kind = 'kind') x);
insert into r select 'kinds come before places',
  (select array_agg(kind order by ord) = array['kind','place']
   from (select kind, row_number() over () ord from suggest_what('pizz', 38.88, -77.1)) x);
insert into r select 'places: name contains the text, nearest first, with distance and type',
  (select array_agg(label order by ord) = array['Alpha Pizza'] and bool_and(miles is not null and place_id = pid('Alpha Pizza') and type_key = 'restaurants')
   from (select label, miles, place_id, type_key, row_number() over () ord from suggest_what('alpha', 38.88, -77.1) where kind = 'place') x);
insert into r select 'places: several matches come nearest first',
  (select array_agg(label order by ord) = array['Alpha Pizza','Bella Italia']
   from (select label, row_number() over () ord from suggest_what('al', 38.88, -77.1) where kind = 'place') x);
insert into r select 'places beyond 25 miles are not suggested',
  (select count(*) = 0 from suggest_what('sushi', 38.88, -77.1) where kind = 'place');
insert into r select 'a hidden place is not suggested to the person who hid it',
  (select count(*) = 0 from suggest_what('hidden gem', 38.88, -77.1) where kind = 'place');
select set_config('request.jwt.claim.sub', '', false) \gset
insert into r select '...but is to a visitor',
  (select count(*) = 1 from suggest_what('hidden gem', 38.88, -77.1) where kind = 'place');
insert into r select 'without a point: kinds, no places',
  (select count(*) filter (where kind = 'place') = 0 and count(*) > 0 from suggest_what('ita'));
insert into r select 'one character suggests nothing',
  (select count(*) = 0 from suggest_what('i', 38.88, -77.1));

-- ------------------------------------------------------------ grants
insert into r select 'API roles can call the three functions, PUBLIC cannot',
  has_function_privilege('anon', 'search_places(double precision,double precision,double precision,ltree,text,boolean,boolean,boolean,boolean)', 'execute')
  and has_function_privilege('authenticated', 'search_facets(double precision,double precision,double precision,text,ltree,text,boolean,boolean,boolean,boolean)', 'execute')
  and has_function_privilege('anon', 'suggest_what(text,double precision,double precision)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.proname in ('search_places', 'search_facets', 'suggest_what')
                    and a.grantee = 0 and a.privilege_type = 'EXECUTE');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
