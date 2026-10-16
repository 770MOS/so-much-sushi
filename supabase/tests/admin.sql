-- Scenario checks for the admin functions: review queue, tag suggestions, place editing.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
update sources set license_class = 'permissive' where code = 'overture_places';
insert into entities (name, address, city, state, postal_code, location, main_category_id, status)
select v.n, '1 Main St', v.c, v.s, v.z, 'SRID=4326;POINT(-77.1 38.88)'::extensions.geography,
       (select id from categories where path = 'restaurants'), 'active'
from (values ('Pho New Saigon','Arlington','VA','22201-1234'), ('Hart Food Inc','Arlington','VA','22203'),
             ('Sushi Den','Bethesda','MD','20814'), ('Dup A','Arlington','VA','22201'), ('Dup B','Arlington','VA','22201')) v(n, c, s, z);

-- tag suggestions
select suggest_tags_from_names('t') as suggested \gset
insert into r select 'tags suggested from names', :suggested = 2;
insert into r select 'suggesting again adds nothing', suggest_tags_from_names('t') = 0;
select decide_tag_suggestions(array(select event_id from admin_pending_tags() where name = 'Pho New Saigon'), true, 'me') \gset
select decide_tag_suggestions(array(select event_id from admin_pending_tags() where name = 'Sushi Den'), false, 'me') \gset
insert into r select 'accepted suggestion adds the tag', exists (select 1 from entity_categories ec join entities e on e.id = ec.entity_id where e.name = 'Pho New Saigon');
insert into r select 'rejected suggestion stays rejected', suggest_tags_from_names('t') = 0
  and not exists (select 1 from entity_categories ec join entities e on e.id = ec.entity_id where e.name = 'Sushi Den');

-- merge proposals
insert into change_events (event_type, entity_id, old_value, new_value, evidence)
select 'merge', a.id, jsonb_build_object('duplicate', b.id), jsonb_build_object('survivor', a.id), '{"distance_m":5}'
from entities a, entities b where a.name = 'Dup A' and b.name = 'Dup B';
insert into r select 'merge proposal listed', (select count(*) from admin_pending_merges()) = 1;
select decide_merge_proposals(array(select event_id from admin_pending_merges()), true, 'me') \gset
insert into r select 'accepted proposal merges', (select status from entities where name = 'Dup B') = 'merged';

-- browse and edit
insert into r select 'filter by zip uses the first five digits', (select count(*) from admin_search_places(p_zip => '22201', p_q => 'Pho')) = 1;
insert into r select 'tag filter includes tags beneath', (select count(*) from admin_search_places(p_tags => array['restaurants.asian'])) = 1;
insert into r select 'merged places hidden by default', (select count(*) from admin_search_places(p_q => 'Dup')) = 1;
select admin_update_place((select id from entities where name = 'Hart Food Inc'), '{"name":"Hart Deli","main_category":"markets","needs_review":"false"}', 'me', 'checked') as changed \gset
insert into r select 'edit changes only what differs (needs_review was already false)', :changed = 2;
insert into r select 'edit marks provenance as manual', (select method from entity_field_provenance p join entities e on e.id = p.entity_id where e.name = 'Hart Deli' and p.field = 'name') = 'manual';
select admin_set_place_tags((select id from entities where name = 'Sushi Den'), array['restaurants.asian.japanese.sushi'], 'me') as tagged \gset
insert into r select 'tags replaced', :'tagged'::boolean and (select tags from admin_search_places(p_q => 'Sushi Den')) = array['Sushi'];
do $$ begin perform admin_set_place_tags((select id from entities where name = 'Sushi Den'), array['restaurants'], 'me');
  insert into r values ('main category refused as a tag', false);
exception when others then insert into r values ('main category refused as a tag', true); end $$;
do $$ begin perform admin_update_place((select id from entities where name = 'Sushi Den'), '{"merged_into":"x"}', 'me');
  insert into r values ('unknown field refused', false);
exception when others then insert into r values ('unknown field refused', true); end $$;
insert into r select 'filters list towns with their state', jsonb_array_length(admin_place_filters()->'towns') = 2;

-- access
insert into r select 'admin functions closed to the public',
  not has_function_privilege('anon', 'admin_search_places(text,text,text,text,text,text[],text,boolean,boolean,integer,integer)', 'execute')
  and not has_function_privilege('authenticated', 'decide_source_changes(bigint[],boolean,text)', 'execute')
  and not has_table_privilege('authenticated', 'admins', 'select');
insert into r select 'licence audit stays clean', (select count(*) from provenance_license_audit) = 0;
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
