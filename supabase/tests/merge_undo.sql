-- Merge any two places field by field, and undo a merge.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
update sources set license_class = 'permissive' where code = 'overture_places';
insert into auth.users(id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"handle":"u1"}'), ('22222222-2222-2222-2222-222222222222', '{"handle":"u2"}');

create function pg_temp.rec(id text, name text, phone text, website text, lon float8) returns jsonb
  language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'x', 'license', 'CDLA-Permissive-2.0',
    'name', name, 'address', '1 Main St', 'city', 'Arlington', 'state', 'VA', 'postal_code', '22201', 'phone', phone,
    'website', website, 'lon', lon, 'lat', 38.88, 'source_category', 'cafe', 'category_slug', 'coffee',
    'payload', jsonb_build_object('operating_status', 'open', 'category_mapped', true)) $$;
do $$ declare v bigint; begin
  insert into source_runs (source_id, scope, status) select id, 'state:VA', 'running' from sources where code = 'overture_places' returning id into v;
  perform ingest_source_records(v, jsonb_build_array(
    pg_temp.rec('s', 'Joe''s Pizza', null, 'https://joespizza.example', -77.1000),
    pg_temp.rec('d', 'Joe''s Pizza & Pasta', '7035550101', 'https://joes-pasta.example', -77.1020),
    pg_temp.rec('t', 'Third Place', '7035550303', null, -77.1040),
    pg_temp.rec('p1', 'Taco Town', '7035550404', null, -77.2000),
    pg_temp.rec('p2', 'Taco Town Cantina', '7035550505', null, -77.2001)));
  update source_runs set status = 'succeeded', finished_at = now() where id = v;
  perform reconcile_run(v, 'test');
end $$;
create function pg_temp.e(rid text) returns uuid language sql as $$
  select entity_id from source_records where source_record_id = rid $$;
select pg_temp.e('s') as s, pg_temp.e('d') as d, pg_temp.e('t') as t \gset

insert into entity_categories values (:'d', (select id from categories where slug = 'pizza'));
insert into stars (user_id, entity_id) values ('11111111-1111-1111-1111-111111111111', :'d'),
  ('22222222-2222-2222-2222-222222222222', :'d'), ('22222222-2222-2222-2222-222222222222', :'s');
insert into hidden_entities (user_id, entity_id) values ('11111111-1111-1111-1111-111111111111', :'d');
insert into lists (id, owner_id, name) values ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'L');
insert into list_items (list_id, entity_id, note) values ('bbbbbbbb-0000-0000-0000-000000000001', :'d', 'great');

insert into r select 'candidates: nearby places listed', exists (select 1 from admin_merge_candidates(:'s') where id = :'d');
insert into r select 'candidates: name search', exists (select 1 from admin_merge_candidates(:'s', 'third') where id = :'t');

-- Merge D into S, taking D's name. S has no phone, so D's phone fills it.
select admin_merge_places(:'s', :'d', array['name'], 'admin@test', 'same place') as m1 \gset
insert into r select 'chosen field taken from the other place', (select name from entities where id = :'s') = 'Joe''s Pizza & Pasta';
insert into r select 'empty field filled from the other place', (select phone from entities where id = :'s') = '7035550101';
insert into r select 'unchosen field kept', (select website from entities where id = :'s') = 'https://joespizza.example';
insert into r select 'taken value keeps its source attribution',
  (select source_record_pk from entity_field_provenance where entity_id = :'s' and field = 'name')
  = (select id from source_records where source_record_id = 'd');
insert into r select 'tags from both places kept', exists (select 1 from entity_categories ec join categories c on c.id = ec.category_id
  where ec.entity_id = :'s' and c.slug = 'pizza');
insert into r select 'other place is now a pointer; its record moved',
  (select status = 'merged' and merged_into = :'s' from entities where id = :'d') and pg_temp.e('d') = :'s';
insert into r select 'stars, hidden marks and list items moved',
  (select count(*) from stars where entity_id = :'s') = 2 and not exists (select 1 from stars where entity_id = :'d')
  and exists (select 1 from hidden_entities where entity_id = :'s') and exists (select 1 from list_items where entity_id = :'s');
insert into r select 'undo shows on both places', (select count(*) from admin_place_merges(:'s') where not undone) = 1
  and (select role from admin_place_merges(:'d')) = 'merged';

