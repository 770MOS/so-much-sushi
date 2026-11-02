-- Request a place: signed-in people send requests, admins add, link or decline them.
\set ON_ERROR_STOP 1
\set QUIET 1
-- A plain table, not a temp one, so checks can be recorded while acting as a signed-in person.
create table r(t text, ok boolean);
grant insert, select on r to authenticated, anon;

insert into auth.users (id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle": "u1"}'),
  ('22222222-2222-2222-2222-222222222222', '{"handle": "u2"}');
insert into entities (name, phone, location, main_category_id, status)
select v.n, v.p, v.loc::geography, (select id from categories where path::text = v.cat), v.s
from (values ('Bean Counter Coffee', '7035550101', 'SRID=4326;POINT(-77.1 38.88)', 'coffee', 'active'),
             ('Old Diner', null, 'SRID=4326;POINT(-77.1003 38.8803)', 'restaurants', 'permanently_closed'),
             ('Survivor Tacos', null, 'SRID=4326;POINT(-77.2 38.9)', 'restaurants', 'active')) v(n, p, loc, cat, s);
insert into entities (name, location, main_category_id, status, merged_into)
select 'Merged Tacos', 'SRID=4326;POINT(-77.2 38.9)'::geography, (select id from categories where path = 'restaurants'),
       'merged', (select id from entities where name = 'Survivor Tacos');

-- Privileges: requests are only reachable through the functions.
insert into r select 'signed-in people cannot read the requests table', not has_table_privilege('authenticated', 'place_requests', 'select');
insert into r select 'signed-out visitors cannot send requests', not has_function_privilege('anon', 'submit_place_request(jsonb)', 'execute');
insert into r select 'signed-in people cannot approve requests',
  not has_function_privilege('authenticated', 'admin_approve_place_request(bigint, jsonb, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'admin_pending_place_requests()', 'execute');

-- As u1.
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into r select 'a place we have nearby is shown first',
  exists (select 1 from request_similar_places(38.8801, -77.1001, 'Bean Counter') where name = 'Bean Counter Coffee');
insert into r select 'a permanently closed place is not shown to people',
  not exists (select 1 from request_similar_places(38.8803, -77.1003, 'Old Diner'));
insert into r select 'an unrelated name shows nothing', not exists (select 1 from request_similar_places(38.8801, -77.1001, 'Pho Saigon'));

select submit_place_request('{"name": " Pho Saigon ", "main_category": "restaurants", "lat": "38.8802", "lng": "-77.1002",
  "address": "1 Main St", "city": "Arlington", "state": "va", "phone": "", "own_knowledge": "true", "note": "opened last month"}') as pho \gset
select submit_place_request('{"name": "Bean Counter Cafe", "main_category": "coffee", "lat": "38.88", "lng": "-77.1",
  "own_knowledge": "true"}') as bean \gset
select submit_place_request('{"name": "Taco Spot", "main_category": "restaurants", "lat": "38.9", "lng": "-77.2",
  "own_knowledge": "true"}') as taco \gset
do $$ begin
  begin perform submit_place_request('{"name": "Pho Saigon", "main_category": "restaurants", "lat": "38.8802", "lng": "-77.1002", "own_knowledge": "true"}');
    insert into r values ('asking twice for the same place is refused', false);
  exception when others then insert into r values ('asking twice for the same place is refused', sqlerrm like '%already asked%'); end;
  begin perform submit_place_request('{"name": "X", "main_category": "coffee", "lat": "38.88", "lng": "-77.0"}');
    insert into r values ('where the details come from must be confirmed', false);
  exception when others then insert into r values ('where the details come from must be confirmed', sqlerrm like '%confirm%'); end;
  begin perform submit_place_request('{"name": "X", "main_category": "coffee", "lat": "51.5", "lng": "-0.1", "own_knowledge": "true"}');
    insert into r values ('a pin outside the US is refused', false);
  exception when others then insert into r values ('a pin outside the US is refused', true); end;
  begin perform submit_place_request('{"name": "X", "main_category": "coffee.espresso", "lat": "38.88", "lng": "-77.0", "own_knowledge": "true"}');
    insert into r values ('the kind of place must be a main category', false);
  exception when others then insert into r values ('the kind of place must be a main category', true); end;
  begin perform submit_place_request('{"name": "", "main_category": "coffee", "lat": "38.88", "lng": "-77.0", "own_knowledge": "true"}');
    insert into r values ('a name is required', false);
  exception when others then insert into r values ('a name is required', true); end;
  begin perform submit_place_request('{"name": "X", "main_category": "coffee", "lat": "38.88", "lng": "-77.0", "own_knowledge": "true", "state": "Virginia"}');
    insert into r values ('the state must be a two-letter code', false);
  exception when others then insert into r values ('the state must be a two-letter code', true); end;
end $$;
insert into r select 'people see their own requests', (select array_agg(name order by id) from my_place_requests())
  = array['Pho Saigon', 'Bean Counter Cafe', 'Taco Spot'];

-- As u2: the daily limit.
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
insert into r select 'people do not see others'' requests', not exists (select 1 from my_place_requests());
reset role;
insert into place_requests (requested_by, name, main_category_id, location, own_knowledge)
select '22222222-2222-2222-2222-222222222222', 'Spam ' || g, (select id from categories where path = 'coffee'),
       ST_SetSRID(ST_MakePoint(-77 - g / 100.0, 39), 4326)::geography, true
from generate_series(1, 25) g;
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ begin
  perform submit_place_request('{"name": "One more", "main_category": "coffee", "lat": "38.5", "lng": "-77.5", "own_knowledge": "true"}');
  insert into r values ('more than 25 requests a day are refused', false);
exception when others then insert into r values ('more than 25 requests a day are refused', sqlerrm like '%try again tomorrow%'); end $$;
-- Not signed in.
set request.jwt.claim.sub = '';
do $$ begin
  perform submit_place_request('{"name": "X", "main_category": "coffee", "lat": "38.88", "lng": "-77.0", "own_knowledge": "true"}');
  insert into r values ('a request needs a signed-in person', false);
exception when others then insert into r values ('a request needs a signed-in person', sqlerrm like '%sign in%'); end $$;
reset role;

insert into r select 'the request is stored as sent, tidied',
  (select requested_by = '11111111-1111-1111-1111-111111111111' and name = 'Pho Saigon' and state = 'VA' and phone is null
          and status = 'pending' and note = 'opened last month' from place_requests where id = :pho);

-- Admin screens.
insert into r select 'waiting requests are listed', (select count(*) from admin_pending_place_requests()) = 28;
insert into r select 'the list shows who asked and possible matches',
  (select x->>'requested_by' = 'u1' and (x->>'possible_matches')::int = 0 and (x->>'requests_by_this_person')::int = 3
   from admin_pending_place_requests() x where (x->>'id')::bigint = :pho)
  and (select (x->>'possible_matches')::int = 1 from admin_pending_place_requests() x where (x->>'id')::bigint = :bean);

select admin_approve_place_request(:pho, '{"name": "Pho Saigon", "main_category": "restaurants", "lat": "38.8802", "lng": "-77.1002",
  "address": "1 Main St", "city": "Arlington", "state": "VA", "postal_code": "22201"}', 'admin@test', 'checked its website') as pho_place \gset
insert into r select 'approving adds a place added by hand',
  (select name = 'Pho Saigon' and postal_code = '22201' and status = 'active' from entities where id = :'pho_place')
  and (select added_by_hand from admin_search_places(p_q => 'Pho Saigon') limit 1);
insert into r select 'the request records the place it became',
  (select status = 'added' and entity_id = :'pho_place' and decided_by = 'admin@test' and decided_at is not null
   from place_requests where id = :pho);
insert into r select 'the ledger entry names the request', exists (select 1 from change_events where entity_id = :'pho_place'
  and event_type = 'new_candidate' and (evidence->>'place_request')::bigint = :pho and evidence->>'note' = 'checked its website');
do $$ begin
  perform admin_approve_place_request((select id from place_requests where name = 'Pho Saigon'),
    '{"name": "Pho Saigon", "main_category": "restaurants", "lat": "38.8802", "lng": "-77.1002"}', 'a');
  insert into r values ('a request cannot be decided twice', false);
exception when others then insert into r values ('a request cannot be decided twice', sqlerrm like '%already decided%'); end $$;
insert into r select 'a failed approval adds nothing', (select count(*) from entities where name = 'Pho Saigon') = 1;

select admin_link_place_request(:bean, (select id from entities where name = 'Bean Counter Coffee'), 'admin@test') as bean_place \gset
insert into r select 'linking marks it already listed',
  (select status = 'already_listed' and entity_id = :'bean_place' from place_requests where id = :bean)
  and :'bean_place' = (select id::text from entities where name = 'Bean Counter Coffee');
select admin_link_place_request(:taco, (select id from entities where name = 'Merged Tacos'), 'admin@test') as taco_place \gset
insert into r select 'linking to a merged place follows it to the surviving place',
  :'taco_place' = (select id::text from entities where name = 'Survivor Tacos');

insert into r select 'declining several at once', admin_decline_place_requests(
  array(select id from place_requests where name like 'Spam %'), 'admin@test', 'spam') = 25;
insert into r select 'declining again changes nothing', admin_decline_place_requests(
  array(select id from place_requests where name like 'Spam %'), 'admin@test') = 0;
insert into r select 'nothing is left waiting', not exists (select 1 from admin_pending_place_requests());

set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into r select 'people see what happened, with a link to the place',
  (select array_agg(status || ':' || (place_id is not null)::text order by id) from my_place_requests())
  = array['added:true', 'already_listed:true', 'already_listed:true'];
reset role;

delete from auth.users where id = '22222222-2222-2222-2222-222222222222';
insert into r select 'requests are kept when an account is deleted',
  (select count(*) from place_requests where name like 'Spam %' and requested_by is null) = 25;

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
