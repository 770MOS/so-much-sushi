-- Scenario checks for advanced search (20261121000000_advanced_filters.sql): the `more` filters
-- in the results, the bubbles and the counts; chains; streets; drawn areas; close spellings.
-- Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);

-- u1 searches; u2 is someone else.
insert into auth.users(id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle":"u1"}'),
  ('22222222-2222-2222-2222-222222222222', '{"handle":"u2"}');

create function kid(n text) returns uuid language sql as $$ select id from categories where name = n $$;
create function kpath(n text) returns text language sql as $$ select path::text from categories where name = n $$;

-- Inside the box west -77.2, south 38.8, east -77.0, north 39.0 (like Wilson Blvd in Arlington).
create temp table p(name text, lng float, lat float, main text, tag text, address text, website text,
                    phone text, status text);
insert into p values
  ('Rien Tong Thai',           -77.100, 38.900, 'Restaurants', 'Thai',       '3131 Wilson Blvd',                 'https://rientong.example', '7035550101', 'active'),
  ('Minh''s',                  -77.090, 38.900, 'Restaurants', 'Vietnamese', '2500 Wilson Boulevard, Suite 2',   null,                       '7035550102', 'active'),
  ('Pho 75',                   -77.080, 38.900, 'Restaurants', 'Vietnamese', '1721 Wilson Blvd',                 'https://pho75.example',    '7035550103', 'active'),
  ('Sala Thai',                -77.110, 38.910, 'Restaurants', 'Thai',       '2900 10th St N',                   'https://salathai.example', null,         'active'),
  ('Sawatdee Thai Restaurant', -77.120, 38.910, 'Restaurants', 'Thai',       '2250 Clarendon Blvd',              'https://sawatdee.example', '7035550105', 'active'),
  ('Silver Diner',             -77.104, 38.904, 'Restaurants', 'Diner',      '3200 Wilson Blvd',                 null,                       null,         'permanently_closed'),
  ('Gone For Good',            -77.103, 38.903, 'Restaurants', 'Thai',       '3100 Wilson Blvd',                 null,                       null,         'removed'),
  ('Mcdonalds',                -77.050, 38.950, 'Restaurants', null,         '1500 N Glebe Road',                'https://mcd.example',      '7035550108', 'active'),
  ('Wilson Tavern',            -77.060, 38.950, 'Drinks',      null,         '2915 Wilson Blvd',                 null,                       '7035550109', 'active');
insert into entities(name, location, main_category_id, status, address, website, phone, city, state)
select p.name, ('SRID=4326;POINT(' || p.lng || ' ' || p.lat || ')')::extensions.geography, kid(p.main), p.status,
       p.address, p.website, p.phone, 'Arlington', 'VA'
from p;
insert into entity_categories(entity_id, category_id)
select e.id, kid(p.tag) from entities e join p on p.name = e.name where p.tag is not null;

-- Far away: 9 more Pho 75s (10 open in all: a chain), 9 McDonald's written two ways (10 with the
-- one above), and 8 open Sala Thais plus a closed one (9 open: not a chain).
insert into entities(name, location, main_category_id, status)
select n, ('SRID=4326;POINT(' || (-80 - g * 0.01) || ' 35)')::extensions.geography, kid('Restaurants'), s
from (select 'Pho 75' n, g, 'active' s from generate_series(1, 9) g
      union all select case when g % 2 = 0 then 'McDonald''s' else 'MCDONALD’S' end, g + 20, 'active' from generate_series(1, 9) g
      union all select 'Sala Thai', g + 40, 'active' from generate_series(1, 8) g
      union all select 'Sala Thai', 49, 'permanently_closed') t;

create function pid(n text) returns uuid language sql as $$ select id from entities where name = n and address is not null $$;
create function names(rows text[]) returns text language sql as $$ select array_to_string(array(select unnest(rows) order by 1), ',') $$;
create function fails_with(stmt text, words text) returns boolean language plpgsql as $$
begin
  execute stmt;
  return false;
exception when others then
  return sqlerrm like '%' || words || '%';
