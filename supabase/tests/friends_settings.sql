-- Scenario checks for Friends, a friend's page and account settings
-- (20261113020000_friends_and_settings.sql): requests only through the functions, invite links,
-- the Friends page, finding people, a person's page, the public-list name, the new-list
-- setting, settings and the data download.
-- Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
grant all on table r to authenticated;
set row_security = on;

insert into auth.users(id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle":"johnny","first_name":"Johnny","last_name":"Doe"}'),
  ('22222222-2222-2222-2222-222222222222', '{"handle":"priya","first_name":"Priya","last_name":"Shah"}'),
  ('33333333-3333-3333-3333-333333333333', '{"handle":"sam","first_name":"Sam","last_name":"Okafor"}'),
  ('44444444-4444-4444-4444-444444444444', '{"handle":"dev","first_name":"Dev","last_name":"Patel"}'),
  ('55555555-5555-5555-5555-555555555555', '{"handle":"maya","first_name":"Maya","last_name":"Chen"}');
update profiles set display_name = first_name || ' ' || last_name;

insert into entities(name, address, city, state, location, main_category_id, status) values
  ('Mazaro', '2909 Wilson Blvd', 'Arlington', 'VA', 'SRID=4326;POINT(-77.0936 38.8886)'::extensions.geography,
   (select id from categories where path = 'restaurants'), 'active'),
  ('Doyle', '1500 New Hampshire Ave NW', 'Washington', 'DC', 'SRID=4326;POINT(-77.0430 38.9100)'::extensions.geography,
   (select id from categories where path = 'drinks'), 'active');
create function pid(n text) returns uuid language sql as $$ select id from entities where name = n $$;
create function as_user(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false) $$;

-- ------------------------------------------------------------ no more direct writes
select as_user('11111111-1111-1111-1111-111111111111');
set role authenticated;
do $$ begin
  insert into friendships(requester_id, addressee_id, status)
  values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted');
  insert into r values ('a member can''t add a friendship row directly (e.g. already accepted)', false);
exception when insufficient_privilege then
  insert into r values ('a member can''t add a friendship row directly (e.g. already accepted)', true);
end $$;
reset role;
-- A request from Sam to Johnny, made the proper way.
select as_user('33333333-3333-3333-3333-333333333333');
select send_friend_request('11111111-1111-1111-1111-111111111111');
select as_user('11111111-1111-1111-1111-111111111111');
set role authenticated;
do $$ begin
  update friendships set status = 'accepted', requester_id = '44444444-4444-4444-4444-444444444444'
  where addressee_id = '11111111-1111-1111-1111-111111111111';
  insert into r values ('nor change one directly (accept, or rewrite who sent it)', false);
exception when insufficient_privilege then
  insert into r values ('nor change one directly (accept, or rewrite who sent it)', true);
end $$;
reset role;

-- ------------------------------------------------------------ requests
select as_user('11111111-1111-1111-1111-111111111111');
-- (Each call is its own statement, so the checks see what it changed.)
create temp table out(n int, v text);
insert into out select 1, send_friend_request('22222222-2222-2222-2222-222222222222');
insert into out select 2, send_friend_request('22222222-2222-2222-2222-222222222222');
insert into r select 'send: a new request is sent; asking again changes nothing',
  (select array_agg(v order by n) = array['sent', 'sent'] from out where n in (1, 2))
  and (select count(*) = 1 from friendships where requester_id = '11111111-1111-1111-1111-111111111111'
         and addressee_id = '22222222-2222-2222-2222-222222222222' and status = 'pending');
select as_user('22222222-2222-2222-2222-222222222222');
insert into out select 3, send_friend_request('11111111-1111-1111-1111-111111111111');
insert into r select 'send: asking someone who already asked you makes you friends',
  (select v = 'friends' from out where n = 3)
  and (select status = 'accepted' and accepted_at is not null from friendships
       where requester_id = '11111111-1111-1111-1111-111111111111' and addressee_id = '22222222-2222-2222-2222-222222222222');
do $$ begin
  perform send_friend_request('22222222-2222-2222-2222-222222222222');
  insert into r values ('send: not to yourself', false);
exception when no_data_found then insert into r values ('send: not to yourself', true);
end $$;

select as_user('11111111-1111-1111-1111-111111111111');
insert into out select 4, answer_friend_request('33333333-3333-3333-3333-333333333333', false);
insert into r select 'answer: declining a request removes it',
  (select v = 'none' from out where n = 4)
  and not exists (select 1 from friendships where requester_id = '33333333-3333-3333-3333-333333333333');
select as_user('44444444-4444-4444-4444-444444444444');
select send_friend_request('11111111-1111-1111-1111-111111111111');
select as_user('11111111-1111-1111-1111-111111111111');
insert into r select 'answer: accepting makes friends',
  answer_friend_request('44444444-4444-4444-4444-444444444444', true) = 'friends';
insert into r select 'answer: only requests sent to you',
  answer_friend_request('55555555-5555-5555-5555-555555555555', true) = 'none';

select send_friend_request('55555555-5555-5555-5555-555555555555');
insert into out select 5, remove_friend('55555555-5555-5555-5555-555555555555');
insert into r select 'remove: takes back a request you sent',
  (select v = 'none' from out where n = 5)
  and not exists (select 1 from friendships where addressee_id = '55555555-5555-5555-5555-555555555555');
select as_user('55555555-5555-5555-5555-555555555555');
select send_friend_request('11111111-1111-1111-1111-111111111111');
select as_user('11111111-1111-1111-1111-111111111111');
insert into r select 'remove: a request sent to you stays until you answer it',
  remove_friend('55555555-5555-5555-5555-555555555555') = 'received';

-- A block reads as nothing.
insert into friendships(requester_id, addressee_id, status) values
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'blocked');
insert into out select 6, send_friend_request('33333333-3333-3333-3333-333333333333');
insert into r select 'send: a block says "sent" and changes nothing',
  (select v = 'sent' from out where n = 6)
  and (select count(*) = 1 and bool_and(status = 'blocked') from friendships
       where '33333333-3333-3333-3333-333333333333' in (requester_id, addressee_id));

