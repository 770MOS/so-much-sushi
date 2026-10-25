-- Adding a place by hand.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
insert into entities (name, phone, location, main_category_id)
select 'Bean Counter Coffee', '7035550101', 'SRID=4326;POINT(-77.1 38.88)'::geography, id from categories where path = 'coffee';

insert into r select 'similar name nearby is shown', exists (select 1 from admin_similar_places(38.8801, -77.1001, 'Bean Counter') where reason = 'similar name nearby');
insert into r select 'same phone is shown even with another name', exists (select 1 from admin_similar_places(38.89, -77.11, 'Totally Different', '(703) 555-0101') where reason = 'same phone');
insert into r select 'unrelated name nearby is not shown', not exists (select 1 from admin_similar_places(38.8801, -77.1001, 'Pho Saigon'));

select admin_add_place('{"name": "Pho Saigon", "address": "1 Main St", "city": "Arlington", "state": "va", "postal_code": "22201",
  "phone": "", "lat": "38.8802", "lng": "-77.1002", "main_category": "restaurants"}'::jsonb, 'admin@test', 'walked past it') as id \gset
insert into r select 'place created with its values', (select name = 'Pho Saigon' and state = 'VA' and phone is null and status = 'active'
  and main_category_id = (select id from categories where path = 'restaurants') from entities where id = :'id');
insert into r select 'every value marked as edited by hand',
  (select array_agg(field order by field) from entity_field_provenance where entity_id = :'id' and method = 'manual')
  = array['address', 'categories', 'location', 'name', 'status'];
insert into r select 'ledger records who added it and why', exists (select 1 from change_events where entity_id = :'id'
  and event_type = 'new_candidate' and decided_by = 'admin@test' and evidence->>'note' = 'walked past it');
insert into r select 'shows in the place history', exists (select 1 from place_history(:'id') where kind = 'new_candidate');

do $$ begin
  begin perform admin_add_place('{"lat": 38.88, "lng": -77.1, "main_category": "coffee"}', 'a'); insert into r values ('a name is required', false);
  exception when others then insert into r values ('a name is required', true); end;
  begin perform admin_add_place('{"name": "X", "main_category": "coffee"}', 'a'); insert into r values ('a pin is required', false);
  exception when others then insert into r values ('a pin is required', true); end;
  begin perform admin_add_place('{"name": "X", "lat": 51.5, "lng": -0.1, "main_category": "coffee"}', 'a'); insert into r values ('a pin outside the US is refused', false);
  exception when others then insert into r values ('a pin outside the US is refused', true); end;
  begin perform admin_add_place('{"name": "X", "lat": 38.88, "lng": -77.1, "main_category": "coffee.espresso"}', 'a'); insert into r values ('main category must be a main category', false);
  exception when others then insert into r values ('main category must be a main category', true); end;
end $$;
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
