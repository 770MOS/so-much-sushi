-- Full address shown in lists and on place pages.
\set ON_ERROR_STOP 1
\set QUIET 1
create temp table r(t text, ok boolean);
insert into r select 'street, town, state and ZIP',
  display_address('1401 Wilson Blvd Ste 110', 'Arlington', 'VA', '22209') = '1401 Wilson Blvd Ste 110, Arlington, VA 22209';
insert into r select 'ZIP+4 shown as 5 digits', display_address('1 Main St', 'Arlington', 'VA', '22209-1234') = '1 Main St, Arlington, VA 22209';
insert into r select 'missing ZIP', display_address('1 Main St', 'Arlington', 'VA', null) = '1 Main St, Arlington, VA';
insert into r select 'missing town', display_address('1 Main St', null, 'VA', '22209') = '1 Main St, VA 22209';
insert into r select 'missing street', display_address(null, 'Arlington', 'VA', '22209') = 'Arlington, VA 22209';
insert into r select 'blank pieces ignored', display_address('1 Main St', ' ', '', '22209') = '1 Main St, 22209';
insert into r select 'nothing at all', display_address(null, null, null, null) is null;
insert into r select 'town already in the street line: not repeated',
  display_address('3507 Columbia Pike, Arlington, VA 22204', 'Arlington', 'VA', '22204') = '3507 Columbia Pike, Arlington, VA 22204';
insert into r select 'search results carry the full address', exists (
  select 1 from pg_proc where proname = 'search_entities' and prosrc like '%display_address%');
select case when ok then 'PASS ' else 'FAIL ' end || t from r;
