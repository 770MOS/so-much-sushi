-- Scenario checks for location suggestions (20261109000000_localities.sql).
-- Run against a scratch database only: it inserts fixtures shaped like the loader's output
-- (scripts/localities/load_census.py).
\set ON_ERROR_STOP 1
\set QUIET 1
set search_path = public, extensions;
create temp table r(t text, ok boolean);

-- Normalising: how both loaded names and typed text are compared.
insert into r select 'normalise: punctuation, case, spaces',
  locality_normalize('  St. Louis,   MO ') = 'st louis mo';
insert into r select 'normalise: apostrophes dropped', locality_normalize('Coeur d''Alene') = 'coeur dalene';
insert into r select 'normalise: accents removed', locality_normalize('Cañon City') = 'canon city';
insert into r select 'normalise: wildcards cannot get through', locality_normalize('a%b_c') = 'a b c';

-- Fixtures: places (name, state, population, lat, lng) and their names, as the loader writes them.
create temp table fx(code text, name text, state text, pop int, lat float8, lng float8, extra text[]);
insert into fx values
  ('3601000', 'Albany', 'NY', 99224, 42.6664, -73.7987, '{}'),
  ('1301052', 'Albany', 'GA', 69647, 31.5776, -84.1762, '{}'),
  ('1700000', 'Albany Park', 'IL', 50000, 41.97, -87.72, '{}'),
  ('5103000', 'Arlington', 'VA', 238643, 38.8786, -77.1011, '{}'),
  ('4804000', 'Arlington', 'TX', 394266, 32.7007, -97.1247, '{}'),
  ('1150000', 'Washington', 'DC', 689545, 38.9047, -77.0163, '{DC}'),
  ('3651000', 'New York', 'NY', 8804190, 40.6635, -73.9387, '{NYC,New York City}'),
  ('2965000', 'St. Louis', 'MO', 301578, 38.6358, -90.2451, '{Saint Louis}'),
  ('2758000', 'St. Paul', 'MN', 311527, 44.9489, -93.1039, '{Saint Paul}'),
  ('3512150', 'Cañon City', 'NM', 1000, 35.0, -106.0, '{}');
insert into localities(kind, code, name, state, label, city, population, location, source)
select 'place', code, name, state, name || ', ' || state, name, pop,
       ('SRID=4326;POINT(' || lng || ' ' || lat || ')')::geography, 'test' from fx;
insert into locality_names(locality_id, name, with_state)
select l.id, v.n, v.w
from fx join localities l on l.code = fx.code
cross join lateral (
  select b, false from unnest(array[fx.name] || fx.extra) b
  union select b || ' ' || fx.state, true from unnest(array[fx.name] || fx.extra) b
  union select b || ' ' || s.full_name, true from unnest(array[fx.name] || fx.extra) b,
        (values ('NY','New York'),('GA','Georgia'),('IL','Illinois'),('VA','Virginia'),('TX','Texas'),
                ('DC','District of Columbia'),('MO','Missouri'),('MN','Minnesota'),('NM','New Mexico')) s(code, full_name)
        where s.code = fx.state
) v(n, w);
insert into localities(kind, code, name, state, label, detail, city, location, source) values
  ('zip', '22201', '22201', 'VA', '22201', 'Arlington, VA', 'Arlington', 'SRID=4326;POINT(-77.093 38.887)', 'test'),
  ('zip', '22202', '22202', 'VA', '22202', 'Arlington, VA', 'Arlington', 'SRID=4326;POINT(-77.051 38.857)', 'test'),
  ('zip', '10001', '10001', 'NY', '10001', 'New York, NY', 'New York', 'SRID=4326;POINT(-73.997 40.751)', 'test');

-- From Washington, DC (38.9, -77.04) unless noted.
insert into r select 'exact name before "starts with"',
  (select array_agg(label) from suggest_localities('albany', 38.9, -77.04)) = array['Albany, NY', 'Albany, GA', 'Albany Park, IL'];