-- ------------------------------------------------------------ invite links
-- Johnny: friends with Priya and Dev; Maya has asked; Sam blocked him.
create temp table codes as select my_invite_code() as first, my_invite_code() as again;
insert into r select 'invite: a code, the same each time',
  (select length(first) = 16 and first = again from codes);
update codes set again = my_invite_code(true);
insert into r select 'invite: a new code, and the old one stops working',
  (select first <> again and invite_info(first) is null and invite_info(again) is not null from codes);
select as_user('');
insert into r select 'invite: a visitor sees first name and last initial',
  (select invite_info(again) = '{"name":"Johnny D.","handle":"johnny","relation":"none"}'::jsonb from codes);
select as_user('55555555-5555-5555-5555-555555555555');
insert into out select 7, accept_invite(again)::text from codes;
insert into r select 'invite: opening it makes friends (and settles a waiting request)',
  (select v::jsonb = '{"handle":"johnny","relation":"friends"}'::jsonb from out where n = 7)
  and (select count(*) = 1 from friendships where '55555555-5555-5555-5555-555555555555' in (requester_id, addressee_id));
select as_user('11111111-1111-1111-1111-111111111111');
insert into r select 'invite: your own link does nothing',
  (select accept_invite(again)->>'relation' = 'self' from codes);
insert into r select 'invite: no such code, nothing',
  accept_invite('nope') is null;

