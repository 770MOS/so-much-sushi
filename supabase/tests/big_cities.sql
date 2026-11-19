-- Scenario checks for big cities opening on their busiest area (20261119000000_big_cities.sql):
-- refresh_locality_focus, the focus as a town's point in suggest_localities, and the 5-mile
-- cap on a town's own size in start_area.
-- Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);

create function kid(n text) returns uuid language sql as $$ select id from categories where name = n $$;
create function pt(lat float, lng float) returns extensions.geography language sql as $$
  select extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography $$;
create function miles(a extensions.geography, b extensions.geography) returns float language sql as $$
  select extensions.st_distance(a, b) / 1609.34 $$;

-- Bigtown, TX: about 10 miles in radius; its middle at (30.00, -97.00), its busy downtown 4
-- miles north-east at (30.04, -96.96). Nexttown, TX lies 6 miles west, inside Bigtown's circle,
-- and is busier still, but its places don't count for Bigtown. Smallville, TX: 2 miles in
-- radius (too small for a focus). Quiettown, TX: big, but only 5 places.
insert into localities(kind, code, name, state, label, city, population, location, land_sq_m, source) values
  ('place', '4800001', 'Bigtown', 'TX', 'Bigtown, TX', 'Bigtown', 900000, pt(30.00, -97.00), (pi() * (10 * 1609.34) ^ 2)::bigint, 'test'),
  ('place', '4800002', 'Smallville', 'TX', 'Smallville, TX', 'Smallville', 5000, pt(31.00, -97.00), (pi() * (2 * 1609.34) ^ 2)::bigint, 'test'),
  ('place', '4800003', 'Quiettown', 'TX', 'Quiettown, TX', 'Quiettown', 9000, pt(32.00, -97.00), (pi() * (8 * 1609.34) ^ 2)::bigint, 'test');
insert into locality_names(locality_id, name, with_state)
select id, lower(name), false from localities where code like '48000%'
union all select id, lower(name) || ' tx', true from localities where code like '48000%';

insert into entities(name, location, main_category_id, status, city, state)
-- 40 open places downtown (and 10 closed ones, which don't count)
select 'Downtown ' || g, pt(30.04 + (g % 5) * 0.001, -96.96 + (g % 7) * 0.001), kid('Restaurants'),
       case when g > 40 then 'permanently_closed' else 'active' end, 'Bigtown', 'TX'
from generate_series(1, 50) g
union all
-- 12 scattered elsewhere in Bigtown
select 'Bigtown ' || g, pt(29.95 + g * 0.004, -97.05 + g * 0.003), kid('Restaurants'), 'active', 'bigtown', 'TX'
from generate_series(1, 12) g
union all
-- 80 in Nexttown, inside Bigtown's circle
select 'Nexttown ' || g, pt(30.00 + (g % 4) * 0.001, -97.10 + (g % 9) * 0.001), kid('Restaurants'), 'active', 'Nexttown', 'TX'
from generate_series(1, 80) g
union all
-- Smallville: 30 places; Quiettown: 5
select 'Smallville ' || g, pt(31.00 + g * 0.0005, -97.00), kid('Restaurants'), 'active', 'Smallville', 'TX' from generate_series(1, 30) g
union all
select 'Quiettown ' || g, pt(32.00 + g * 0.001, -97.00), kid('Restaurants'), 'active', 'Quiettown', 'TX' from generate_series(1, 5) g;

create temp table refreshed as select refresh_locality_focus() as n;

insert into r select 'focus: a big town''s busiest spot among its own addresses (not its middle, not the busier town next door)',
  (select focus is not null and miles(focus, pt(30.042, -96.957)) < 0.5 from localities where code = '4800001');
insert into r select 'focus: none for a small town or a big town with few places; one town set in all',
  (select bool_and(focus is null) from localities where code in ('4800002', '4800003'))
  and (select n = 1 from refreshed);
update localities set focus = pt(31.5, -97.5) where code = '4800002';
create temp table again as select refresh_locality_focus() as n;
insert into r select 'focus: worked out again from scratch (an old focus that no longer qualifies is cleared)',
  (select focus is null from localities where code = '4800002')
  and (select focus is not null from localities where code = '4800001')
  and (select n = 1 from again);

-- suggest_localities hands back the focus as the point; other towns keep their own point.
insert into r select 'suggestions: a big town''s point is its busiest spot',
  (select miles(pt(lat, lng), pt(30.042, -96.957)) < 0.5 and radius_miles = 10
   from suggest_localities('bigtown', null, null, 1));
insert into r select 'suggestions: a town without a focus keeps its own point',
  (select lat = 31.00 and lng = -97.00 from suggest_localities('smallville', null, null, 1));

-- start_area: a town's own size counts up to 5 miles.
insert into r select 'start: a town''s own size counts up to 5 miles (10 across)',
  start_area(30.042, -96.957, 10, 10) = 5 and start_area(30.042, -96.957, 3, 10) = 3;

insert into r select 'refresh_locality_focus is for the service role only',
  not has_function_privilege('anon', 'refresh_locality_focus()', 'execute')
  and not has_function_privilege('authenticated', 'refresh_locality_focus()', 'execute')
  and has_function_privilege('service_role', 'refresh_locality_focus()', 'execute');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
