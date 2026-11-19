-- Scenario checks for the search fixes (20261116000000_search_fixes.sql): typed text finds
-- kinds as well as names, in the results, the bubbles and the filter counts; start_area's
-- answers unchanged (map_area.sql checks them too).
-- Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);

create function kid(n text) returns uuid language sql as $$ select id from categories where name = n $$;
-- The kinds kinds_for_text finds for a text, broadest only (finer kinds under them left out).
create function kinds(t text) returns text language sql as $$
  select coalesce(string_agg(c.name, ', ' order by c.name), '')
  from categories c
  where c.id = any (kinds_for_text(t))
    and not exists (select 1 from categories p
                    where p.id = any (kinds_for_text(t)) and c.path <@ p.path and p.path <> c.path)
$$;

-- ------------------------------------------------------------ which kinds a text names
insert into r select 'kinds: "pizza", "Pizza" and "pizzas" are Pizza',
  kinds('pizza') = 'Pizza' and kinds('Pizza') = 'Pizza' and kinds('pizzas') = 'Pizza';
insert into r select 'kinds: a kind with exactly that name wins ("bar" is Bar with its finer kinds, not Bar and Grill or Barbecue)',
  kinds('bar') = 'Bar' and kinds('bars') = 'Bar'
  and kid('Sports Bar') = any (kinds_for_text('bar'))
  and not kid('Bar and Grill') = any (kinds_for_text('bar'))
  and not kid('Barbecue') = any (kinds_for_text('bar'));
insert into r select 'kinds: word endings don''t matter ("bakeries" is Bakery, not all of Bakeries and Markets)',
  kinds('bakeries') = 'Bakery' and not kid('Butcher') = any (kinds_for_text('bakeries'));
insert into r select 'kinds: words inside a longer name ("ice cream", "brunch", "smoothie")',
  kinds('ice cream') = 'Ice Cream and Frozen Desserts' and kinds('brunch') = 'Breakfast and Brunch'
  and kinds('smoothie') = 'Juice and Smoothies';
insert into r select 'kinds: a trailing "restaurant", "food" or "shop" is dropped when nothing matches with it',
  kinds('thai restaurant') = 'Thai' and kinds('italian food') = 'Italian' and kinds('coffee shop') = 'Coffee'
  and kinds('fast food') = 'Fast Food';
insert into r select 'kinds: "bbq" and "doughnuts" count as Barbecue and Donuts; "tex mex" is Tex-Mex',
  kinds('bbq') = 'Barbecue' and kinds('doughnuts') = 'Donuts' and kinds('tex mex') = 'Tex-Mex';
insert into r select 'kinds: a broad kind includes its finer kinds (Asian includes Sushi)',
  kid('Sushi') = any (kinds_for_text('asian'));
insert into r select 'kinds: none for short text, little words, "food" alone or a name',
  kinds('pi') = '' and kinds('the') = '' and kinds('food') = '' and kinds('Pupatella') = ''
  and kinds(null) = '' and kinds('   ') = '';

-- ------------------------------------------------------------ searches
-- Inside the box west -77.2, south 38.8, east -77.0, north 39.0.
insert into entities(name, location, main_category_id, status) values
  ('Joe''s Pizza',  'SRID=4326;POINT(-77.10 38.90)', kid('Restaurants'), 'active'),
  ('Pupatella',     'SRID=4326;POINT(-77.11 38.91)', kid('Restaurants'), 'active'),
  ('Two Amys',      'SRID=4326;POINT(-77.12 38.92)', kid('Restaurants'), 'active'),
  ('Thai Spot',     'SRID=4326;POINT(-77.13 38.93)', kid('Restaurants'), 'active'),
  ('Bean There',    'SRID=4326;POINT(-77.15 38.95)', kid('Coffee'), 'active'),
  ('Old Pizza Co',  'SRID=4326;POINT(-77.14 38.94)', kid('Restaurants'), 'permanently_closed'),
  ('Far Pizza',     'SRID=4326;POINT(-80.00 35.00)', kid('Restaurants'), 'active');
-- Finer kinds are tags (a place's main kind is always a top-level one).
insert into entity_categories(entity_id, category_id)
select e.id, kid(t.kind) from entities e join (values
  ('Pupatella', 'Pizza'), ('Two Amys', 'Italian'), ('Two Amys', 'Pizza'), ('Thai Spot', 'Thai'),
  ('Old Pizza Co', 'Pizza'), ('Far Pizza', 'Pizza')) t(name, kind) on t.name = e.name;

create function names(rows text[]) returns text language sql as $$ select array_to_string(array(select unnest(rows) order by 1), ',') $$;

insert into r select 'search: "pizza" finds the name and the Pizza tag; not closed places, places outside the box or other kinds',
  (select names(array_agg(name)) = 'Joe''s Pizza,Pupatella,Two Amys' and bool_and(total_count = 3)
   from search_area(38.9, -77.1, -77.2, 38.8, -77.0, 39.0, null, 'pizza'));
insert into r select 'search: a name that isn''t a kind still finds just that name',
  (select names(array_agg(name)) = 'Pupatella' from search_area(38.9, -77.1, -77.2, 38.8, -77.0, 39.0, null, 'Pupa'));
insert into r select 'search: a main kind ("coffee"), and "thai restaurant" finds Thai places',
  (select names(array_agg(name)) = 'Bean There' from search_area(38.9, -77.1, -77.2, 38.8, -77.0, 39.0, null, 'coffee'))
  and (select names(array_agg(name)) = 'Thai Spot' from search_area(38.9, -77.1, -77.2, 38.8, -77.0, 39.0, null, 'thai restaurant'));
insert into r select 'search: typed text and a chosen kind together',
  (select names(array_agg(name)) = 'Two Amys'
   from search_area(38.9, -77.1, -77.2, 38.8, -77.0, 39.0, 'restaurants.italian', 'amys'));
insert into r select 'bubbles: area_cells counts the same places',
  (select sum(n) = 3 from area_cells(-77.2, 38.8, -77.0, 39.0, 0, 0, null, 'pizza'));
insert into r select 'filter counts: area_facets counts the same places',
  (select (area_facets(-77.2, 38.8, -77.0, 39.0, null, null, 'pizza') -> 'types' ->> 'all')::int = 3);

-- ------------------------------------------------------------ start_area
insert into r select 'start_area: the n-th nearest open place, as before (closed places skipped)',
  (select start_area(38.90, -77.10, 0, 4)
          = round((ST_Distance('SRID=4326;POINT(-77.10 38.90)'::geography,
                               'SRID=4326;POINT(-77.13 38.93)'::geography) / 1609.34)::numeric, 2)::float);
insert into r select 'start_area: limits as before (at least 1/3 mile, at most 25, the given radius, null off the map)',
  start_area(38.90, -77.10, 0, 1) = 0.33 and start_area(30.0, -90.0, 0, 6) = 25
  and start_area(38.90, -77.10, 4.5, 1) = 4.5 and start_area(95, 0) is null and start_area(null, 0) is null;

insert into r select 'kinds_for_text is internal; start_area is still open to the API roles',
  not has_function_privilege('anon', 'kinds_for_text(text)', 'execute')
  and not has_function_privilege('authenticated', 'kinds_for_text(text)', 'execute')
  and has_function_privilege('anon', 'start_area(double precision,double precision,double precision,integer)', 'execute')
  and has_function_privilege('authenticated', 'start_area(double precision,double precision,double precision,integer)', 'execute');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
