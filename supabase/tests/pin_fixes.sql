-- Pin fixes: admins move pins, members suggest new spots, sources leave hand-placed pins alone
-- (but a big source move goes to review).
\set ON_ERROR_STOP 1
\set QUIET 1
-- A plain table, not a temp one, so checks can be recorded while acting as a signed-in person.
create table r(t text, ok boolean);
grant insert, select on r to authenticated, anon;
update sources set license_class = 'permissive' where code = 'overture_places';

create function pg_temp.rec(id text, name text, lon float8, lat float8) returns jsonb
  language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'meta', 'license', 'CDLA-Permissive-2.0',
    'name', name, 'address', '1 Main St', 'city', 'Arlington', 'state', 'VA', 'postal_code', '22201', 'phone', null,
    'website', null, 'lon', lon, 'lat', lat, 'source_category', 'restaurant', 'category_slug', 'restaurants',
    'source_confidence', 0.9, 'payload', jsonb_build_object('operating_status', 'open', 'category_mapped', true)) $$;
create function pg_temp.load(records jsonb) returns jsonb language plpgsql as $$
declare v bigint;
begin
  insert into source_runs (source_id, scope, status) select id, 'bbox:-78,38,-76,40', 'running' from sources where code = 'overture_places' returning id into v;
  perform ingest_source_records(v, records);
  update source_runs set status = 'succeeded' where id = v;
  return reconcile_run(v, 'test');
end $$;
grant execute on function pg_temp.rec(text, text, float8, float8) to authenticated;

