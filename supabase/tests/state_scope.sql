-- Scenario checks for state-by-state loads, including 'state:none' for records with no
-- recognised state.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
update sources set license_class = 'permissive' where code = 'overture_places';
create function pg_temp.rec(id text, state text, lon float8) returns jsonb
  language sql as $$
  select jsonb_build_object('source_record_id', id, 'upstream_dataset', 'x', 'license', 'CC0-1.0',
    'name', 'Cafe ' || id, 'address', '1 Main St', 'city', 'Town', 'state', state, 'postal_code', '22201',
    'phone', null, 'website', null, 'lon', lon, 'lat', 38.88,
    'source_category', 'cafe', 'category_slug', 'coffee',
    'payload', jsonb_build_object('operating_status', 'open', 'category_mapped', true)) $$;
create function pg_temp.load(scope text, records jsonb) returns jsonb language plpgsql as $$
declare v bigint;
begin
  insert into source_runs (source_id, scope, status) select id, scope, 'running' from sources where code = 'overture_places'
    returning id into v;
  perform ingest_source_records(v, records);
  update source_runs set status = 'succeeded', finished_at = now() where id = v;
  return reconcile_run(v, 'test');
end $$;
create function pg_temp.absent(rid text) returns boolean language sql as $$
  select exists (select 1 from change_events c join source_records sr on sr.id = c.source_record_pk
                 where c.event_type = 'absent' and c.status = 'pending' and sr.source_record_id = rid) $$;

insert into r select 'state:none covers a missing state', record_in_scope('state:none', null, null);
insert into r select 'state:none covers a blank state', record_in_scope('state:none', null, '  ');
insert into r select 'state:none covers a state we do not recognise', record_in_scope('state:none', null, 'Ontario');
insert into r select 'state:none leaves out a US state', not record_in_scope('state:none', null, 'VA');
insert into r select 'state:none leaves out lower-case codes too', not record_in_scope('state:none', null, 'va');
insert into r select 'state:none leaves out Puerto Rico', not record_in_scope('state:none', null, 'PR');
insert into r select 'state:VA is unchanged', record_in_scope('state:VA', null, 'va') and not record_in_scope('state:VA', null, 'MD');

-- One load per area, then two more loads without some records.
select from pg_temp.load('state:VA', jsonb_build_array(pg_temp.rec('v1', 'VA', -77.10), pg_temp.rec('v2', 'VA', -77.11)));
select from pg_temp.load('state:none', jsonb_build_array(pg_temp.rec('n1', null, -90.10), pg_temp.rec('n2', 'Ontario', -80.11)));
select from pg_temp.load('state:none', jsonb_build_array(pg_temp.rec('n1', null, -90.10)));
select from pg_temp.load('state:none', jsonb_build_array(pg_temp.rec('n1', null, -90.10)));
insert into r select 'no-state record missing from 2 loads of state:none is proposed', pg_temp.absent('n2');
insert into r select 'no-state record still listed is not proposed', not pg_temp.absent('n1');
insert into r select 'loads of state:none never touch a state''s records', not pg_temp.absent('v1') and not pg_temp.absent('v2');

select from pg_temp.load('state:VA', jsonb_build_array(pg_temp.rec('v1', 'VA', -77.10)));
select from pg_temp.load('state:VA', jsonb_build_array(pg_temp.rec('v1', 'VA', -77.10)));
insert into r select 'a state''s record missing from 2 loads of that state is proposed', pg_temp.absent('v2');
insert into r select 'loads of a state never touch no-state records', not pg_temp.absent('n1');

select case when ok then 'PASS ' else 'FAIL ' end || t from r;
