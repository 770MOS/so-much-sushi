-- Scenario checks for nearest-first search (20261108000000_nearest_first_search.sql).
-- Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);

-- People: u1 searches; u2 is u1's friend; u3 has only a pending request.
insert into auth.users(id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle":"u1"}'),
  ('22222222-2222-2222-2222-222222222222', '{"handle":"u2"}'),
  ('33333333-3333-3333-3333-333333333333', '{"handle":"u3"}');
insert into friendships(requester_id, addressee_id, status) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'pending');

-- 1,005 restaurants in a line heading east from the search point, about 9 m apart (P0001 nearest).
insert into entities(name, location, main_category_id)
select 'P' || lpad(i::text, 4, '0'),
       ('SRID=4326;POINT(' || (-77.1 + i * 0.0001) || ' 38.88)')::extensions.geography,
       (select id from categories where slug = 'restaurants')
from generate_series(1, 1005) i;
-- Two bars at exactly the same spot, out of name order, for the tie-break.
insert into entities(name, location, main_category_id)
select v.name, 'SRID=4326;POINT(-77.0995 38.881)'::extensions.geography, (select id from categories where slug = 'drinks')
from (values ('B Same'), ('A Same')) v(name);
-- A closed place right at the search point: never shown, never counted.
insert into entities(name, location, main_category_id, status)
select 'Closed Spot', 'SRID=4326;POINT(-77.1 38.88)'::extensions.geography,
       (select id from categories where slug = 'restaurants'), 'permanently_closed';

-- Not signed in.
select set_config('request.jwt.claim.sub', '', false) \gset
create temp table s as
select * from search_entities(38.88, -77.1, 10) with ordinality;

insert into r select 'capped at 1,000 rows', (select count(*) = 1000 from s);
insert into r select 'total_count counts every match (1,005 + 2), not the closed one',
  (select bool_and(total_count = 1007) from s);
insert into r select 'the nearest are kept, the farthest left out',
  (select count(*) = 1 from s where name = 'P0001') and (select count(*) = 0 from s where name = 'P1005');
insert into r select 'rows come closest first',
  (select bool_and(miles >= prev) from (select miles, lag(miles) over (order by ordinality) prev from s) x where prev is not null);
insert into r select 'same distance is ordered by name',
  (select (select ordinality from s where name = 'A Same') < (select ordinality from s where name = 'B Same'));
insert into r select 'closed place not shown', (select count(*) = 0 from s where name = 'Closed Spot');

insert into r select 'a small result set reports its own size',
  (select count(*) = 2 and bool_and(total_count = 2) from search_entities(38.88, -77.1, 10, 'drinks'));
insert into r select 'name search counts only matching names',
  (select count(*) = 2 and bool_and(total_count = 2) from search_entities(38.88, -77.1, 10, null, false, false, false, 'same'));
insert into r select 'category filter applies to the count',
  (select bool_and(total_count = 1005) from search_entities(38.88, -77.1, 10, 'restaurants'));
insert into r select 'no matches returns no rows',
  (select count(*) = 0 from search_entities(38.88, -77.1, 10, null, false, false, false, 'nothing like this'));

-- Signed in as u1: hide the nearest place, star one, and let friends star others.
insert into hidden_entities(user_id, entity_id) select '11111111-1111-1111-1111-111111111111', id from entities where name = 'P0001';
insert into stars(user_id, entity_id) select '11111111-1111-1111-1111-111111111111', id from entities where name = 'P0002';
insert into stars(user_id, entity_id) select '22222222-2222-2222-2222-222222222222', id from entities where name = 'P0003';
insert into stars(user_id, entity_id) select '33333333-3333-3333-3333-333333333333', id from entities where name = 'P0004';
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \gset

insert into r select 'hidden place left out and not counted',
  (select bool_and(total_count = 1006) and count(*) filter (where name = 'P0001') = 0 from search_entities(38.88, -77.1, 10));
insert into r select 'show_hidden brings it back and marks it',
  (select is_hidden and total_count = 1007 from search_entities(38.88, -77.1, 10, null, true) where name = 'P0001');
insert into r select 'own star marked',
  (select is_starred from search_entities(38.88, -77.1, 10) where name = 'P0002');
insert into r select 'a friend''s star is a recommendation, with their name',
  (select recommended_count = 1 and recommended_by->0->>'handle' = 'u2' from search_entities(38.88, -77.1, 10) where name = 'P0003');
insert into r select 'a pending request''s star is not',
  (select recommended_count = 0 and recommended_by is null from search_entities(38.88, -77.1, 10) where name = 'P0004');
insert into r select 'recommended only: just the friend''s place, counted',
  (select count(*) = 1 and bool_and(name = 'P0003' and total_count = 1) from search_entities(38.88, -77.1, 10, null, false, true));
insert into r select 'starred only: just my star, counted',
  (select count(*) = 1 and bool_and(name = 'P0002' and total_count = 1) from search_entities(38.88, -77.1, 10, null, false, false, true));

-- Grants: open to the API roles, not to everyone.
insert into r select 'API roles can search, PUBLIC cannot',
  has_function_privilege('anon', 'search_entities(double precision,double precision,double precision,ltree,boolean,boolean,boolean,text)', 'execute')
  and has_function_privilege('authenticated', 'search_entities(double precision,double precision,double precision,ltree,boolean,boolean,boolean,text)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.proname = 'search_entities' and a.grantee = 0 and a.privilege_type = 'EXECUTE');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
