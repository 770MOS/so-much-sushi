-- Stand-ins for what a Supabase database provides before our migrations run:
-- the API roles, the extensions and auth schemas, auth.users and auth.uid().
-- Used only by the test runner (scripts/test-db.sh) on a plain PostGIS database.
do $$ begin
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;
exception when duplicate_object then null; end $$;
create schema if not exists extensions;
create schema if not exists auth;
grant usage on schema extensions, auth to anon, authenticated, service_role;
create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