-- Undo it.
select admin_undo_merge(:m1, 'admin@test', 'different places') as u1 \gset
insert into r select 'kept place gets its own values back',
  (select name = 'Joe''s Pizza' and phone is null and website = 'https://joespizza.example' from entities where id = :'s');
insert into r select 'kept place gets its own attribution back',
  (select source_record_pk from entity_field_provenance where entity_id = :'s' and field = 'name')
  = (select id from source_records where source_record_id = 's')
  and not exists (select 1 from entity_field_provenance where entity_id = :'s' and field = 'phone');
insert into r select 'merged place comes back with its record',
  (select status = 'active' and merged_into is null from entities where id = :'d') and pg_temp.e('d') = :'d';
insert into r select 'stars, hidden marks and list items return',
  (select count(*) from stars where entity_id = :'d') = 2 and (select count(*) from stars where entity_id = :'s') = 1
  and exists (select 1 from hidden_entities where entity_id = :'d') and not exists (select 1 from hidden_entities where entity_id = :'s')
  and (select note from list_items where entity_id = :'d') = 'great' and not exists (select 1 from list_items where entity_id = :'s');
insert into r select 'tag added by the merge removed; still on the other place',
  not exists (select 1 from entity_categories ec join categories c on c.id = ec.category_id where ec.entity_id = :'s' and c.slug = 'pizza')
  and exists (select 1 from entity_categories ec join categories c on c.id = ec.category_id where ec.entity_id = :'d' and c.slug = 'pizza');
insert into r select 'undo logged on both places and the merge marked undone',
  (select count(*) from change_events where event_type = 'unmerge' and entity_id in (:'s', :'d')) = 2
  and (select evidence ? 'undone_by' from change_events where id = :m1);
do $$ begin
  perform admin_undo_merge((select id from change_events where event_type = 'merge' and evidence ? 'undone_by' limit 1), 'admin@test');
  insert into r values ('a merge cannot be undone twice', false);
exception when others then insert into r values ('a merge cannot be undone twice', true); end $$;

-- A field edited by hand after the merge is left alone by the undo.
select admin_merge_places(:'s', :'d', array['name'], 'admin@test') as m2 \gset
select admin_update_place(:'s', '{"name": "Joe''s Pizzeria"}'::jsonb, 'admin@test') \gset
select admin_undo_merge(:m2, 'admin@test') as u2 \gset
insert into r select 'field edited since the merge is kept and reported',
  (select name from entities where id = :'s') = 'Joe''s Pizzeria' and (:'u2'::jsonb)->'fields_kept_edited_since' ? 'name'
  and (select phone is null from entities where id = :'s');

-- A merge cannot be undone while the kept place is itself merged elsewhere.
select admin_merge_places(:'s', :'d', '{}', 'admin@test') as m3 \gset
select admin_merge_places(:'t', :'s', '{}', 'admin@test') as m4 \gset
create temp table vars as select :m3::bigint as m3;
do $$ begin
  perform admin_undo_merge((select m3 from vars), 'admin@test');
  insert into r values ('blocked while the kept place is merged elsewhere', false);
exception when others then insert into r values ('blocked while the kept place is merged elsewhere', true); end $$;
select admin_undo_merge(:m4, 'admin@test') \gset
select admin_undo_merge(:m3, 'admin@test') \gset
insert into r select 'undoing in reverse order restores all three',
  (select count(*) from entities where id in (:'s', :'d', :'t') and status = 'active') = 3;

-- From the review queue: accept, then undo marks the pair as different places.
insert into change_events (event_type, entity_id, old_value, new_value, evidence)
values ('merge', pg_temp.e('p1'), jsonb_build_object('duplicate', pg_temp.e('p2')), jsonb_build_object('survivor', pg_temp.e('p1')), '{}');
select max(id) as prop from change_events where event_type = 'merge' and status = 'pending' \gset
select decide_merge_proposals(array[:prop]::bigint[], true, 'admin@test') \gset
insert into r select 'queue merge: proposal approved', (select status from change_events where id = :prop) = 'approved';
select id as m5 from change_events where event_type = 'merge' and status = 'approved' and (evidence->>'proposal')::bigint = :prop \gset
select admin_undo_merge(:m5, 'admin@test') \gset
insert into r select 'undo marks the proposal as different places', (select status from change_events where id = :prop) = 'rejected';
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
