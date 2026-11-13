-- Scenario checks for searching the map area (20261112020000_map_area.sql): the box's edges,
-- boxes refused, the bubbles' counts and how wide the map opens around a point.
-- Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);

-- u1 searches; u2 is u1's friend.
insert into auth.users(id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle":"u1"}'),
  ('22222222-2222-2222-2222-222222222222', '{"handle":"u2"}');
insert into friendships(requester_id, addressee_id, status) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted');

-- The box used below: west -77.2, south 38.8, east -77.0, north 39.0.
create temp table p(name text, lng float, lat float, main text);
insert into p values
  ('NW corner',          -77.199, 38.999, 'restaurants'),
  ('On the east edge',   -77.0,   38.9,   'coffee'),
  ('Just west of it',    -77.2001, 38.9,  'restaurants'),
  ('Just north of it',   -77.1,   39.0001, 'restaurants'),
  ('A1 fav and friend',  -77.131, 38.871, 'restaurants'),
  ('A2 friend',          -77.132, 38.872, 'restaurants'),
  ('A3 friend and want', -77.133, 38.873, 'drinks'),
  ('A4 plain',           -77.134, 38.874, 'restaurants'),
  ('B1 want',            -77.031, 38.971, 'coffee'),
  ('B2 plain',           -77.032, 38.972, 'markets'),
  ('Far away',           -80.0,   35.0,   'restaurants');
insert into entities(name, location, main_category_id, status)
select p.name, ('SRID=4326;POINT(' || p.lng || ' ' || p.lat || ')')::extensions.geography,
       (select id from categories where path = p.main::ltree), 'active'
from p;
create function pid(n text) returns uuid language sql as $$ select id from entities where name = n $$;

insert into stars(user_id, entity_id) values
  ('11111111-1111-1111-1111-111111111111', pid('A1 fav and friend')),
  ('22222222-2222-2222-2222-222222222222', pid('A1 fav and friend')),
  ('22222222-2222-2222-2222-222222222222', pid('A2 friend')),
  ('22222222-2222-2222-2222-222222222222', pid('A3 friend and want'));
insert into lists(id, owner_id, name, is_default_list) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Want to try', true);
insert into list_items(list_id, entity_id) values
  ('aaaaaaaa-0000-0000-0000-000000000001', pid('A3 friend and want')),
  ('aaaaaaaa-0000-0000-0000-000000000001', pid('B1 want'));

create function names(rows text[]) returns text language sql as $$ select array_to_string(array(select unnest(rows) order by 1), ',') $$;
-- True when the statement fails with a message containing the given words.
create function fails_with(stmt text, words text) returns boolean language plpgsql as $$
begin
  execute stmt;
  return false;
exception when others then
  return sqlerrm like '%' || words || '%';
end $$;

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \gset

-- ------------------------------------------------------------ the box
insert into r select 'box: places inside it, the edges included; just outside left out',
  (select names(array_agg(name)) = 'A1 fav and friend,A2 friend,A3 friend and want,A4 plain,B1 want,B2 plain,NW corner,On the east edge'
          and bool_and(total_count = 8)
   from search_area(38.9, -77.1, -77.2, 38.8, -77.0, 39.0));
insert into r select 'box: nearest to the point first',
  (select array_agg(name order by ordinality)::text[] = array['On the east edge']
   from search_area(38.9, -77.0, -77.2, 38.8, -77.0, 39.0) with ordinality where ordinality = 1);
insert into r select 'box: the point can be outside it (distances still from the point)',
  (select count(*) = 2 and min(miles) > 5
   from search_area(38.0, -77.1, -77.04, 38.95, -77.02, 38.98));
insert into r select 'box: filters work as before (Want to try)',
  (select names(array_agg(name)) = 'A3 friend and want,B1 want'
   from search_area(38.9, -77.1, -77.2, 38.8, -77.0, 39.0, null, null, false, false, true));
insert into r select 'box: a kind',
  (select names(array_agg(name)) = 'B1 want,On the east edge'
   from search_area(38.9, -77.1, -77.2, 38.8, -77.0, 39.0, 'coffee'));
insert into r select 'box: edges out of order are refused',
  fails_with($$select * from search_area(38.9, -77.1, -77.0, 38.8, -77.2, 39.0)$$, 'not a box');
insert into r select 'box: a box taller than 1.2 degrees is refused',
  fails_with($$select * from search_area(38.9, -77.1, -77.2, 38.0, -77.0, 39.3)$$, 'too large');
insert into r select 'box: a box wider than 2.5 degrees is refused',
  fails_with($$select * from search_area(38.9, -77.1, -79.0, 38.8, -76.4, 39.0)$$, 'too large');
insert into r select 'box: the filter counts refuse it too',
  fails_with($$select area_facets(-79.0, 38.8, -76.4, 39.0)$$, 'too large');
insert into r select 'box: the counts cover the box',
  (select f->'types' = '{"all":8,"restaurants":4,"drinks":1,"coffee":2,"markets":1}'::jsonb
   from area_facets(-77.2, 38.8, -77.0, 39.0) f);

-- ------------------------------------------------------------ bubbles
-- 0.1-degree squares: the A places share one, the B places another, the other two one each.
create temp table c as select * from area_cells(-77.2, 38.8, -77.0, 39.0, 0.1, 0.1);
insert into r select 'cells: every place counted once, biggest square first',
  (select sum(n) = 8 and count(*) = 4 from c)
  and (select n = 4 from c limit 1);
insert into r select 'cells: each place by its first mark (own favorite, friends'', Want to try)',
  (select fav = 1 and friend = 2 and want = 0 from c where n = 4)
  and (select fav = 0 and friend = 0 and want = 1 from c where n = 2);
insert into r select 'cells: where a square''s places are, and their extent',
  (select abs(lat - 38.8725) < 0.0001 and abs(lng + 77.1325) < 0.0001
          and abs(cell_west + 77.134) < 1e-9 and abs(cell_east + 77.131) < 1e-9
          and abs(cell_south - 38.871) < 1e-9 and abs(cell_north - 38.874) < 1e-9
   from c where n = 4);
insert into r select 'cells: the same filters as the list (Favorites only)',
  (select count(*) = 1 and sum(n) = 1 and sum(fav) = 1
   from area_cells(-77.2, 38.8, -77.0, 39.0, 0.1, 0.1, null, null, true));
insert into r select 'cells: squares no smaller than a 200th of the box',
  (select sum(n) = 8 and count(*) <= 8 from area_cells(-77.2, 38.8, -77.0, 39.0, 0, 0));
insert into r select 'cells: a box too large is refused',
  fails_with($$select * from area_cells(-79.0, 38.8, -76.4, 39.0, 0.1, 0.1)$$, 'too large');
select set_config('request.jwt.claim.sub', '', false) \gset
insert into r select 'cells: a visitor sees counts with no marks',
  (select sum(n) = 8 and sum(fav + friend + want) = 0 from area_cells(-77.2, 38.8, -77.0, 39.0, 0.1, 0.1));
insert into r select 'cells: a visitor''s Favorites filter shows nothing',
  (select count(*) = 0 from area_cells(-77.2, 38.8, -77.0, 39.0, 0.1, 0.1, null, null, true));

-- ------------------------------------------------------------ how wide the map opens
insert into r select 'start: far enough for the n-th nearest place',
  (select abs(start_area(38.871, -77.131, 0, 5) -
              (select round((st_distance(location, 'SRID=4326;POINT(-77.131 38.871)'::extensions.geography) / 1609.34)::numeric, 2)
               from entities order by location <-> 'SRID=4326;POINT(-77.131 38.871)'::extensions.geography offset 4 limit 1)) < 0.01)
  and (select start_area(38.871, -77.131, 0, 5) > 4);
insert into r select 'start: at least a third of a mile',
  (select start_area(38.871, -77.131, 0, 1) = 0.33);
insert into r select 'start: at least the radius asked for (a town''s own size)',
  (select start_area(38.871, -77.131, 6.5, 4) = 6.5);
insert into r select 'start: at most 25 miles, even when the places are far',
  (select start_area(30.0, -90.0, 0, 3) = 25);
insert into r select 'start: a point off the map gives nothing',
  (select start_area(120, -77.1) is null);

-- ------------------------------------------------------------ grants
insert into r select 'API roles can call search_area, area_facets, area_cells and start_area; PUBLIC cannot',
  has_function_privilege('anon', 'search_area(double precision,double precision,double precision,double precision,double precision,double precision,ltree,text,boolean,boolean,boolean,boolean)', 'execute')
  and has_function_privilege('anon', 'area_cells(double precision,double precision,double precision,double precision,double precision,double precision,ltree,text,boolean,boolean,boolean,boolean)', 'execute')
  and has_function_privilege('authenticated', 'start_area(double precision,double precision,double precision,integer)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.proname in ('search_area', 'area_facets', 'area_cells', 'start_area')
                    and a.grantee = 0 and a.privilege_type = 'EXECUTE');
insert into r select 'the shared pieces (which take the viewer as an argument) are not callable through the API',
  not has_function_privilege('anon', 'area_matches(double precision,double precision,double precision,double precision,ltree,text,boolean,boolean,boolean,boolean,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'area_matches(double precision,double precision,double precision,double precision,ltree,text,boolean,boolean,boolean,boolean,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'area_box(double precision,double precision,double precision,double precision)', 'execute');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