-- ------------------------------------------------------------ the Friends page
select as_user('22222222-2222-2222-2222-222222222222');
select send_friend_request('44444444-4444-4444-4444-444444444444');
select as_user('44444444-4444-4444-4444-444444444444');
select answer_friend_request('22222222-2222-2222-2222-222222222222', true);
insert into stars(user_id, entity_id) values
  ('22222222-2222-2222-2222-222222222222', pid('Mazaro')),
  ('22222222-2222-2222-2222-222222222222', pid('Doyle')),
  ('11111111-1111-1111-1111-111111111111', pid('Mazaro'));
insert into lists(owner_id, name, visibility) values
  ('22222222-2222-2222-2222-222222222222', 'Best dumplings', 'friends'),
  ('22222222-2222-2222-2222-222222222222', 'Public picks', 'public'),
  ('22222222-2222-2222-2222-222222222222', 'Secret', 'private');
insert into list_items(list_id, entity_id)
select id, pid('Doyle') from lists where name = 'Public picks';
select as_user('66666666-6666-6666-6666-666666666666');
insert into auth.users(id, raw_user_meta_data) values ('66666666-6666-6666-6666-666666666666', '{"handle":"alex","first_name":"Alex","last_name":"Moreno"}');
select send_friend_request('11111111-1111-1111-1111-111111111111');
select as_user('11111111-1111-1111-1111-111111111111');
select send_friend_request('33333333-3333-3333-3333-333333333333'); -- blocked: nothing
create temp table fo as select friends_overview() as j;
insert into r select 'friends page: requests to you, newest first',
  (select jsonb_path_query_array(j->'incoming', '$[*].handle') = '["alex"]'::jsonb from fo);
insert into r select 'friends page: your friends A-Z with favorites and shared lists',
  (select jsonb_path_query_array(j->'friends', '$[*].handle') = '["dev","maya","priya"]'::jsonb from fo)
  and (select (x->>'favorites')::int = 2 and (x->>'shared_lists')::int = 2 and x->>'name' = 'Priya Shah'
       from fo, jsonb_array_elements(j->'friends') x where x->>'handle' = 'priya');
insert into r select 'friends page: friends in common',
  (select (x->>'in_common')::int = 1 from fo, jsonb_array_elements(j->'friends') x where x->>'handle' = 'dev');
insert into r select 'friends page: nothing sent (a block isn''t shown)',
  (select j->'outgoing' = '[]'::jsonb from fo);

-- ------------------------------------------------------------ finding people
insert into r select 'find: by name or username, with how you''re connected',
  (select array_agg(handle || ':' || relation order by handle) from find_people('a'))  is null
  and (select array_agg(handle || ':' || relation order by handle) from find_people('mor')) = array['alex:received']
  and (select array_agg(handle || ':' || relation order by handle) from find_people('@pri')) = array['priya:friends'];
insert into r select 'find: not yourself, not someone who blocked you',
  not exists (select 1 from find_people('jo')) and not exists (select 1 from find_people('sam'));
select as_user('');
insert into r select 'find: nothing for a visitor', not exists (select 1 from find_people('priya'));

-- ------------------------------------------------------------ a person's page
select as_user('11111111-1111-1111-1111-111111111111');
create temp table pp as select person_page('Priya') as j;
insert into r select 'person: a friend sees their favorites, with their own hearts marked',
  (select j->>'relation' = 'friends' and j->>'name' = 'Priya Shah' and (j->>'favorites_count')::int = 2
          and jsonb_path_query_array(j->'favorites', '$[*].name') = '["Doyle","Mazaro"]'::jsonb
          and jsonb_path_query_array(j->'favorites', '$[*].is_starred') = '[false,true]'::jsonb
          and j->>'friends_since' is not null from pp);
insert into r select 'person: a friend sees Friends and Public lists, not Just you',
  (select jsonb_path_query_array(j->'lists', '$[*].name') = '["Best dumplings","Public picks"]'::jsonb
          and j->'lists'->1->>'place_count' = '1' and j->'lists'->1->'towns' = '["Washington"]'::jsonb from pp);