insert into r select 'without a map position, bigger places first',
  (select array_agg(label) from suggest_localities('arlington')) = array['Arlington, TX', 'Arlington, VA'];
insert into r select 'near the map first (from DC: Arlington, VA)',
  (select label from suggest_localities('arlington', 38.9, -77.04) limit 1) = 'Arlington, VA';
insert into r select 'near the map first (from Dallas: Arlington, TX)',
  (select label from suggest_localities('arlington', 32.78, -96.8) limit 1) = 'Arlington, TX';
insert into r select 'partial word', (select label from suggest_localities('new y', 38.9, -77.04) limit 1) = 'New York, NY';
insert into r select 'with the state code', (select label from suggest_localities('Albany, NY', 38.9, -77.04) limit 1) = 'Albany, NY';
insert into r select 'with the state name', (select label from suggest_localities('albany georgia', 38.9, -77.04) limit 1) = 'Albany, GA';
insert into r select 'nickname', (select label from suggest_localities('NYC') limit 1) = 'New York, NY';
insert into r select 'two-letter nickname', (select label from suggest_localities('dc') limit 1) = 'Washington, DC';
insert into r select 'St. and Saint both work',
  (select label from suggest_localities('st louis') limit 1) = 'St. Louis, MO'
  and (select label from suggest_localities('saint louis') limit 1) = 'St. Louis, MO';
insert into r select 'accents not needed', (select label from suggest_localities('canon city') limit 1) = 'Cañon City, NM';
insert into r select 'typo: albny', (select label from suggest_localities('albny', 38.9, -77.04) limit 1) = 'Albany, NY';
insert into r select 'typo: new yrok', (select label from suggest_localities('new yrok') limit 1) = 'New York, NY';
insert into r select 'not a typo: saint paul does not suggest Saint Louis',
  (select array_agg(label) from suggest_localities('saint paul')) = array['St. Paul, MN'];
insert into r select 'not a typo: arlington does not suggest Washington',
  not exists (select 1 from suggest_localities('arlington') where label like 'Washington%');
insert into r select 'typing the state does not pull in other places in it',
  (select array_agg(label) from suggest_localities('new york, ny')) = array['New York, NY'];
insert into r select 'ZIP: digits match ZIP codes, with their main place',
  (select array_agg(label || ' ' || detail) from suggest_localities('222', 38.9, -77.04))
  = array['22201 Arlington, VA', '22202 Arlington, VA'];
insert into r select 'ZIP: a whole code comes back first, with city and state',
  (select label = '10001' and city = 'New York' and state = 'NY' from suggest_localities('10001') limit 1);
insert into r select 'a picked place carries city, state and a point',
  (select city = 'Albany' and state = 'NY' and abs(lat - 42.6664) < 0.001 and abs(lng + 73.7987) < 0.001
   from suggest_localities('albany ny') limit 1);
insert into r select 'one character or one digit: nothing yet',
  not exists (select 1 from suggest_localities('a')) and not exists (select 1 from suggest_localities('2'));
insert into r select 'punctuation only: nothing, no error', not exists (select 1 from suggest_localities('%%'''));
insert into r select 'no match: nothing', not exists (select 1 from suggest_localities('zzzzqqq'));
insert into r select 'max_results respected',
  (select count(*) = 2 from suggest_localities('albany', null, null, 2));
insert into r select 'max_results above 20 is held to 20',
  (select count(*) <= 20 from suggest_localities('a', null, null, 500));

-- Grants: anyone can ask for suggestions; nobody reads the tables directly through the API.
insert into r select 'API roles can ask for suggestions, PUBLIC cannot',
  has_function_privilege('anon', 'suggest_localities(text,double precision,double precision,integer)', 'execute')
  and has_function_privilege('authenticated', 'suggest_localities(text,double precision,double precision,integer)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.proname = 'suggest_localities' and a.grantee = 0 and a.privilege_type = 'EXECUTE');
insert into r select 'tables not readable by the API roles',
  not has_table_privilege('anon', 'public.localities', 'select')
  and not has_table_privilege('authenticated', 'public.locality_names', 'select');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