insert into auth.users (id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle": "u1"}'),
  ('22222222-2222-2222-2222-222222222222', '{"handle": "u2"}');

-- Three places from a source load.
select pg_temp.load(jsonb_build_array(
  pg_temp.rec('P', 'Pin Place', -77.10, 38.88), pg_temp.rec('Q', 'Quiet Place', -77.12, 38.88),
  pg_temp.rec('S', 'Source Place', -77.14, 38.88))) \gset
select id as p from entities where name = 'Pin Place' \gset
select id as q from entities where name = 'Quiet Place' \gset
select id as s from entities where name = 'Source Place' \gset
insert into entities (name, location, main_category_id, status, merged_into)
select 'Merged Place', 'SRID=4326;POINT(-77.1 38.88)'::geography, (select id from categories where path = 'restaurants'),
       'merged', :'p';

-- Privileges: reports are only reachable through the functions.
insert into r select 'signed-in people cannot read the reports table', not has_table_privilege('authenticated', 'pin_reports', 'select');
insert into r select 'signed-out visitors cannot send reports',
  not has_function_privilege('anon', 'submit_pin_report(uuid, double precision, double precision, text, text, real, text, boolean)', 'execute');
insert into r select 'signed-in people cannot move pins or decide reports',
  not has_function_privilege('authenticated', 'admin_move_pin(uuid, double precision, double precision, text, text, real, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'admin_accept_pin_report(bigint, double precision, double precision, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'admin_pending_pin_reports()', 'execute')
  and not has_function_privilege('authenticated', 'set_hand_pin(uuid, geography, text, text, text, jsonb, text)', 'execute');

-- Place ids for the do-blocks below (members cannot read entities themselves).
select set_config('t.p', :'p', false), set_config('t.m', (select id::text from entities where name = 'Merged Place'), false) \gset

-- As u1: a report for Pin Place about 7 m away, then a second one that replaces it.
set row_security = on;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select submit_pin_report(:'p', 38.88004, -77.10004, 'was_there', 'map', null, null, true) as first \gset
select submit_pin_report(:'p', 38.88005, -77.10005, 'was_there', 'map', null, 'by the side door', true) as p_u1 \gset
insert into r select 'sending again replaces the waiting report', :first = :p_u1;
insert into r select 'people see their waiting report',
  (select (j->>'id')::bigint = :p_u1 and abs((j->>'lat')::float8 - 38.88005) < 1e-9 from my_pin_report(:'p') j);
insert into r select 'no waiting report for another place', my_pin_report(:'q') is null;
select submit_pin_report(:'q', 38.88003, -77.12002, 'business', 'gps', 6.5, null, true) as q_u1 \gset
do $$ declare pid uuid := current_setting('t.p')::uuid; begin
  begin perform submit_pin_report(pid, 38.8801, -77.1001, 'was_there', 'map', null, null, false);
    insert into r values ('the box letting us use the correction must be ticked', false);
  exception when others then insert into r values ('the box letting us use the correction must be ticked', sqlerrm like '%tick the box%'); end;
  begin perform submit_pin_report(pid, 38.8801, -77.1001, 'other', 'map', null, '  ', true);
    insert into r values ('"something else" needs a note', false);
  exception when others then insert into r values ('"something else" needs a note', sqlerrm like '%add a note%'); end;
  begin perform submit_pin_report(pid, 38.90, -77.10, 'was_there', 'map', null, null, true);
    insert into r values ('a spot more than 2 km away is refused', false);
  exception when others then insert into r values ('a spot more than 2 km away is refused', sqlerrm like '%more than 2 km%'); end;
  begin perform submit_pin_report(pid, 38.880005, -77.100005, 'was_there', 'map', null, null, true);
    insert into r values ('the spot the pin is already at is refused', false);
  exception when others then insert into r values ('the spot the pin is already at is refused', sqlerrm like '%already is%'); end;
  begin perform submit_pin_report(pid, 51.5, -0.1, 'was_there', 'map', null, null, true);
    insert into r values ('a spot outside the US is refused', false);
  exception when others then insert into r values ('a spot outside the US is refused', sqlerrm like '%outside the United States%'); end;
  begin perform submit_pin_report(pid, 38.8801, -77.1001, 'was_there', 'map', 5, null, true);
    insert into r values ('accuracy is only kept for a phone location', false);
  exception when others then insert into r values ('accuracy is only kept for a phone location', true); end;
  begin perform submit_pin_report(pid, 38.8801, -77.1001, 'google', 'map', null, null, true);
    insert into r values ('only the listed ways of knowing are accepted', false);
  exception when others then insert into r values ('only the listed ways of knowing are accepted', sqlerrm like '%how you know%'); end;
  begin perform submit_pin_report(current_setting('t.m')::uuid, 38.8801, -77.1001, 'was_there', 'map', null, null, true);
    insert into r values ('a merged place takes no reports', false);
  exception when others then insert into r values ('a merged place takes no reports', sqlerrm like '%no longer listed%'); end;
end $$;

-- As u2: a report for Pin Place 2 m from u1's.
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select submit_pin_report(:'p', 38.880062, -77.100062, 'was_there', 'map', null, null, true) as p_u2 \gset
insert into r select 'people do not see others'' reports', my_pin_report(:'q') is null;

-- Signed out.
set request.jwt.claim.sub = '';
do $$ begin
  perform submit_pin_report(current_setting('t.p')::uuid, 38.8801, -77.1001, 'was_there', 'map', null, null, true);
  insert into r values ('signing in is needed to send a report', false);
exception when others then insert into r values ('signing in is needed to send a report', sqlerrm like '%sign in%'); end $$;
reset role;

-- Admin: the queue.
insert into r select 'three reports are waiting', (select count(*) from admin_pending_pin_reports()) = 3;
select admin_get_pin_report(:p_u1) as j \gset
insert into r select 'the report shows the place, where its pin came from and who sent it',
  (:'j'::jsonb #>> '{place,name}') = 'Pin Place' and (:'j'::jsonb #>> '{place,pin_method}') = 'survivorship'
  and (:'j'::jsonb #>> '{place,pin_contributor}') = 'meta' and (:'j'::jsonb ->> 'reported_by_handle') = 'u1'
  and (:'j'::jsonb ->> 'note') = 'by the side door';
insert into r select 'the report says how far the pin would move', (:'j'::jsonb ->> 'distance_m')::int between 6 and 8;
insert into r select 'other reports for the same place are listed, with how far apart they are',
  jsonb_array_length(:'j'::jsonb -> 'others') = 1 and (:'j'::jsonb #>> '{others,0,meters_from_this}')::int between 1 and 3;

-- Accept u1's report as sent.
select admin_accept_pin_report(:p_u1, null, null, 'admin@test', 'looks right') as moved \gset
insert into r select 'accepting moves the pin to the suggested spot',
  (select ST_DWithin(location, 'SRID=4326;POINT(-77.10005 38.88005)'::geography, 0.01) from entities where id = :'p')
  and :moved between 6 and 8;
insert into r select 'the pin is now credited to the member''s report',
  (select p.method = 'user_report' and s.code = 'user_report' and p.source_record_pk is null
   from entity_field_provenance p join sources s on s.id = p.source_id where p.entity_id = :'p' and p.field = 'location');
insert into r select 'the ledger records the move from the report',
  exists (select 1 from change_events where entity_id = :'p' and event_type = 'user_report' and status = 'approved'
          and field = 'location' and (evidence->>'pin_report')::bigint = :p_u1 and evidence->>'how' = 'was_there'
          and (evidence->>'adjusted')::boolean = false and evidence->>'note' = 'looks right');
insert into r select 'the place''s history shows it', exists (select 1 from place_history(:'p') where kind = 'user_report');
insert into r select 'the report is marked accepted with where the pin went',
  (select status = 'accepted' and applied_location is not null and decided_by = 'admin@test' from pin_reports where id = :p_u1);
insert into r select 'the other waiting report for the place is closed with it',
  (select status = 'superseded' and decision_note = 'pin set from report ' || :p_u1 from pin_reports where id = :p_u2);
do $$ begin
  perform admin_accept_pin_report((select id from pin_reports where status = 'accepted' limit 1), null, null, 'a');
  insert into r values ('a report cannot be decided twice', false);
exception when others then insert into r values ('a report cannot be decided twice', sqlerrm like '%already decided%'); end $$;

-- Accept u1's Quiet Place report, adjusted by the admin.
select admin_accept_pin_report(:q_u1, 38.88004, -77.12003, 'admin@test') \gset
insert into r select 'an adjusted report puts the pin where the admin put it, credited to us',
  (select ST_DWithin(e.location, 'SRID=4326;POINT(-77.12003 38.88004)'::geography, 0.01) and p.method = 'manual' and s.code = 'manual_research'
   from entities e join entity_field_provenance p on p.entity_id = e.id and p.field = 'location' join sources s on s.id = p.source_id
   where e.id = :'q')
  and exists (select 1 from change_events where entity_id = :'q' and event_type = 'user_report'
              and (evidence->>'adjusted')::boolean and evidence->>'method' = 'gps' and (evidence->>'accuracy_m')::int = 7);

-- Declining.
set row_security = on;
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select submit_pin_report(:'s', 38.8801, -77.1401, 'was_there', 'map', null, null, true) as s_u2 \gset
reset role;
create temp table out as select admin_decline_pin_reports(array[:s_u2]::bigint[], 'admin@test', 'not right') as n;
insert into r select 'declining a report', (select n from out) = 1
  and (select status = 'declined' and decision_note = 'not right' from pin_reports where id = :s_u2);
insert into r select 'declining again changes nothing', admin_decline_pin_reports(array[:s_u2]::bigint[], 'admin@test') = 0;
insert into r select 'a declined report leaves the pin alone',
  (select ST_DWithin(location, 'SRID=4326;POINT(-77.14 38.88)'::geography, 0.01) from entities where id = :'s');
insert into r select 'nothing is left waiting', not exists (select 1 from admin_pending_pin_reports());

-- An admin moves Pin Place directly, from a phone's location.
update entities set last_verified = null where id = :'p';
select admin_move_pin(:'p', 38.88007, -77.10007, 'was_there', 'gps', 4.2, null, 'admin@test') \gset
insert into r select 'moving a pin by hand credits it to us',
  (select ST_DWithin(e.location, 'SRID=4326;POINT(-77.10007 38.88007)'::geography, 0.01) and p.method = 'manual'
   from entities e join entity_field_provenance p on p.entity_id = e.id and p.field = 'location' where e.id = :'p');
insert into r select 'the ledger keeps how they knew and how the pin was placed',
  exists (select 1 from change_events where entity_id = :'p' and event_type = 'manual_edit' and field = 'location'
          and evidence->>'how' = 'was_there' and evidence->>'method' = 'gps' and (evidence->>'accuracy_m')::int = 4
          and (old_value->>'lat')::float8 between 38.880049 and 38.880051);
insert into r select 'moving a pin by hand counts as checking the place', (select last_verified is not null from entities where id = :'p');
do $$ declare pid uuid := (select id from entities where name = 'Pin Place'); begin
  begin perform admin_move_pin(pid, 38.88007, -77.10007, 'was_there', 'map', null, null, 'a');
    insert into r values ('moving a pin to where it already is is refused', false);
  exception when others then insert into r values ('moving a pin to where it already is is refused', sqlerrm like '%already there%'); end;
  begin perform admin_move_pin(pid, 38.8802, -77.1002, 'other', 'map', null, null, 'a');
    insert into r values ('admins also say how they know', false);
  exception when others then insert into r values ('admins also say how they know', sqlerrm like '%add a note%'); end;
  begin perform admin_move_pin((select id from entities where name = 'Merged Place'), 38.8802, -77.1002, 'was_there', 'map', null, null, 'a');
    insert into r values ('a merged place''s pin cannot be moved', false);
  exception when others then insert into r values ('a merged place''s pin cannot be moved', sqlerrm like '%merged%'); end;
end $$;

-- Load 2: Pin Place's source point moves 300 m, Quiet Place's 50 m, Source Place's 80 m.
select pg_temp.load(jsonb_build_array(
  pg_temp.rec('P', 'Pin Place', -77.10, 38.8827), pg_temp.rec('Q', 'Quiet Place', -77.12, 38.88045),
  pg_temp.rec('S', 'Source Place', -77.1409, 38.88))) as s2 \gset
insert into r select 'a hand-placed pin does not follow its source',
  (select ST_DWithin(location, 'SRID=4326;POINT(-77.10007 38.88007)'::geography, 0.01) from entities where id = :'p')
  and (select ST_DWithin(location, 'SRID=4326;POINT(-77.12003 38.88004)'::geography, 0.01) from entities where id = :'q');
insert into r select 'a source moving a hand-placed place more than 250 m goes to review',
  exists (select 1 from change_events where entity_id = :'p' and event_type = 'attribute_change' and field = 'location'
          and status = 'pending' and evidence->>'reason' like '%placed by hand%');
insert into r select 'a small source move of a hand-placed place is ignored',
  not exists (select 1 from change_events where entity_id = :'q' and event_type = 'attribute_change' and field = 'location' and status = 'pending');
insert into r select 'pins nobody placed by hand still follow their source',
  (select ST_DWithin(location, 'SRID=4326;POINT(-77.1409 38.88)'::geography, 0.01) from entities where id = :'s');

-- Accepting that proposal hands the pin back to the source.
select decide_source_changes(array(select id from change_events where entity_id = :'p' and status = 'pending'
                                   and field = 'location'), true, 'admin@test') \gset
insert into r select 'accepting the source''s move hands the pin back to the source',
  (select ST_DWithin(e.location, 'SRID=4326;POINT(-77.10 38.8827)'::geography, 0.01) and p.method = 'survivorship'
   from entities e join entity_field_provenance p on p.entity_id = e.id and p.field = 'location' where e.id = :'p');

-- A hand move closes pending source proposals to move the pin.
select pg_temp.load(jsonb_build_array(pg_temp.rec('P', 'Pin Place', -77.10, 38.886))) \gset
insert into r select 'a big source move of a source pin is proposed',
  exists (select 1 from change_events where entity_id = :'p' and status = 'pending' and field = 'location');
select admin_move_pin(:'p', 38.8828, -77.1001, 'business', 'map', null, null, 'admin@test') \gset
insert into r select 'moving the pin by hand closes it',
  not exists (select 1 from change_events where entity_id = :'p' and status = 'pending' and field = 'location');

delete from auth.users where id = '22222222-2222-2222-2222-222222222222';
insert into r select 'reports are kept when an account is deleted',
  (select count(*) from pin_reports where reported_by is null) = 2;

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
