-- Bulk edits from the All places list.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
insert into entities (id, name, location, main_category_id, needs_review)
select v.id::uuid, v.name, 'SRID=4326;POINT(-77.1 38.88)'::geography, (select id from categories where path = 'restaurants'), true
from (values ('aaaaaaaa-0000-0000-0000-000000000001', 'One'), ('aaaaaaaa-0000-0000-0000-000000000002', 'Two'),
             ('aaaaaaaa-0000-0000-0000-000000000003', 'Three')) v(id, name);
insert into entity_categories values ('aaaaaaaa-0000-0000-0000-000000000001', (select id from categories where slug = 'pizza'));
update entities set status = 'merged', merged_into = 'aaaaaaaa-0000-0000-0000-000000000001' where id = 'aaaaaaaa-0000-0000-0000-000000000003';
create function pg_temp.tags(p_place uuid) returns text[] language sql as $$
  select coalesce(array_agg(c.slug order by c.slug), '{}') from entity_categories ec join categories c on c.id = ec.category_id where ec.entity_id = p_place $$;

select admin_bulk_update(array['aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000003']::uuid[],
  '{"needs_review": "false", "status": "temporarily_closed"}', array[(select path::text from categories where slug = 'italian')],
  array[(select path::text from categories where slug = 'pizza')], 'admin@test', 'checked on the street') as res \gset
insert into r select 'fields changed on every live place',
  (select count(*) from entities where id in ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002')
   and status = 'temporarily_closed' and not needs_review) = 2;
insert into r select 'tags added and removed', pg_temp.tags('aaaaaaaa-0000-0000-0000-000000000001') = array['italian']
  and pg_temp.tags('aaaaaaaa-0000-0000-0000-000000000002') = array['italian'];
insert into r select 'merged place skipped', (:'res'::jsonb->>'skipped_merged')::int = 1
  and (select status from entities where id = 'aaaaaaaa-0000-0000-0000-000000000003') = 'merged';
insert into r select 'counts returned', (:'res'::jsonb->>'places_changed')::int = 2 and (:'res'::jsonb->>'fields_changed')::int = 4;
insert into r select 'each change is a hand edit with the bulk note',
  (select count(*) from change_events where event_type = 'manual_edit' and evidence->>'note' = 'Bulk edit of 3 places: checked on the street') = 4
  and (select method from entity_field_provenance where entity_id = 'aaaaaaaa-0000-0000-0000-000000000002' and field = 'status') = 'manual';

do $$ begin
  begin perform admin_bulk_update(array['aaaaaaaa-0000-0000-0000-000000000001']::uuid[], '{"name": "X"}', null, null, 'a');
    insert into r values ('only category, status and review flag can be bulk edited', false);
  exception when others then insert into r values ('only category, status and review flag can be bulk edited', true); end;
  begin perform admin_bulk_update(array['aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002']::uuid[],
                                  '{"status": "bogus"}', null, null, 'a');
    insert into r values ('one bad value stops the whole edit', false);
  exception when others then insert into r values ('one bad value stops the whole edit',
    (select count(*) from entities where status = 'bogus') = 0); end;
  begin perform admin_bulk_update(array['aaaaaaaa-0000-0000-0000-000000000001']::uuid[], '{}', null, null, 'a');
    insert into r values ('an empty edit is refused', false);
  exception when others then insert into r values ('an empty edit is refused', true); end;
end $$;
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