end $$;
-- The places search_area finds in the box for u1, by name.
create function found(more jsonb, q text default null, kind text default null) returns text language sql as $$
  select coalesce(names(array_agg(name)), '')
  from search_area(38.9, -77.1, -77.2, 38.8, -77.0, 39.0, kind::ltree, q, false, false, false, false, more)
$$;

-- Lists: u1's "Thai night" (Rien Tong, Sala Thai); u2's own list (Pho 75).
insert into lists(id, owner_id, name) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Thai night'),
  ('bbbbbbbb-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Pho');
insert into list_items(list_id, entity_id) values
  ('bbbbbbbb-0000-0000-0000-000000000001', pid('Rien Tong Thai')),
  ('bbbbbbbb-0000-0000-0000-000000000001', pid('Sala Thai')),
  ('bbbbbbbb-0000-0000-0000-000000000002', pid('Pho 75'));

select public.refresh_chain_names() \gset
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \gset

-- ------------------------------------------------------------ the pieces
insert into r select 'street_key: house numbers, units and spellings don''t matter',
  street_key('2500 Wilson Boulevard, Suite 2') = 'wilson blvd' and street_key('4238 Wilson Blvd Ste 138') = 'wilson blvd'
  and street_key('305 North Glebe Road') = 'n glebe rd' and street_key('1800 N Lynn St #102, Inside Happy Eatery') = 'n lynn st'
  and street_key('2424 Wilson Blvd  Ste A') = 'wilson blvd' and street_key('2900 10th St N') = '10th st n'
  and street_key(null) is null and street_key('123') is null and street_key('') is null;
insert into r select 'chain_key: case, apostrophes and punctuation don''t matter',
  chain_key('McDonald''s') = 'mcdonalds' and chain_key('MCDONALD’S') = 'mcdonalds' and chain_key('Mcdonalds') = 'mcdonalds'
  and chain_key('Pho 75') = 'pho 75' and chain_key('  ') is null;
insert into r select 'chains: 10 or more open places with the name; closed places don''t count',
  exists (select 1 from chain_names where name_key = 'pho 75' and places = 10)
  and exists (select 1 from chain_names where name_key = 'mcdonalds' and places = 10)
  and not exists (select 1 from chain_names where name_key = 'sala thai');

-- ------------------------------------------------------------ results
insert into r select 'no `more`: as before (open places only)',
  found('{}') = 'Mcdonalds,Minh''s,Pho 75,Rien Tong Thai,Sala Thai,Sawatdee Thai Restaurant,Wilson Tavern'
  and found(null) = found('{}');
insert into r select 'cuisines: any of several',
  found(jsonb_build_object('cuisines', jsonb_build_array(kpath('Thai'), kpath('Vietnamese'))))
    = 'Minh''s,Pho 75,Rien Tong Thai,Sala Thai,Sawatdee Thai Restaurant'
  and found(jsonb_build_object('cuisines', jsonb_build_array(kpath('Vietnamese')))) = 'Minh''s,Pho 75';
insert into r select 'cuisines: with a type (Bars & drinks has none of them)',
  found(jsonb_build_object('cuisines', jsonb_build_array(kpath('Thai'))), null, 'drinks') = '';
insert into r select 'street: however it''s written, and by its start',
  found('{"street": "Wilson Boulevard"}') = 'Minh''s,Pho 75,Rien Tong Thai,Wilson Tavern'
  and found('{"street": "wilson"}') = found('{"street": "Wilson Blvd"}')
  and found('{"street": "N Glebe Rd"}') = 'Mcdonalds'
  and found('{"street": "elm"}') = '';
insert into r select 'chain or independent',
  found('{"chain": "chain"}') = 'Mcdonalds,Pho 75'
  and found('{"chain": "independent"}') = 'Minh''s,Rien Tong Thai,Sala Thai,Sawatdee Thai Restaurant,Wilson Tavern';
