-- Extends the existing on_auth_user_created trigger (handle_new_user) to
-- also set profiles.handle from signup metadata, alongside the
-- display_name it already sets. Lets the sign-up form collect a required
-- username instead of leaving handle null for the post-signup banner to
-- catch.
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
    INSERT INTO public.profiles (id, display_name, handle)
    VALUES (new.id, new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'handle');
    RETURN new;
END;
$function$;

-- Not reachable via PostgREST's RPC surface regardless of grants (functions
-- returning `trigger` aren't exposed as /rpc/* endpoints), so this REVOKE
-- is defense-in-depth rather than a fix for something exploitable - added
-- for consistency with the standing rule in grants_reference.sql (every
-- SECURITY DEFINER function should explicitly revoke the implicit PUBLIC
-- execute grant CREATE FUNCTION leaves behind, unless anon access is
-- genuinely intended).
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
