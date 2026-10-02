-- Scenario checks for the data-layer migrations. Run against a scratch database only: it inserts fixtures.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
-- fixtures
insert into auth.users(id,raw_user_meta_data) values ('11111111-1111-1111-1111-111111111111','{"handle":"u1"}'),('22222222-2222-2222-2222-222222222222','{"handle":"u2"}');
insert into entities(id,name,location) values
 ('aaaaaaaa-0000-0000-0000-000000000001','Dup','SRID=4326;POINT(-77.1 38.88)'),
 ('aaaaaaaa-0000-0000-0000-000000000002','Survivor','SRID=4326;POINT(-77.1 38.88)'),
 ('aaaaaaaa-0000-0000-0000-000000000003','Final','SRID=4326;POINT(-77.1 38.88)');
insert into entity_categories select id,(select id from categories where slug='pizza') from entities;
insert into stars(user_id,entity_id) values ('11111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-000000000001'),('11111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-000000000002'),('22222222-2222-2222-2222-222222222222','aaaaaaaa-0000-0000-0000-000000000001');
insert into lists(id,owner_id,name) values ('bbbbbbbb-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','A'),('bbbbbbbb-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','B');
insert into list_items(list_id,entity_id) values ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001'),('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000002');
-- 1 delete of starred entity refused
do $$ begin delete from entities where id='aaaaaaaa-0000-0000-0000-000000000001'; insert into r values('restrict delete',false); exception when foreign_key_violation then insert into r values('restrict delete',true); end $$;
-- 2 merge
select merge_entities('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002','test') as ev \gset
insert into r select 'stars: survivor has 2, dup has 0', (select count(*) from stars where entity_id='aaaaaaaa-0000-0000-0000-000000000002')=2 and (select count(*) from stars where entity_id='aaaaaaaa-0000-0000-0000-000000000001')=0;
insert into r select 'survivor in both lists', (select count(*) from list_items where entity_id='aaaaaaaa-0000-0000-0000-000000000002')=2;
insert into r select 'tombstone', (select status='merged' and merged_into='aaaaaaaa-0000-0000-0000-000000000002' from entities where id='aaaaaaaa-0000-0000-0000-000000000001');
insert into r select 'ledger records moved+dropped', (select jsonb_array_length(evidence->'stars'->'moved')=1 and jsonb_array_length(evidence->'stars'->'dropped')=1 and jsonb_array_length(evidence->'list_items'->'moved')=1 from change_events where id=:ev);
-- 3 chain
select merge_entities('aaaaaaaa-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000003','test') \gset
insert into r select 'chain resolves', resolve_entity('aaaaaaaa-0000-0000-0000-000000000001')='aaaaaaaa-0000-0000-0000-000000000003';
insert into r select 'detail of old id returns final', (select id='aaaaaaaa-0000-0000-0000-000000000003' from get_entity_detail('aaaaaaaa-0000-0000-0000-000000000001'));
insert into r select 'search excludes tombstones', (select count(*)=1 from search_entities(38.88,-77.1,1));
do $$ begin perform merge_entities('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000003','t'); insert into r values('re-merge refused',false); exception when others then insert into r values('re-merge refused',true); end $$;
do $$ begin update entities set status='merged' where id='aaaaaaaa-0000-0000-0000-000000000003'; insert into r values('merged needs pointer',false); exception when check_violation then insert into r values('merged needs pointer',true); end $$;
-- 4 provenance licence guard
insert into sources(code,name,role,license,license_class) values ('va_abc','VA ABC','registry','public record','verify_only');
do $$ begin insert into entity_field_provenance(entity_id,field,source_id,license,method) select 'aaaaaaaa-0000-0000-0000-000000000003','name',id,'x','survivorship' from sources where code='va_abc'; insert into r values('verify_only blocked',false); exception when check_violation then insert into r values('verify_only blocked',true); end $$;
insert into entity_field_provenance(entity_id,field,source_id,license,method) select 'aaaaaaaa-0000-0000-0000-000000000003','name',id,'CDLA-Permissive-2.0','survivorship' from sources where code='overture_places';
insert into r select 'audit view empty', (select count(*)=0 from provenance_license_audit);
update sources set license_class='share_alike' where code='overture_places';
insert into r select 'audit view flags after reclass', (select count(*)=1 from provenance_license_audit);
-- 5 access
insert into r select 'anon/auth cannot read ledger or sources', not has_table_privilege('anon','change_events','select') and not has_table_privilege('authenticated','sources','select') and not has_table_privilege('authenticated','pending_changes','select');
insert into r select 'service_role can write', has_table_privilege('service_role','source_records','insert') and has_function_privilege('service_role','merge_entities(uuid,uuid,text,text)','execute');
insert into r select 'anon cannot merge', not has_function_privilege('anon','merge_entities(uuid,uuid,text,text)','execute');
insert into r select 'rls on all new tables', (select bool_and(relrowsecurity) from pg_class where relname in ('sources','source_runs','source_records','entity_field_provenance','change_events','review_decisions'));
set role anon; select (select id from get_entity_detail('aaaaaaaa-0000-0000-0000-000000000001')) is not null as anon_detail \gset
reset role; insert into r values('anon venue link resolves', :'anon_detail');
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