insert into r select 'has a website / a phone number',
  found('{"website": true}') = 'Mcdonalds,Pho 75,Rien Tong Thai,Sala Thai,Sawatdee Thai Restaurant'
  and found('{"phone": true}') = 'Mcdonalds,Minh''s,Pho 75,Rien Tong Thai,Sawatdee Thai Restaurant,Wilson Tavern'
  and found('{"website": true, "phone": true}') = 'Mcdonalds,Pho 75,Rien Tong Thai,Sawatdee Thai Restaurant';
insert into r select 'closed places only when asked for; removed ones never',
  found('{"closed": true, "street": "wilson"}') = 'Minh''s,Pho 75,Rien Tong Thai,Silver Diner,Wilson Tavern'
  and found('{"street": "wilson"}') not like '%Silver Diner%';
insert into r select 'one of your lists; someone else''s list finds nothing',
  found('{"list": "bbbbbbbb-0000-0000-0000-000000000001"}') = 'Rien Tong Thai,Sala Thai'
  and found('{"list": "bbbbbbbb-0000-0000-0000-000000000002"}') = '';
insert into r select 'close spellings: only when asked for, and only names close enough',
  found('{}', 'sawasdee thai') = ''
  and found('{"close": true}', 'sawasdee thai') = 'Sawatdee Thai Restaurant'
  and found('{"close": true}', 'sala') = 'Sala Thai';
insert into r select 'drawn area: places inside the shape only (the box can be larger)',
  found('{"area": [[-77.105, 38.895], [-77.085, 38.895], [-77.085, 38.905], [-77.105, 38.905]]}') = 'Minh''s,Rien Tong Thai'
  and found('{"area": [[-77.105, 38.895], [-77.085, 38.895], [-77.085, 38.905], [-77.105, 38.905]], "closed": true}')
      = 'Minh''s,Rien Tong Thai,Silver Diner';
insert into r select 'drawn area: a line that crosses itself still works',
  found('{"area": [[-77.105, 38.895], [-77.085, 38.905], [-77.085, 38.895], [-77.105, 38.905]]}') <> 'x';
insert into r select 'drawn area: refused with too few points, or points off the map',
  fails_with($q$select found('{"area": [[-77.1, 38.9], [-77.0, 38.9]]}')$q$, '3 to 100 points')
  and fails_with($q$select found('{"area": [[-77.1, 38.9], [-77.0, 98.9], [-77.0, 38.8]]}')$q$, 'longitude, latitude')
  and fails_with($q$select found('{"area": "here"}')$q$, 'list of points');
insert into r select 'bad `more` refused',
  fails_with($q$select found('[]')$q$, 'set of filters')
  and fails_with($q$select found('{"chain": "big"}')$q$, 'chain or independent');
insert into r select 'filters add up',
  found(jsonb_build_object('cuisines', jsonb_build_array(kpath('Thai'), kpath('Vietnamese')),
                           'street', 'wilson', 'chain', 'independent')) = 'Minh''s,Rien Tong Thai';
insert into r select 'total_count matches the rows',
  (select bool_and(total_count = 2) and count(*) = 2
   from search_area(38.9, -77.1, -77.2, 38.8, -77.0, 39.0, null, null, false, false, false, false,
                    jsonb_build_object('cuisines', jsonb_build_array(kpath('Thai'), kpath('Vietnamese')),
                                       'street', 'wilson', 'chain', 'independent')));

-- ------------------------------------------------------------ bubbles
insert into r select 'bubbles count the same places as the list',
  (select sum(n) from area_cells(-77.2, 38.8, -77.0, 39.0, 0.001, 0.001, null, null, false, false, false, false,
                                 '{"street": "wilson", "closed": true}')) = 5
  and (select sum(n) from area_cells(-77.2, 38.8, -77.0, 39.0, 0.001, 0.001)) = 7;

-- ------------------------------------------------------------ counts
create temp table f as
select area_facets(-77.2, 38.8, -77.0, 39.0, 'restaurants', null, null, false, false, false, false,
                   jsonb_build_object('cuisines', jsonb_build_array(kpath('Thai'), kpath('Vietnamese')),
                                      'street', 'wilson', 'chain', 'independent', 'counts', true)) j;
insert into r select 'counts: total is every filter at once',
  (select (j ->> 'total')::int = 2 from f);