select as_user('33333333-3333-3333-3333-333333333333');
insert into r select 'person: someone else sees no favorites, only Public lists, and a short name',
  (select j->>'relation' = 'none' and j->>'name' = 'Priya S.' and (j->>'favorites_count')::int = 0
          and j->'favorites' = '[]'::jsonb and jsonb_path_query_array(j->'lists', '$[*].name') = '["Public picks"]'::jsonb
   from (select person_page('priya') as j) t);
select as_user('22222222-2222-2222-2222-222222222222');
insert into r select 'person: your own page has all your lists',
  (select j->>'relation' = 'self' and jsonb_array_length(j->'lists') = 4
   from (select person_page('priya') as j) t);
select as_user('');
insert into r select 'person: a visitor sees only Public lists; no such handle, nothing',
  (select j->>'relation' = 'none' and jsonb_array_length(j->'lists') = 1 from (select person_page('priya') as j) t)
  and person_page('nobody') is null;

-- ------------------------------------------------------------ the name on public lists
insert into r select 'public lists: first name and last initial by default',
  (select list_page(id)->'owner'->>'name' = 'Priya S.' from lists where name = 'Public picks');
update profiles set public_name_full = true where handle = 'priya';
insert into r select 'public lists: the full name if they chose it',
  (select list_page(id)->'owner'->>'name' = 'Priya Shah' from lists where name = 'Public picks');

-- ------------------------------------------------------------ who sees new lists
update profiles set new_list_visibility = 'friends' where handle = 'johnny';
select as_user('11111111-1111-1111-1111-111111111111');
set role authenticated;
insert into lists(owner_id, name) values ('11111111-1111-1111-1111-111111111111', 'Tacos');
reset role;
select as_user('44444444-4444-4444-4444-444444444444');
set role authenticated;
insert into lists(owner_id, name) values ('44444444-4444-4444-4444-444444444444', 'Dev''s');
reset role;
insert into r select 'new lists start with the person''s setting (Just you if they have none)',
  (select visibility = 'friends' from lists where name = 'Tacos')
  and (select visibility = 'private' from lists where name = 'Dev''s');
insert into r select 'the ready-made Want to try still starts as Just you',
  (select bool_and(visibility = 'private') from lists where is_default_list);

-- ------------------------------------------------------------ settings and your data
select as_user('11111111-1111-1111-1111-111111111111');
insert into r select 'settings: your own choices',
  (select j->>'first_name' = 'Johnny' and j->>'handle' = 'johnny' and not (j->>'public_name_full')::boolean
          and j->>'new_list_visibility' = 'friends' and (j->>'email_friend_requests')::boolean
   from (select my_settings() as j) t);
create temp table ex as select * from my_data_export();
insert into r select 'your data: favorites, list places (an empty list as one row) and friends',
  (select count(*) = 1 from ex where section = 'Favorite' and name = 'Mazaro' and town = 'Arlington')
  and (select count(*) = 1 from ex where section = 'List' and list_name = 'Tacos' and name is null)
  and (select array_agg(name order by name) from ex where section = 'Friend') = array['Dev Patel', 'Maya Chen', 'Priya Shah'];
select as_user('');
insert into r select 'settings: nothing for a visitor', my_settings() is null;

-- ------------------------------------------------------------ grants
insert into r select 'requests need a signed-in member; invites open to anyone',
  not has_function_privilege('anon', 'send_friend_request(uuid)', 'execute')
  and has_function_privilege('authenticated', 'send_friend_request(uuid)', 'execute')
  and not has_function_privilege('anon', 'my_invite_code(boolean)', 'execute')
  and has_function_privilege('anon', 'invite_info(text)', 'execute')
  and has_function_privilege('anon', 'person_page(text)', 'execute')
  and not has_function_privilege('anon', 'my_data_export()', 'execute');
insert into r select 'the internal helpers aren''t callable through the API',
  not has_function_privilege('authenticated', 'friendship_with(uuid, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'relation_to(uuid, uuid)', 'execute');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
