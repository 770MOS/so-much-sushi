-- The same address written differently is recognised; different addresses are not.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
create function pg_temp.same(a text, b text) returns boolean language sql as $$ select values_equivalent('address', a, b) $$;
insert into r select 'Ctr = Center', pg_temp.same('5890 Kingstowne Ctr', '5890 Kingstowne Center');
insert into r select 'unit letter hyphenated', pg_temp.same('6973 Hechinger Dr', '6973-H Hechinger Dr.');
insert into r select 'unit letter attached', pg_temp.same('3556 S Jefferson St', '3556B S Jefferson St');
insert into r select 'unit letter with a suite after', pg_temp.same('6552 Little River Tpke', '6552-B Little River Turnpike');
insert into r select 'Space G = Ste G', pg_temp.same('7042 Little River Turnpike, Ste G', '7042 Little River Turnpike, Space G');
insert into r select 'Seventh = 7th, plus a suite', pg_temp.same('325 7th St NW', '325 Seventh Street NW, Suite 100');
insert into r select 'Eye Street = I St', pg_temp.same('1825 I St NW', '1825 Eye Street, NW');
insert into r select 'spacing inside a name', pg_temp.same('3046 Gate House Plz', '3046 Gatehouse Plaza')
  and pg_temp.same('5185 Mac Arthur Blvd Ste 104', '5185 MacArthur Blvd, Ste 104');
insert into r select 'place name before or after the street', pg_temp.same('Lee Heights Shops, 4526 Cherry Hill Rd', '4526 Cherry Hill Rd, Lee Heights Shops');
insert into r select 'still the same as before', pg_temp.same('725 King Street', '725 King St') and pg_temp.same('1 Main St', '1 Main St Ste 200');
insert into r select 'different lettered streets in DC stay different', not pg_temp.same('1825 I St NW', '1825 K St NW');
insert into r select 'different numbers stay different', not pg_temp.same('2000 S Bell St', '2050 S Bell St');
insert into r select 'different streets stay different', not pg_temp.same('3101 Richmond Hwy', '3101 Jefferson Davis Hwy')
  and not pg_temp.same('4435 Lehigh Rd', '4364 Knox Rd Suite 6');
insert into r select 'a longer street name is not a suite', not pg_temp.same('12 Oak St', '12 Oakwood St');
insert into r select 'unit letter is not a lettered street', not pg_temp.same('100 A St', '100 B St');
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