insert into r select 'counts: chain or independent leaves out its own choice (Thai or Vietnamese on Wilson)',
  (select j -> 'chain' = '{"chain": 1, "independent": 2}'::jsonb from f);
insert into r select 'counts: streets leave out the street (top streets, with a label)',
  (select j -> 'streets' @> '[{"street": "wilson blvd", "label": "Wilson Blvd", "n": 2},
                               {"street": "10th st n", "label": "10th St N", "n": 1},
                               {"street": "clarendon blvd", "label": "Clarendon Blvd", "n": 1}]'::jsonb
          and jsonb_array_length(j -> 'streets') = 3 from f);
insert into r select 'counts: website, phone and closed places with the other filters on',
  (select (j ->> 'website')::int = 1 and (j ->> 'phone')::int = 2 and (j ->> 'closed')::int = 0 from f);
insert into r select 'counts: closed places that would be added',
  (select (area_facets(-77.2, 38.8, -77.0, 39.0, null, null, null, false, false, false, false,
                       '{"street": "wilson", "counts": true}') ->> 'closed')::int = 1);
insert into r select 'counts: the cuisine counts keep the panel''s filters',
  (select j -> 'cuisines' @> '[{"name": "Thai", "n": 1}, {"name": "Vietnamese", "n": 1}]'::jsonb from f);
insert into r select 'counts: without counts, only the usual keys (plus total)',
  (select not (j ? 'streets') and j ? 'total' and (j ->> 'total')::int = 7
   from (select area_facets(-77.2, 38.8, -77.0, 39.0) j) x);
insert into r select 'counts: total agrees with search_area for the same filters',
  (select (area_facets(-77.2, 38.8, -77.0, 39.0, null, null, 'sawasdee thai', false, false, false, false,
                       '{"close": true}') ->> 'total')::int = 1);

-- ------------------------------------------------------------ close spellings in the What box
insert into r select 'What box: close spellings when no name has the text',
  (select array_agg(label order by ordinality) = array['Sawatdee Thai Restaurant'] and bool_and(kind = 'close')
   from suggest_what('sawasdee thai', 38.9, -77.1) with ordinality where kind in ('place', 'close'));
insert into r select 'What box: no close spellings when a name has the text',
  not exists (select 1 from suggest_what('sala', 38.9, -77.1) where kind = 'close')
  and exists (select 1 from suggest_what('sala', 38.9, -77.1) where kind = 'place' and label = 'Sala Thai');

-- ------------------------------------------------------------ access
select set_config('request.jwt.claim.sub', '', false) \gset
insert into r select 'refresh_chain_names is for the service role; chain_names isn''t readable through the API',
  not has_function_privilege('anon', 'refresh_chain_names()', 'execute')
  and not has_function_privilege('authenticated', 'refresh_chain_names()', 'execute')
  and has_function_privilege('service_role', 'refresh_chain_names()', 'execute')
  and not has_table_privilege('anon', 'chain_names', 'select')
  and not has_table_privilege('authenticated', 'chain_names', 'select');
insert into r select 'the helpers aren''t callable through the API',
  not has_function_privilege('authenticated', 'area_options(jsonb,text)', 'execute')
  and not has_function_privilege('anon', 'area_shape(jsonb)', 'execute')
  and not has_function_privilege('anon', 'street_key(text)', 'execute')
  and not has_function_privilege('authenticated', 'chain_key(text)', 'execute');
insert into r select 'API roles can call the new search functions; PUBLIC cannot',
  has_function_privilege('anon', 'area_facets(double precision,double precision,double precision,double precision,text,ltree,text,boolean,boolean,boolean,boolean,jsonb)', 'execute')
  and has_function_privilege('authenticated', 'search_area(double precision,double precision,double precision,double precision,double precision,double precision,ltree,text,boolean,boolean,boolean,boolean,jsonb)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.proname in ('search_area', 'area_facets', 'area_cells', 'refresh_chain_names', 'area_options')
                    and a.grantee = 0 and a.privilege_type = 'EXECUTE');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
