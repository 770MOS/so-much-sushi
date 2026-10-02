


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "ltree" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."get_entity_detail"("p_entity_id" "uuid") RETURNS TABLE("id" "uuid", "name" "text", "address" "text", "phone" "text", "website" "text", "hours" "jsonb", "attributes" "jsonb", "status" "text", "lat" double precision, "lng" double precision, "is_starred" boolean, "categories" "text"[], "category_paths" "text"[])
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
    SELECT
        e.id, e.name, e.address, e.phone, e.website, e.hours, e.attributes,
        e.status,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        EXISTS (
            SELECT 1 FROM stars s
            WHERE s.entity_id = e.id AND s.user_id = auth.uid()
        ) AS is_starred,
        (
            SELECT array_agg(cat.name ORDER BY cat.name)
            FROM entity_categories ec
            JOIN categories cat ON cat.id = ec.category_id
            WHERE ec.entity_id = e.id
        ) AS categories,
        (
            SELECT array_agg(cat2.path::text ORDER BY cat2.path)
            FROM entity_categories ec2
            JOIN categories cat2 ON cat2.id = ec2.category_id
            WHERE ec2.entity_id = e.id
        ) AS category_paths
    FROM entities e
    WHERE e.id = p_entity_id;
$$;


ALTER FUNCTION "public"."get_entity_detail"("p_entity_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_list_entities"("p_list_id" "uuid") RETURNS TABLE("entity_id" "uuid", "name" "text", "address" "text", "city" "text", "state" "text", "lat" double precision, "lng" double precision, "added_at" timestamp with time zone, "status" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
    SELECT e.id AS entity_id, e.name, e.address, e.city, e.state,
           ST_Y(e.location::geometry) AS lat, ST_X(e.location::geometry) AS lng,
           li.added_at, e.status
    FROM lists l
    JOIN list_items li ON li.list_id = l.id
    JOIN entities e ON e.id = li.entity_id
    WHERE l.id = p_list_id
      AND (
        l.owner_id = auth.uid()
        OR l.visibility = 'public'
        OR (
          l.visibility = 'friends'
          AND EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'accepted'
              AND ((f.requester_id = auth.uid() AND f.addressee_id = l.owner_id)
                OR (f.addressee_id = auth.uid() AND f.requester_id = l.owner_id))
          )
        )
      )
    ORDER BY li.added_at DESC;
$$;


ALTER FUNCTION "public"."get_list_entities"("p_list_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_list_meta"("p_list_id" "uuid") RETURNS TABLE("id" "uuid", "name" "text", "description" "text", "visibility" "text", "owner_id" "uuid", "owner_name" "text", "is_owner" boolean)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT l.id, l.name, l.description, l.visibility, l.owner_id,
           COALESCE(p.display_name, p.handle) AS owner_name,
           (l.owner_id = auth.uid()) AS is_owner
    FROM lists l
    JOIN profiles p ON p.id = l.owner_id
    WHERE l.id = p_list_id
      AND (
        l.owner_id = auth.uid()
        OR l.visibility = 'public'
        OR (
          l.visibility = 'friends'
          AND EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'accepted'
              AND ((f.requester_id = auth.uid() AND f.addressee_id = l.owner_id)
                OR (f.addressee_id = auth.uid() AND f.requester_id = l.owner_id))
          )
        )
      );
$$;


ALTER FUNCTION "public"."get_list_meta"("p_list_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_lists_shared_with_me"() RETURNS TABLE("id" "uuid", "name" "text", "description" "text", "owner_id" "uuid", "owner_name" "text", "item_count" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT l.id, l.name, l.description, l.owner_id,
           COALESCE(p.display_name, p.handle) AS owner_name,
           (SELECT count(*)::integer FROM list_items li WHERE li.list_id = l.id) AS item_count
    FROM lists l
    JOIN profiles p ON p.id = l.owner_id
    JOIN friendships f ON (
        (f.requester_id = auth.uid() AND f.addressee_id = l.owner_id)
        OR (f.addressee_id = auth.uid() AND f.requester_id = l.owner_id)
    )
    WHERE l.visibility = 'friends'
      AND f.status = 'accepted'
      AND l.owner_id <> auth.uid()
    ORDER BY l.created_at DESC;
$$;


ALTER FUNCTION "public"."get_lists_shared_with_me"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_home_location"() RETURNS TABLE("home_city" "text", "home_state" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT p.home_city, p.home_state
    FROM profiles p
    WHERE p.id = auth.uid();
$$;


ALTER FUNCTION "public"."get_my_home_location"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_saved_lists"() RETURNS TABLE("id" "uuid", "name" "text", "description" "text", "visibility" "text", "owner_id" "uuid", "owner_name" "text", "item_count" integer, "saved_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT l.id, l.name, l.description, l.visibility, l.owner_id,
           COALESCE(p.display_name, p.handle) AS owner_name,
           (SELECT count(*)::integer FROM list_items li WHERE li.list_id = l.id) AS item_count,
           sl.saved_at
    FROM saved_lists sl
    JOIN lists l    ON l.id = sl.list_id
    JOIN profiles p ON p.id = l.owner_id
    WHERE sl.user_id = auth.uid()
      AND (
          l.owner_id = auth.uid()
          OR l.visibility = 'public'
          OR (
              l.visibility = 'friends'
              AND EXISTS (
                  SELECT 1 FROM friendships f
                  WHERE f.status = 'accepted'
                    AND ((f.requester_id = auth.uid() AND f.addressee_id = l.owner_id)
                      OR (f.addressee_id = auth.uid() AND f.requester_id = l.owner_id))
              )
          )
      )
    ORDER BY sl.saved_at DESC;
$$;


ALTER FUNCTION "public"."get_my_saved_lists"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_starred_entities"() RETURNS TABLE("id" "uuid", "name" "text", "address" "text", "city" "text", "state" "text", "lat" double precision, "lng" double precision, "type_name" "text", "cuisine_name" "text", "recommended_by" "jsonb", "recommended_count" integer, "category_paths" "text"[])
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
    SELECT
        e.id, e.name, e.address, e.city, e.state,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        top.name AS type_name,
        c.name AS cuisine_name,
        (
            SELECT jsonb_agg(jsonb_build_object('name', name, 'handle', handle) ORDER BY starred_at)
            FROM (
                SELECT COALESCE(p.display_name, p.handle) AS name, p.handle AS handle, fs.created_at AS starred_at
                FROM stars fs
                JOIN profiles p ON p.id = fs.user_id
                JOIN friendships f ON (
                    (f.requester_id = auth.uid() AND f.addressee_id = fs.user_id)
                    OR (f.addressee_id = auth.uid() AND f.requester_id = fs.user_id)
                )
                WHERE fs.entity_id = e.id AND f.status = 'accepted'
                ORDER BY fs.created_at
                LIMIT 2
            ) top_two
        ) AS recommended_by,
        (
            SELECT count(*)::integer
            FROM stars fs2
            JOIN friendships f2 ON (
                (f2.requester_id = auth.uid() AND f2.addressee_id = fs2.user_id)
                OR (f2.addressee_id = auth.uid() AND f2.requester_id = fs2.user_id)
            )
            WHERE fs2.entity_id = e.id AND f2.status = 'accepted'
        ) AS recommended_count,
        (
            SELECT array_agg(cat2.path::text ORDER BY cat2.path)
            FROM entity_categories ec2
            JOIN categories cat2 ON cat2.id = ec2.category_id
            WHERE ec2.entity_id = e.id
        ) AS category_paths
    FROM stars s
    JOIN entities e            ON e.id = s.entity_id
    JOIN entity_categories ec  ON ec.entity_id = e.id
    JOIN categories c          ON c.id = ec.category_id
    JOIN categories top        ON top.path = subpath(c.path, 0, 1)
    WHERE s.user_id = auth.uid()
    ORDER BY e.name;
$$;


ALTER FUNCTION "public"."get_my_starred_entities"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_profile_lists"("target_user_id" "uuid") RETURNS TABLE("id" "uuid", "name" "text", "description" "text", "visibility" "text", "item_count" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT
        l.id, l.name, l.description, l.visibility,
        (SELECT count(*)::integer FROM list_items li WHERE li.list_id = l.id) AS item_count
    FROM lists l
    WHERE l.owner_id = target_user_id
      AND (
          target_user_id = auth.uid()
          OR l.visibility = 'public'
          OR (
              l.visibility = 'friends'
              AND EXISTS (
                  SELECT 1 FROM friendships f
                  WHERE f.status = 'accepted'
                    AND (
                        (f.requester_id = auth.uid() AND f.addressee_id = target_user_id)
                        OR (f.addressee_id = auth.uid() AND f.requester_id = target_user_id)
                    )
              )
          )
      )
    ORDER BY l.created_at DESC;
$$;


ALTER FUNCTION "public"."get_profile_lists"("target_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_profile_starred_entities"("target_user_id" "uuid") RETURNS TABLE("id" "uuid", "name" "text", "address" "text", "city" "text", "state" "text", "lat" double precision, "lng" double precision, "type_name" "text", "cuisine_name" "text", "status" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
    SELECT
        e.id, e.name, e.address, e.city, e.state,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        top.name AS type_name,
        c.name AS cuisine_name,
        e.status
    FROM stars s
    JOIN entities e            ON e.id = s.entity_id
    JOIN entity_categories ec  ON ec.entity_id = e.id
    JOIN categories c          ON c.id = ec.category_id
    JOIN categories top        ON top.path = subpath(c.path, 0, 1)
    WHERE s.user_id = target_user_id
      AND (
          target_user_id = auth.uid()
          OR EXISTS (
              SELECT 1 FROM friendships f
              WHERE f.status = 'accepted'
                AND (
                    (f.requester_id = auth.uid() AND f.addressee_id = target_user_id)
                    OR (f.addressee_id = auth.uid() AND f.requester_id = target_user_id)
                )
          )
      )
    ORDER BY e.name;
$$;


ALTER FUNCTION "public"."get_profile_starred_entities"("target_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, handle, first_name, last_name)
    VALUES (
        new.id,
        new.raw_user_meta_data->>'first_name',
        new.raw_user_meta_data->>'handle',
        new.raw_user_meta_data->>'first_name',
        new.raw_user_meta_data->>'last_name'
    );
    RETURN new;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_entities"("ref_lat" double precision, "ref_lng" double precision, "radius_miles" double precision, "category_path" "public"."ltree" DEFAULT NULL::"public"."ltree", "show_hidden" boolean DEFAULT false, "recommended_only" boolean DEFAULT false, "starred_only" boolean DEFAULT false, "name_query" "text" DEFAULT NULL::"text") RETURNS TABLE("id" "uuid", "name" "text", "address" "text", "miles" numeric, "lat" double precision, "lng" double precision, "is_starred" boolean, "is_hidden" boolean, "recommended_by" "jsonb", "recommended_count" integer, "status" "text", "categories" "text"[], "category_paths" "text"[])
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
    SELECT DISTINCT
        e.id, e.name, e.address,
        round((ST_Distance(
            e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography
        ) / 1609.34)::numeric, 2) AS miles,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        EXISTS (
            SELECT 1 FROM stars s
            WHERE s.entity_id = e.id AND s.user_id = auth.uid()
        ) AS is_starred,
        EXISTS (
            SELECT 1 FROM hidden_entities h
            WHERE h.entity_id = e.id AND h.user_id = auth.uid()
        ) AS is_hidden,
        (
            SELECT jsonb_agg(jsonb_build_object('name', name, 'handle', handle) ORDER BY starred_at)
            FROM (
                SELECT COALESCE(p.display_name, p.handle) AS name, p.handle AS handle, fs.created_at AS starred_at
                FROM stars fs
                JOIN profiles p ON p.id = fs.user_id
                JOIN friendships f ON (
                    (f.requester_id = auth.uid() AND f.addressee_id = fs.user_id)
                    OR (f.addressee_id = auth.uid() AND f.requester_id = fs.user_id)
                )
                WHERE fs.entity_id = e.id AND f.status = 'accepted'
                ORDER BY fs.created_at
                LIMIT 2
            ) top_two
        ) AS recommended_by,
        (
            SELECT count(*)::integer
            FROM stars fs2
            JOIN friendships f2 ON (
                (f2.requester_id = auth.uid() AND f2.addressee_id = fs2.user_id)
                OR (f2.addressee_id = auth.uid() AND f2.requester_id = fs2.user_id)
            )
            WHERE fs2.entity_id = e.id AND f2.status = 'accepted'
        ) AS recommended_count,
        e.status,
        (
            SELECT array_agg(cat.name ORDER BY cat.name)
            FROM entity_categories ec2
            JOIN categories cat ON cat.id = ec2.category_id
            WHERE ec2.entity_id = e.id
        ) AS categories,
        (
            SELECT array_agg(cat3.path::text ORDER BY cat3.path)
            FROM entity_categories ec3
            JOIN categories cat3 ON cat3.id = ec3.category_id
            WHERE ec3.entity_id = e.id
        ) AS category_paths
    FROM entities e
    JOIN entity_categories ec ON ec.entity_id = e.id
    JOIN categories c         ON c.id = ec.category_id
    WHERE (category_path IS NULL OR c.path <@ category_path)
      AND e.status <> 'permanently_closed'
      AND ST_DWithin(
          e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography,
          radius_miles * 1609.34
      )
      AND (
          show_hidden
          OR NOT EXISTS (
              SELECT 1 FROM hidden_entities h2
              WHERE h2.entity_id = e.id AND h2.user_id = auth.uid()
          )
      )
      AND (
          NOT recommended_only
          OR EXISTS (
              SELECT 1 FROM stars fs3
              JOIN friendships f3 ON (
                  (f3.requester_id = auth.uid() AND f3.addressee_id = fs3.user_id)
                  OR (f3.addressee_id = auth.uid() AND f3.requester_id = fs3.user_id)
              )
              WHERE fs3.entity_id = e.id AND f3.status = 'accepted'
          )
      )
      AND (
          NOT starred_only
          OR EXISTS (
              SELECT 1 FROM stars s4
              WHERE s4.entity_id = e.id AND s4.user_id = auth.uid()
          )
      )
      AND (
          name_query IS NULL
          OR trim(name_query) = ''
          OR e.name ILIKE '%' || trim(name_query) || '%'
      )
    ORDER BY miles;
$$;


ALTER FUNCTION "public"."search_entities"("ref_lat" double precision, "ref_lng" double precision, "radius_miles" double precision, "category_path" "public"."ltree", "show_hidden" boolean, "recommended_only" boolean, "starred_only" boolean, "name_query" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "parent_id" "uuid",
    "name" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "path" "public"."ltree" NOT NULL
);


ALTER TABLE "public"."categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."entities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "address" "text",
    "phone" "text",
    "website" "text",
    "location" "extensions"."geography"(Point,4326),
    "hours" "jsonb",
    "attributes" "jsonb",
    "source" "text",
    "last_verified" timestamp with time zone,
    "city" "text",
    "state" "text",
    "needs_review" boolean DEFAULT false NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "source_code" "text",
    "osm_id" "text",
    CONSTRAINT "entities_source_code_check" CHECK ((("source_code" = ANY (ARRAY['osm'::"text", 'manual'::"text"])) OR ("source_code" IS NULL))),
    CONSTRAINT "entities_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'temporarily_closed'::"text", 'permanently_closed'::"text"])))
);


ALTER TABLE "public"."entities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."entity_categories" (
    "entity_id" "uuid" NOT NULL,
    "category_id" "uuid" NOT NULL
);


ALTER TABLE "public"."entity_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."friendships" (
    "requester_id" "uuid" NOT NULL,
    "addressee_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "friendships_check" CHECK (("requester_id" <> "addressee_id")),
    CONSTRAINT "friendships_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'blocked'::"text"])))
);


ALTER TABLE "public"."friendships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hidden_entities" (
    "user_id" "uuid" NOT NULL,
    "entity_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."hidden_entities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."list_items" (
    "list_id" "uuid" NOT NULL,
    "entity_id" "uuid" NOT NULL,
    "note" "text",
    "position" integer,
    "added_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."list_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lists" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid",
    "name" "text" NOT NULL,
    "description" "text",
    "visibility" "text" DEFAULT 'private'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_default_list" boolean DEFAULT false NOT NULL,
    CONSTRAINT "lists_visibility_check" CHECK (("visibility" = ANY (ARRAY['private'::"text", 'friends'::"text", 'public'::"text"])))
);


ALTER TABLE "public"."lists" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_addons" (
    "id" character varying(20) NOT NULL,
    "addon_key" character varying(255) NOT NULL,
    "title" character varying(255),
    "description" "text",
    "stripe_product_id" character varying(255) NOT NULL,
    "prices" "text",
    "is_active" boolean DEFAULT true,
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_addons" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_api_token_scopes" (
    "id" character varying(20) NOT NULL,
    "fk_api_token_id" character varying(20) NOT NULL,
    "resource_type" character varying(20) NOT NULL,
    "resource_id" character varying(20) NOT NULL,
    "permissions" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_api_token_scopes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_api_tokens" (
    "id" integer NOT NULL,
    "base_id" character varying(20),
    "db_alias" character varying(255),
    "description" character varying(255),
    "permissions" "text",
    "token" "text",
    "expiry" character varying(255),
    "enabled" boolean DEFAULT true,
    "fk_user_id" character varying(20),
    "fk_workspace_id" character varying(20),
    "fk_sso_client_id" character varying(20),
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "token_hash" character varying(64),
    "token_prefix" character varying(20),
    "last_used_at" timestamp with time zone
);


ALTER TABLE "public"."nc_api_tokens" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."nc_api_tokens_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."nc_api_tokens_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."nc_api_tokens_id_seq" OWNED BY "public"."nc_api_tokens"."id";



CREATE TABLE IF NOT EXISTS "public"."nc_audit_v2" (
    "id" "uuid" NOT NULL,
    "user" character varying(255),
    "ip" character varying(255),
    "source_id" character varying(20),
    "base_id" character varying(20),
    "fk_model_id" character varying(20),
    "row_id" character varying(255),
    "op_type" character varying(255),
    "op_sub_type" character varying(255),
    "status" character varying(255),
    "description" "text",
    "details" "text",
    "fk_user_id" character varying(20),
    "fk_ref_id" character varying(20),
    "fk_parent_id" "uuid",
    "fk_workspace_id" character varying(20),
    "fk_org_id" character varying(20),
    "user_agent" "text",
    "version" smallint DEFAULT '0'::smallint,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "old_id" character varying(20)
);


ALTER TABLE "public"."nc_audit_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_automation_executions" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_workflow_id" character varying(20) NOT NULL,
    "workflow_data" "text",
    "execution_data" "text",
    "finished" boolean DEFAULT false,
    "started_at" timestamp with time zone,
    "finished_at" timestamp with time zone,
    "status" character varying(50),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "resume_at" timestamp with time zone,
    "error_notified_at" timestamp with time zone
);


ALTER TABLE "public"."nc_automation_executions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_automation_subscribers" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_automation_id" character varying(20),
    "fk_user_id" character varying(20),
    "notify_on_error" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_automation_subscribers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_automations" (
    "id" character varying(20) NOT NULL,
    "title" character varying(255),
    "description" "text",
    "meta" "text",
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "order" real,
    "type" character varying(20),
    "created_by" character varying(20),
    "updated_by" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "enabled" boolean DEFAULT false,
    "nodes" "text",
    "edges" "text",
    "draft" "text",
    "config" "text",
    "script" "text",
    "draft_reminder_sent_at" timestamp with time zone,
    "deleted" boolean
);


ALTER TABLE "public"."nc_automations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_base_users_v2" (
    "base_id" character varying(20) NOT NULL,
    "fk_user_id" character varying(20) NOT NULL,
    "roles" "text",
    "starred" boolean,
    "pinned" boolean,
    "group" character varying(255),
    "color" character varying(255),
    "order" real,
    "hidden" real,
    "opened_date" timestamp with time zone,
    "invited_by" character varying(20),
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_base_users_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_base_variables" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "key" character varying(255),
    "value" "text",
    "description" "text",
    "inheritance" character varying(20) DEFAULT 'fixed'::character varying,
    "type" character varying(20) DEFAULT 'text'::character varying,
    "order" real,
    "default_value" "text",
    "is_overridden" boolean DEFAULT false,
    "is_inherited" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_base_variables" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_bases_v2" (
    "id" character varying(128) NOT NULL,
    "title" character varying(255),
    "prefix" character varying(255),
    "status" character varying(255),
    "description" "text",
    "meta" "text",
    "color" character varying(255),
    "uuid" character varying(255),
    "password" character varying(255),
    "roles" character varying(255),
    "deleted" boolean DEFAULT false,
    "is_meta" boolean,
    "order" real,
    "type" character varying(200),
    "fk_workspace_id" character varying(20),
    "is_snapshot" boolean DEFAULT false,
    "fk_custom_url_id" character varying(20),
    "version" smallint DEFAULT '2'::smallint,
    "default_role" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "managed_app_master" boolean DEFAULT false,
    "managed_app_id" character varying(20),
    "managed_app_version_id" character varying(20),
    "auto_update" boolean DEFAULT true,
    "is_sandbox_production" boolean DEFAULT false,
    "is_sandbox" boolean DEFAULT false
);


ALTER TABLE "public"."nc_bases_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_bookmark_groups" (
    "id" character varying(20) NOT NULL,
    "fk_user_id" character varying(20) NOT NULL,
    "name" character varying(100) NOT NULL,
    "order" real DEFAULT '0'::real,
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_bookmark_groups" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_bookmarks" (
    "id" character varying(20) NOT NULL,
    "fk_user_id" character varying(20) NOT NULL,
    "fk_group_id" character varying(20) NOT NULL,
    "title" character varying(255) DEFAULT NULL::character varying,
    "target_type" character varying(20) NOT NULL,
    "target_id" character varying(128) NOT NULL,
    "icon" character varying(255) DEFAULT NULL::character varying,
    "icon_color" character varying(50) DEFAULT NULL::character varying,
    "icon_type" character varying(20) DEFAULT NULL::character varying,
    "order" real DEFAULT '0'::real,
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_bookmarks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_calendar_view_columns_v2" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "fk_view_id" character varying(20),
    "fk_column_id" character varying(20),
    "show" boolean,
    "bold" boolean,
    "underline" boolean,
    "italic" boolean,
    "order" real,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_calendar_view_columns_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_calendar_view_range_v2" (
    "id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "fk_to_column_id" character varying(20),
    "label" character varying(40),
    "fk_from_column_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_calendar_view_range_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_calendar_view_v2" (
    "fk_view_id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "title" character varying(255),
    "fk_cover_image_col_id" character varying(20),
    "meta" "text",
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
);


ALTER TABLE "public"."nc_calendar_view_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_chat_messages" (
    "id" character varying(20) NOT NULL,
    "fk_session_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20) NOT NULL,
    "role" character varying(20) NOT NULL,
    "content" "text",
    "parts" "text",
    "model" character varying(100),
    "input_tokens" integer DEFAULT 0,
    "output_tokens" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "base_id" character varying(20),
    "bt_span_id" character varying(100),
    "files" "text",
    "created_files" "text",
    "ui_context_record" "text"
);


ALTER TABLE "public"."nc_chat_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_chat_sessions" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20) NOT NULL,
    "fk_user_id" character varying(20),
    "title" character varying(255),
    "summary" "text",
    "total_input_tokens" integer DEFAULT 0,
    "total_output_tokens" integer DEFAULT 0,
    "message_count" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "meta" "text",
    "base_id" character varying(20)
);


ALTER TABLE "public"."nc_chat_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_col_barcode_v2" (
    "id" character varying(20) NOT NULL,
    "fk_column_id" character varying(20),
    "fk_barcode_value_column_id" character varying(20),
    "barcode_format" character varying(15),
    "deleted" boolean,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "error" "text"
);


ALTER TABLE "public"."nc_col_barcode_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_col_button_v2" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "type" character varying(255),
    "label" "text",
    "theme" character varying(255),
    "color" character varying(255),
    "icon" character varying(255),
    "formula" "text",
    "formula_raw" "text",
    "error" character varying(255),
    "parsed_tree" "text",
    "fk_webhook_id" character varying(20),
    "fk_column_id" character varying(20),
    "fk_integration_id" character varying(20),
    "model" character varying(255),
    "output_column_ids" "text",
    "fk_workspace_id" character varying(20),
    "fk_script_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_col_button_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_col_formula_v2" (
    "id" character varying(20) NOT NULL,
    "fk_column_id" character varying(20),
    "formula" "text" NOT NULL,
    "formula_raw" "text",
    "error" "text",
    "deleted" boolean,
    "order" real,
    "parsed_tree" "text",
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_col_formula_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_col_long_text_v2" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_model_id" character varying(20),
    "fk_column_id" character varying(20),
    "fk_integration_id" character varying(20),
    "model" character varying(255),
    "prompt" "text",
    "prompt_raw" "text",
    "error" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_col_long_text_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_col_lookup_v2" (
    "id" character varying(20) NOT NULL,
    "fk_column_id" character varying(20),
    "fk_relation_column_id" character varying(20),
    "fk_lookup_column_id" character varying(20),
    "deleted" boolean,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "error" "text"
);


ALTER TABLE "public"."nc_col_lookup_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_col_qrcode_v2" (
    "id" character varying(20) NOT NULL,
    "fk_column_id" character varying(20),
    "fk_qr_value_column_id" character varying(20),
    "deleted" boolean,
    "order" real,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "error" "text"
);


ALTER TABLE "public"."nc_col_qrcode_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_col_relations_v2" (
    "id" character varying(20) NOT NULL,
    "ref_db_alias" character varying(255),
    "type" character varying(255),
    "virtual" boolean,
    "db_type" character varying(255),
    "fk_column_id" character varying(20),
    "fk_related_model_id" character varying(20),
    "fk_child_column_id" character varying(20),
    "fk_parent_column_id" character varying(20),
    "fk_mm_model_id" character varying(20),
    "fk_mm_child_column_id" character varying(20),
    "fk_mm_parent_column_id" character varying(20),
    "ur" character varying(255),
    "dr" character varying(255),
    "fk_index_name" character varying(255),
    "deleted" boolean,
    "fk_target_view_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "fk_related_base_id" character varying(20),
    "fk_mm_base_id" character varying(20),
    "fk_related_source_id" character varying(20),
    "fk_mm_source_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "version" integer DEFAULT 1,
    "fk_display_value_column_id" character varying(20)
);


ALTER TABLE "public"."nc_col_relations_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_col_rollup_v2" (
    "id" character varying(20) NOT NULL,
    "fk_column_id" character varying(20),
    "fk_relation_column_id" character varying(20),
    "fk_rollup_column_id" character varying(20),
    "rollup_function" character varying(255),
    "deleted" boolean,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "error" "text"
);


ALTER TABLE "public"."nc_col_rollup_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_col_select_options_v2" (
    "id" character varying(20) NOT NULL,
    "fk_column_id" character varying(20),
    "title" character varying(255),
    "color" character varying(255),
    "order" real,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_col_select_options_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_columns_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_model_id" character varying(20),
    "title" character varying(255),
    "column_name" character varying(255),
    "uidt" character varying(255),
    "dt" character varying(255),
    "np" character varying(255),
    "ns" character varying(255),
    "clen" character varying(255),
    "cop" character varying(255),
    "pk" boolean,
    "pv" boolean,
    "rqd" boolean,
    "un" boolean,
    "ct" "text",
    "ai" boolean,
    "unique" boolean,
    "cdf" "text",
    "cc" "text",
    "csn" character varying(255),
    "dtx" character varying(255),
    "dtxp" "text",
    "dtxs" character varying(255),
    "au" boolean,
    "validate" "text",
    "virtual" boolean,
    "deleted" boolean,
    "system" boolean DEFAULT false,
    "order" real,
    "meta" "text",
    "description" "text",
    "readonly" boolean DEFAULT false,
    "fk_workspace_id" character varying(20),
    "custom_index_name" character varying(64),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "internal_meta" "text"
);


ALTER TABLE "public"."nc_columns_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_comment_reactions" (
    "id" character varying(20) NOT NULL,
    "row_id" character varying(255),
    "comment_id" character varying(20),
    "source_id" character varying(20),
    "fk_model_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "reaction" character varying(255),
    "created_by" character varying(255),
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_comment_reactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_comments" (
    "id" character varying(20) NOT NULL,
    "row_id" character varying(255),
    "comment" "text",
    "created_by" character varying(20),
    "created_by_email" character varying(255),
    "resolved_by" character varying(20),
    "resolved_by_email" character varying(255),
    "parent_comment_id" character varying(20),
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_model_id" character varying(20),
    "is_deleted" boolean,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "fk_doc_id" character varying(20),
    "anchor_id" character varying(20)
);


ALTER TABLE "public"."nc_comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_custom_urls_v2" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_model_id" character varying(20),
    "view_id" character varying(20),
    "original_path" character varying(255),
    "custom_path" character varying(255),
    "fk_dashboard_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_custom_urls_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_dashboards_v2" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "title" character varying(255) NOT NULL,
    "description" "text",
    "meta" "text",
    "order" integer,
    "created_by" character varying(20),
    "owned_by" character varying(20),
    "uuid" character varying(255),
    "password" character varying(255),
    "fk_custom_url_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "deleted" boolean
);


ALTER TABLE "public"."nc_dashboards_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_data_reflection" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "username" character varying(255),
    "password" character varying(255),
    "database" character varying(255),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_data_reflection" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_date_dependency_v2" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "fk_model_id" character varying(20),
    "fk_start_date_field_id" character varying(20),
    "fk_end_date_field_id" character varying(20),
    "fk_duration_field_id" character varying(20),
    "fk_dependency_linkrow_field_id" character varying(20),
    "dependency_linkrow_role" character varying(20) DEFAULT 'predecessors'::character varying,
    "dependency_connection_type" character varying(20) DEFAULT 'end-to-start'::character varying,
    "dependency_buffer_type" character varying(20) DEFAULT 'none'::character varying,
    "dependency_buffer_days" integer DEFAULT 0,
    "include_weekends" boolean DEFAULT true,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "fk_gantt_view_id" character varying(20)
);


ALTER TABLE "public"."nc_date_dependency_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_db_servers" (
    "id" character varying(20) NOT NULL,
    "title" character varying(255),
    "is_shared" boolean DEFAULT true,
    "max_tenant_count" integer,
    "current_tenant_count" integer DEFAULT 0,
    "config" "text",
    "conditions" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_db_servers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_dependency_tracker" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "source_type" character varying(50) NOT NULL,
    "source_id" character varying(20) NOT NULL,
    "dependent_type" character varying(50) NOT NULL,
    "dependent_id" character varying(20) NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "queryable_field_0" "text",
    "queryable_field_1" "text",
    "meta" "text",
    "queryable_field_2" timestamp with time zone
);


ALTER TABLE "public"."nc_dependency_tracker" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_disabled_models_for_role_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "role" character varying(45),
    "disabled" boolean DEFAULT true,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_disabled_models_for_role_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_doc_content_v2" (
    "fk_doc_id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "content" "jsonb",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "yjs_state" "bytea"
);


ALTER TABLE "public"."nc_doc_content_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_doc_revisions_v2" (
    "id" character varying(40) NOT NULL,
    "fk_doc_id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "version" integer NOT NULL,
    "content" "jsonb",
    "title" character varying(255),
    "created_by" character varying(20),
    "fk_tab_id" character varying(36),
    "source" character varying(16) DEFAULT 'auto'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_doc_revisions_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_docs_v2" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "title" character varying(512),
    "meta" "text",
    "order" real,
    "parent_id" character varying(20),
    "deleted" boolean DEFAULT false,
    "has_children" boolean DEFAULT false,
    "version" integer DEFAULT 1,
    "created_by" character varying(20),
    "updated_by" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_docs_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_extensions" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_user_id" character varying(20),
    "extension_id" character varying(255),
    "title" character varying(255),
    "kv_store" "text",
    "meta" "text",
    "order" real,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "deleted" boolean
);


ALTER TABLE "public"."nc_extensions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_file_references" (
    "id" character varying(20) NOT NULL,
    "storage" character varying(255),
    "file_url" "text",
    "file_size" integer,
    "fk_user_id" character varying(20),
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20),
    "source_id" character varying(20),
    "fk_model_id" character varying(20),
    "fk_column_id" character varying(20),
    "is_external" boolean DEFAULT false,
    "deleted" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "fk_doc_id" character varying(20),
    "fk_session_id" character varying(20),
    "soft_deleted" boolean DEFAULT false,
    "fk_row_id" character varying(255),
    "fk_revision_id" character varying(40)
);


ALTER TABLE "public"."nc_file_references" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_filter_exp_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "fk_hook_id" character varying(20),
    "fk_column_id" character varying(20),
    "fk_parent_id" character varying(20),
    "logical_op" character varying(255),
    "comparison_op" character varying(255),
    "value" "text",
    "is_group" boolean,
    "order" real,
    "comparison_sub_op" character varying(255),
    "fk_link_col_id" character varying(20),
    "fk_value_col_id" character varying(20),
    "fk_parent_column_id" character varying(20),
    "fk_workspace_id" character varying(20),
    "fk_row_color_condition_id" character varying(20),
    "fk_widget_id" character varying(20),
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "enabled" boolean DEFAULT true,
    "fk_rls_policy_id" character varying(20),
    "fk_level_id" character varying(20),
    "fk_button_col_id" character varying(20)
);


ALTER TABLE "public"."nc_filter_exp_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_follower" (
    "fk_user_id" character varying(20) NOT NULL,
    "fk_follower_id" character varying(20) NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_follower" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_form_view_columns_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "fk_column_id" character varying(20),
    "uuid" character varying(255),
    "label" "text",
    "help" "text",
    "description" "text",
    "required" boolean,
    "show" boolean,
    "order" real,
    "meta" "text",
    "enable_scanner" boolean,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "row_id" character varying(32)
);


ALTER TABLE "public"."nc_form_view_columns_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_form_view_v2" (
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20) NOT NULL,
    "heading" character varying(255),
    "subheading" "text",
    "success_msg" "text",
    "redirect_url" "text",
    "redirect_after_secs" character varying(255),
    "email" "text",
    "submit_another_form" boolean,
    "show_blank_form" boolean,
    "uuid" character varying(255),
    "banner_image_url" "text",
    "logo_url" "text",
    "meta" "text",
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "starts_at" timestamp with time zone,
    "expires_at" timestamp with time zone,
    "save_draft_to_browser" boolean DEFAULT true
);


ALTER TABLE "public"."nc_form_view_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_gallery_view_columns_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "fk_column_id" character varying(20),
    "uuid" character varying(255),
    "label" character varying(255),
    "help" character varying(255),
    "show" boolean,
    "order" real,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_gallery_view_columns_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_gallery_view_v2" (
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20) NOT NULL,
    "next_enabled" boolean,
    "prev_enabled" boolean,
    "cover_image_idx" integer,
    "fk_cover_image_col_id" character varying(20),
    "cover_image" character varying(255),
    "restrict_types" character varying(255),
    "restrict_size" character varying(255),
    "restrict_number" character varying(255),
    "public" boolean,
    "dimensions" character varying(255),
    "responsive_columns" character varying(255),
    "meta" "text",
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_gallery_view_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_gantt_view_columns_v2" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "fk_view_id" character varying(20),
    "fk_column_id" character varying(20),
    "show" boolean,
    "bold" boolean,
    "underline" boolean,
    "italic" boolean,
    "order" real,
    "group_by" boolean,
    "group_by_order" real,
    "group_by_sort" character varying(4),
    "aggregation" character varying(20),
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "group_by_enabled" boolean
);


ALTER TABLE "public"."nc_gantt_view_columns_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_gantt_view_v2" (
    "fk_view_id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "title" character varying(255),
    "meta" "text",
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_gantt_view_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_gcp_marketplace_accounts" (
    "id" character varying(20) NOT NULL,
    "procurement_account_id" character varying(255) NOT NULL,
    "fk_user_id" character varying(20),
    "state" character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    "link_token" character varying(64),
    "link_token_expires_at" timestamp with time zone,
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_gcp_marketplace_accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_gcp_marketplace_entitlements" (
    "id" character varying(20) NOT NULL,
    "entitlement_id" character varying(255) NOT NULL,
    "fk_gcp_account_id" character varying(20) NOT NULL,
    "fk_installation_id" character varying(20),
    "plan" character varying(255),
    "state" character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_gcp_marketplace_entitlements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_grid_view_columns_v2" (
    "id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "fk_column_id" character varying(20),
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "uuid" character varying(255),
    "label" character varying(255),
    "help" character varying(255),
    "width" character varying(255) DEFAULT '200px'::character varying,
    "show" boolean,
    "order" real,
    "group_by" boolean,
    "group_by_order" real,
    "group_by_sort" character varying(255),
    "aggregation" character varying(30) DEFAULT NULL::character varying,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "group_by_enabled" boolean
);


ALTER TABLE "public"."nc_grid_view_columns_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_grid_view_v2" (
    "fk_view_id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "uuid" character varying(255),
    "meta" "text",
    "row_height" integer,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_grid_view_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_hook_logs_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_hook_id" character varying(20),
    "type" character varying(255),
    "event" character varying(255),
    "operation" character varying(255),
    "test_call" boolean DEFAULT true,
    "payload" "text",
    "conditions" "text",
    "notification" "text",
    "error_code" character varying(255),
    "error_message" character varying(255),
    "error" "text",
    "execution_time" integer,
    "response" "text",
    "triggered_by" character varying(255),
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "error_notified_at" timestamp with time zone
);


ALTER TABLE "public"."nc_hook_logs_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_hook_trigger_fields" (
    "fk_hook_id" character varying(20) NOT NULL,
    "fk_column_id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20) NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_hook_trigger_fields" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_hooks_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_model_id" character varying(20),
    "title" character varying(255),
    "description" character varying(255),
    "env" character varying(255) DEFAULT 'all'::character varying,
    "type" character varying(255),
    "event" character varying(255),
    "operation" character varying(255),
    "async" boolean DEFAULT false,
    "payload" boolean DEFAULT true,
    "url" "text",
    "headers" "text",
    "condition" boolean DEFAULT false,
    "notification" "text",
    "retries" integer DEFAULT 0,
    "retry_interval" integer DEFAULT 60000,
    "timeout" integer DEFAULT 60000,
    "active" boolean DEFAULT true,
    "version" character varying(255),
    "trigger_field" boolean DEFAULT false,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "deleted" boolean
);


ALTER TABLE "public"."nc_hooks_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_installations" (
    "id" character varying(20) NOT NULL,
    "fk_subscription_id" character varying(20),
    "licensed_to" character varying(255) NOT NULL,
    "license_key" character varying(255) NOT NULL,
    "installation_secret" character varying(255),
    "installed_at" timestamp with time zone,
    "last_seen_at" timestamp with time zone,
    "expires_at" timestamp with time zone,
    "license_type" character varying(255) NOT NULL,
    "status" character varying(255) DEFAULT 'active'::character varying NOT NULL,
    "seat_count" integer DEFAULT 0 NOT NULL,
    "config" "text",
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "fk_user_id" character varying(20),
    "min_seats" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."nc_installations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_integration_links_v2" (
    "id" character varying(20) NOT NULL,
    "fk_integration_id" character varying(20),
    "base_id" character varying(20),
    "fk_workspace_id" character varying(20),
    "created_by" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_integration_links_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_integrations_store_v2" (
    "id" character varying(20) NOT NULL,
    "fk_integration_id" character varying(20),
    "type" character varying(20),
    "sub_type" character varying(20),
    "fk_workspace_id" character varying(20),
    "fk_user_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "slot_0" "text",
    "slot_1" "text",
    "slot_2" "text",
    "slot_3" "text",
    "slot_4" "text",
    "slot_5" integer,
    "slot_6" integer,
    "slot_7" integer,
    "slot_8" integer,
    "slot_9" integer
);


ALTER TABLE "public"."nc_integrations_store_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_integrations_v2" (
    "id" character varying(20) NOT NULL,
    "title" character varying(128),
    "config" "text",
    "meta" "text",
    "type" character varying(20),
    "sub_type" character varying(20),
    "fk_workspace_id" character varying(20),
    "is_private" boolean DEFAULT false,
    "deleted" boolean DEFAULT false,
    "created_by" character varying(20),
    "order" real,
    "is_default" boolean DEFAULT false,
    "is_encrypted" boolean DEFAULT false,
    "is_global" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "is_restricted" boolean DEFAULT false
);


ALTER TABLE "public"."nc_integrations_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_jobs" (
    "id" character varying(20) NOT NULL,
    "job" character varying(255),
    "status" character varying(20),
    "result" "text",
    "fk_user_id" character varying(20),
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_jobs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_kanban_view_columns_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "fk_column_id" character varying(20),
    "uuid" character varying(255),
    "label" character varying(255),
    "help" character varying(255),
    "show" boolean,
    "order" real,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_kanban_view_columns_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_kanban_view_v2" (
    "fk_view_id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "show" boolean,
    "order" real,
    "uuid" character varying(255),
    "title" character varying(255),
    "public" boolean,
    "password" character varying(255),
    "show_all_fields" boolean,
    "fk_grp_col_id" character varying(20),
    "fk_cover_image_col_id" character varying(20),
    "meta" "text",
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_kanban_view_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_list_view_columns_v2" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "source_id" character varying(128),
    "fk_view_id" character varying(20),
    "fk_column_id" character varying(20),
    "fk_level_id" character varying(20),
    "show" boolean,
    "order" real,
    "width" character varying(255),
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_list_view_columns_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_list_view_levels_v2" (
    "id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "level" integer,
    "fk_model_id" character varying(20),
    "fk_link_column_id" character varying(20),
    "enable_nested_records" boolean,
    "fk_self_link_column_id" character varying(20),
    "wrap_headers" boolean,
    "meta" "text",
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_list_view_levels_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_list_view_v2" (
    "fk_view_id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "source_id" character varying(128),
    "title" character varying(255),
    "show_empty_parents" boolean,
    "row_height" integer,
    "fk_prefix_column_id" character varying(20),
    "meta" "text",
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_list_view_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_mail_sends" (
    "id" character varying(20) NOT NULL,
    "event" character varying(64) NOT NULL,
    "fk_user_id" character varying(20),
    "to_email" character varying(320) NOT NULL,
    "subject" "text",
    "status" character varying(16) NOT NULL,
    "dedupe_key" character varying(255),
    "payload_json" "text",
    "ses_message_id" character varying(128),
    "error" "text",
    "attempts" integer DEFAULT 0 NOT NULL,
    "scheduled_for" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "sent_at" timestamp with time zone
);


ALTER TABLE "public"."nc_mail_sends" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_managed_app_deployment_logs" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_managed_app_id" character varying(20) NOT NULL,
    "from_version_id" character varying(20),
    "to_version_id" character varying(20) NOT NULL,
    "status" character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    "deployment_type" character varying(20) NOT NULL,
    "error_message" "text",
    "deployment_log" "text",
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone
);


ALTER TABLE "public"."nc_managed_app_deployment_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_managed_app_versions" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20) NOT NULL,
    "fk_managed_app_id" character varying(20) NOT NULL,
    "version" character varying(20) NOT NULL,
    "version_number" integer NOT NULL,
    "status" character varying(20) DEFAULT 'draft'::character varying NOT NULL,
    "schema" "text",
    "release_notes" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "published_at" timestamp with time zone
);


ALTER TABLE "public"."nc_managed_app_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_managed_apps" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "title" character varying(255) NOT NULL,
    "description" "text",
    "created_by" character varying(20) NOT NULL,
    "visibility" character varying(20) DEFAULT 'private'::character varying NOT NULL,
    "category" character varying(255),
    "install_count" integer DEFAULT 0,
    "meta" "text",
    "deleted" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "published_at" timestamp with time zone
);


ALTER TABLE "public"."nc_managed_apps" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_map_view_columns_v2" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "project_id" character varying(128),
    "fk_view_id" character varying(20),
    "fk_column_id" character varying(20),
    "uuid" character varying(255),
    "label" character varying(255),
    "help" character varying(255),
    "show" boolean,
    "order" real,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "source_id" character varying(20)
);


ALTER TABLE "public"."nc_map_view_columns_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_map_view_v2" (
    "fk_view_id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "uuid" character varying(255),
    "title" character varying(255),
    "fk_geo_data_col_id" character varying(20),
    "meta" "text",
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
);


ALTER TABLE "public"."nc_map_view_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_mcp_tokens" (
    "id" character varying(20) NOT NULL,
    "title" character varying(512),
    "base_id" character varying(20) NOT NULL,
    "token" character varying(32),
    "fk_workspace_id" character varying(20),
    "order" real,
    "fk_user_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_mcp_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_model_stats_v2" (
    "fk_workspace_id" character varying(20) NOT NULL,
    "fk_model_id" character varying(20) NOT NULL,
    "row_count" integer DEFAULT 0,
    "is_external" boolean DEFAULT false,
    "base_id" character varying(20) NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_model_stats_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_models_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "table_name" character varying(255),
    "title" character varying(255),
    "type" character varying(255) DEFAULT 'table'::character varying,
    "meta" "text",
    "schema" "text",
    "enabled" boolean DEFAULT true,
    "mm" boolean DEFAULT false,
    "tags" character varying(255),
    "pinned" boolean,
    "deleted" boolean,
    "order" real,
    "description" "text",
    "synced" boolean DEFAULT false,
    "fk_workspace_id" character varying(20),
    "created_by" character varying(20),
    "owned_by" character varying(20),
    "uuid" character varying(255),
    "password" character varying(255),
    "fk_custom_url_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "parent_id" character varying(20),
    "updated_by" character varying(20),
    "has_children" boolean DEFAULT false,
    "doc_version" integer DEFAULT 1,
    "trash_disabled" boolean,
    "trash_retention_days" integer
);


ALTER TABLE "public"."nc_models_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_oauth_authorization_codes" (
    "code" character varying(32) NOT NULL,
    "fk_client_id" character varying(32),
    "fk_user_id" character varying(20),
    "code_challenge" character varying(255),
    "code_challenge_method" character varying(10) DEFAULT 'S256'::character varying,
    "redirect_uri" character varying(255),
    "scope" character varying(255),
    "state" character varying(1024),
    "resource" character varying(255),
    "granted_resources" "text",
    "expires_at" timestamp with time zone NOT NULL,
    "is_used" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_oauth_authorization_codes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_oauth_clients" (
    "client_id" character varying(32) NOT NULL,
    "client_secret" character varying(128),
    "client_type" character varying(255),
    "client_name" character varying(255),
    "client_description" "text",
    "client_uri" character varying(255),
    "logo_uri" character varying(255),
    "redirect_uris" "text",
    "allowed_grant_types" "text",
    "response_types" "text",
    "allowed_scopes" "text",
    "registration_access_token" character varying(255),
    "registration_client_uri" character varying(255),
    "client_id_issued_at" bigint,
    "client_secret_expires_at" bigint,
    "fk_user_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_oauth_clients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_oauth_tokens" (
    "id" character varying(20) NOT NULL,
    "fk_client_id" character varying(32),
    "fk_user_id" character varying(20),
    "access_token" "text",
    "access_token_expires_at" timestamp with time zone,
    "refresh_token" "text",
    "refresh_token_expires_at" timestamp with time zone,
    "resource" character varying(255),
    "audience" character varying(255),
    "granted_resources" "text",
    "scope" character varying(255),
    "is_revoked" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "last_used_at" timestamp with time zone
);


ALTER TABLE "public"."nc_oauth_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_operation_logs" (
    "id" character varying(20) NOT NULL,
    "seq" bigint NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20),
    "fk_user_id" character varying(20),
    "tab_id" character varying(100),
    "forward_op" character varying(80),
    "forward_op_version" smallint,
    "forward_params" "text",
    "inverse_op" character varying(80),
    "inverse_op_version" smallint,
    "inverse_params" "text",
    "entity_type" character varying(40),
    "entity_id" character varying(20),
    "entity_title" character varying(255),
    "description" "text",
    "scope_type" character varying(32),
    "scope_id" character varying(36),
    "status" character varying(20) DEFAULT 'active'::character varying,
    "error" "text",
    "undone_at" timestamp with time zone,
    "meta" "text",
    "cleanup_due_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_operation_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_org" (
    "id" character varying(20) NOT NULL,
    "title" character varying(255),
    "slug" character varying(255),
    "fk_user_id" character varying(20),
    "meta" "text",
    "image" character varying(255),
    "is_share_enabled" boolean DEFAULT false,
    "deleted" boolean DEFAULT false,
    "order" real,
    "fk_db_instance_id" character varying(20),
    "stripe_customer_id" character varying(255),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_org" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_org_domain" (
    "id" character varying(20) NOT NULL,
    "fk_org_id" character varying(20),
    "fk_user_id" character varying(20),
    "domain" character varying(255),
    "verified" boolean,
    "txt_value" character varying(255),
    "last_verified" timestamp with time zone,
    "deleted" boolean DEFAULT false,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_org_domain" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_org_users" (
    "fk_org_id" character varying(20) NOT NULL,
    "fk_user_id" character varying(20) NOT NULL,
    "roles" character varying(255),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "deleted" boolean DEFAULT false,
    "deleted_at" timestamp with time zone,
    "scim_external_id" character varying(255),
    "scim_managed" boolean DEFAULT false,
    "scim_user_name" character varying(255),
    "scim_meta" "text"
);


ALTER TABLE "public"."nc_org_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_permission_subjects" (
    "fk_permission_id" character varying(20) NOT NULL,
    "subject_type" character varying(255) NOT NULL,
    "subject_id" character varying(255) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "hierarchy_scope" character varying(30)
);


ALTER TABLE "public"."nc_permission_subjects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_permissions" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "entity" character varying(255),
    "entity_id" character varying(255),
    "permission" character varying(255),
    "created_by" character varying(20),
    "enforce_for_form" boolean DEFAULT true,
    "enforce_for_automation" boolean DEFAULT true,
    "granted_type" character varying(255),
    "granted_role" character varying(255),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_permissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_plans" (
    "id" character varying(20) NOT NULL,
    "title" character varying(255),
    "description" "text",
    "stripe_product_id" character varying(255) NOT NULL,
    "is_active" boolean DEFAULT true,
    "prices" "text",
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_plans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_plugins_v2" (
    "id" character varying(20) NOT NULL,
    "title" character varying(45),
    "description" "text",
    "active" boolean DEFAULT false,
    "rating" real,
    "version" character varying(255),
    "docs" character varying(255),
    "status" character varying(255) DEFAULT 'install'::character varying,
    "status_details" character varying(255),
    "logo" character varying(255),
    "icon" character varying(255),
    "tags" character varying(255),
    "category" character varying(255),
    "input_schema" "text",
    "input" "text",
    "creator" character varying(255),
    "creator_website" character varying(255),
    "price" character varying(255),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_plugins_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_principal_assignments" (
    "resource_type" character varying(20) NOT NULL,
    "resource_id" character varying(20) NOT NULL,
    "principal_type" character varying(20) NOT NULL,
    "principal_ref_id" character varying(20) NOT NULL,
    "roles" character varying(255) NOT NULL,
    "deleted" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_principal_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_record_templates" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "fk_model_id" character varying(20) NOT NULL,
    "title" character varying(255) NOT NULL,
    "description" "text",
    "template_data" "text" NOT NULL,
    "usage_count" integer DEFAULT 0,
    "enabled" boolean DEFAULT true,
    "created_by" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_record_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_rls_policies" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "fk_model_id" character varying(20) NOT NULL,
    "title" character varying(255),
    "enabled" boolean DEFAULT true,
    "is_default" boolean DEFAULT false,
    "default_behavior" character varying(20),
    "order" real,
    "meta" "text",
    "created_by" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_rls_policies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_rls_policy_subjects" (
    "fk_rls_policy_id" character varying(20) NOT NULL,
    "subject_type" character varying(255) NOT NULL,
    "subject_id" character varying(255) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "hierarchy_scope" character varying(30)
);


ALTER TABLE "public"."nc_rls_policy_subjects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_row_color_conditions" (
    "id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "color" character varying(20),
    "nc_order" real,
    "is_set_as_background" boolean,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "type" character varying(20) DEFAULT 'row'::character varying,
    "fk_target_column_id" character varying(20)
);


ALTER TABLE "public"."nc_row_color_conditions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_ry6x___Features" (
    "id" integer NOT NULL,
    "created_at" timestamp without time zone,
    "updated_at" timestamp without time zone,
    "created_by" character varying,
    "updated_by" character varying,
    "nc_order" numeric,
    "__nc_deleted" boolean,
    "nc_row_meta" "jsonb",
    "title" "text"
);


ALTER TABLE "public"."nc_ry6x___Features" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."nc_ry6x___Features_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."nc_ry6x___Features_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."nc_ry6x___Features_id_seq" OWNED BY "public"."nc_ry6x___Features"."id";



CREATE TABLE IF NOT EXISTS "public"."nc_sandbox_changelog" (
    "id" character varying(20) NOT NULL,
    "seq" bigint NOT NULL,
    "fk_sandbox_id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "event" character varying(80) NOT NULL,
    "entity_type" character varying(40) NOT NULL,
    "entity_id" character varying(20),
    "entity_title" character varying(255),
    "parent_entity_id" character varying(20),
    "parent_entity_title" character varying(255),
    "created_by" character varying(20) NOT NULL,
    "description" "text",
    "meta" "text",
    "status" character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    "merged_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_sandbox_changelog" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_sandboxes_v2" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20) NOT NULL,
    "production_base_id" character varying(20) NOT NULL,
    "sandbox_base_id" character varying(20) NOT NULL,
    "created_by" character varying(20) NOT NULL,
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "merge_state" character varying(20) DEFAULT 'idle'::character varying NOT NULL,
    "merge_error" "text",
    "merge_started_at" timestamp with time zone
);


ALTER TABLE "public"."nc_sandboxes_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_scim_config" (
    "id" character varying(20) NOT NULL,
    "enabled" boolean DEFAULT false,
    "provisioning_token" "text" NOT NULL,
    "role_mapping" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "default_role" character varying(50) DEFAULT 'no-access'::character varying,
    "fk_org_id" character varying(20)
);


ALTER TABLE "public"."nc_scim_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_scripts" (
    "id" character varying(20) NOT NULL,
    "title" "text",
    "description" "text",
    "meta" "text",
    "order" real,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "script" "text",
    "config" "text",
    "created_by" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_scripts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_snapshots" (
    "id" character varying(20) NOT NULL,
    "title" character varying(512),
    "base_id" character varying(20),
    "snapshot_base_id" character varying(20),
    "fk_workspace_id" character varying(20),
    "created_by" character varying(20),
    "status" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_snapshots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_sort_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "fk_column_id" character varying(20),
    "direction" character varying(255) DEFAULT 'false'::character varying,
    "order" real,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "fk_level_id" character varying(20),
    "enabled" boolean
);


ALTER TABLE "public"."nc_sort_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_sources_v2" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "alias" character varying(255),
    "config" "text",
    "meta" "text",
    "is_meta" boolean,
    "type" character varying(255),
    "inflection_column" character varying(255),
    "inflection_table" character varying(255),
    "enabled" boolean DEFAULT true,
    "order" real,
    "description" character varying(255),
    "erd_uuid" character varying(255),
    "deleted" boolean DEFAULT false,
    "is_schema_readonly" boolean DEFAULT false,
    "is_data_readonly" boolean DEFAULT false,
    "is_local" boolean DEFAULT false,
    "fk_sql_executor_id" character varying(20),
    "fk_workspace_id" character varying(20),
    "fk_integration_id" character varying(20),
    "is_encrypted" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_sources_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_sql_executor_v2" (
    "id" character varying(20) NOT NULL,
    "domain" character varying(50),
    "status" character varying(20),
    "priority" integer,
    "capacity" integer,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_sql_executor_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_sso_client" (
    "id" character varying(20) NOT NULL,
    "type" character varying(20),
    "title" character varying(255),
    "enabled" boolean DEFAULT true,
    "config" "text",
    "fk_user_id" character varying(20),
    "fk_org_id" character varying(20),
    "deleted" boolean DEFAULT false,
    "order" real,
    "domain_name" character varying(255),
    "domain_name_verified" boolean,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_sso_client" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_sso_client_domain" (
    "fk_sso_client_id" character varying(20) NOT NULL,
    "fk_org_domain_id" character varying(20),
    "enabled" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_sso_client_domain" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_store" (
    "id" integer NOT NULL,
    "base_id" character varying(255),
    "db_alias" character varying(255) DEFAULT 'db'::character varying,
    "key" character varying(255),
    "value" "text",
    "type" character varying(255),
    "env" character varying(255),
    "tag" character varying(255),
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
);


ALTER TABLE "public"."nc_store" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."nc_store_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."nc_store_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."nc_store_id_seq" OWNED BY "public"."nc_store"."id";



CREATE TABLE IF NOT EXISTS "public"."nc_subscription_addons" (
    "id" character varying(20) NOT NULL,
    "fk_subscription_id" character varying(20) NOT NULL,
    "fk_addon_id" character varying(20) NOT NULL,
    "addon_key" character varying(255) NOT NULL,
    "stripe_subscription_item_id" character varying(255),
    "stripe_price_id" character varying(255),
    "seat_count" integer DEFAULT 1,
    "status" character varying(255) DEFAULT 'active'::character varying,
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_subscription_addons" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_subscriptions" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "fk_org_id" character varying(20),
    "fk_plan_id" character varying(20) NOT NULL,
    "fk_user_id" character varying(20),
    "stripe_subscription_id" character varying(255),
    "stripe_price_id" character varying(255),
    "seat_count" integer DEFAULT 1 NOT NULL,
    "status" character varying(255),
    "billing_cycle_anchor" timestamp with time zone,
    "start_at" timestamp with time zone,
    "trial_end_at" timestamp with time zone,
    "canceled_at" timestamp with time zone,
    "period" character varying(255),
    "upcoming_invoice_at" timestamp with time zone,
    "upcoming_invoice_due_at" timestamp with time zone,
    "upcoming_invoice_amount" integer,
    "upcoming_invoice_currency" character varying(255),
    "stripe_schedule_id" character varying(255),
    "schedule_phase_start" timestamp with time zone,
    "schedule_stripe_price_id" character varying(255),
    "schedule_fk_plan_id" character varying(20),
    "schedule_period" character varying(255),
    "schedule_type" character varying(255),
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "last_paid_seat_count" integer
);


ALTER TABLE "public"."nc_subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_sync_configs" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_integration_id" character varying(20),
    "fk_model_id" character varying(20),
    "sync_type" character varying(255),
    "sync_trigger" character varying(255),
    "sync_trigger_cron" character varying(255),
    "sync_trigger_secret" character varying(255),
    "sync_job_id" character varying(255),
    "last_sync_at" timestamp with time zone,
    "next_sync_at" timestamp with time zone,
    "title" character varying(255),
    "sync_category" character varying(255),
    "fk_parent_sync_config_id" character varying(20),
    "on_delete_action" character varying(255) DEFAULT 'mark_deleted'::character varying,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "created_by" character varying(20),
    "updated_by" character varying(20),
    "meta" "text",
    "deleted" boolean DEFAULT false
);


ALTER TABLE "public"."nc_sync_configs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_sync_logs_v2" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_sync_source_id" character varying(20),
    "time_taken" integer,
    "status" character varying(255),
    "status_details" "text",
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_sync_logs_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_sync_mappings" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_sync_config_id" character varying(20),
    "target_table" character varying(255),
    "fk_model_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_sync_mappings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_sync_source_v2" (
    "id" character varying(20) NOT NULL,
    "title" character varying(255),
    "type" character varying(255),
    "details" "text",
    "deleted" boolean,
    "enabled" boolean DEFAULT true,
    "order" real,
    "base_id" character varying(20) NOT NULL,
    "fk_user_id" character varying(20),
    "source_id" character varying(20),
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_sync_source_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_table_sync_column_mappings" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "fk_table_sync_id" character varying(20),
    "fk_table_sync_mapping_id" character varying(20),
    "source_workspace_id" character varying(20),
    "source_base_id" character varying(20),
    "source_table_id" character varying(20),
    "source_column_id" character varying(20),
    "dest_base_id" character varying(20),
    "dest_table_id" character varying(20),
    "dest_column_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_table_sync_column_mappings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_table_sync_mappings" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "fk_table_sync_id" character varying(20),
    "source_workspace_id" character varying(20),
    "source_base_id" character varying(20),
    "source_table_id" character varying(20),
    "source_view_id" character varying(20),
    "source_uuid" character varying(255),
    "source_password_hash" "text",
    "dest_base_id" character varying(20),
    "dest_table_id" character varying(20),
    "role" character varying(16),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_table_sync_mappings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_table_syncs" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20) NOT NULL,
    "title" character varying(255) NOT NULL,
    "selected_fields" "text",
    "on_delete_action" character varying(32),
    "sync_trigger" character varying(32),
    "status" character varying(16) DEFAULT 'active'::character varying,
    "last_error" "text",
    "last_synced_at" timestamp with time zone,
    "sync_job_id" character varying(255),
    "source_input_mode" character varying(16) DEFAULT 'browse'::character varying NOT NULL,
    "created_by" character varying(20),
    "updated_by" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "deleted" boolean DEFAULT false
);


ALTER TABLE "public"."nc_table_syncs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_teams" (
    "id" character varying(20) NOT NULL,
    "title" character varying(255) NOT NULL,
    "meta" "text",
    "fk_org_id" character varying(20),
    "fk_workspace_id" character varying(20),
    "created_by" character varying(20),
    "deleted" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "scim_external_id" character varying(255),
    "scim_managed" boolean DEFAULT false,
    "scim_display_name" character varying(255),
    "scim_meta" "text",
    "fk_parent_team_id" character varying(20),
    "depth" integer DEFAULT 0,
    "path" "text"
);


ALTER TABLE "public"."nc_teams" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_timeline_view_columns_v2" (
    "id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "fk_view_id" character varying(20),
    "fk_column_id" character varying(20),
    "show" boolean,
    "bold" boolean,
    "underline" boolean,
    "italic" boolean,
    "order" real,
    "group_by" boolean,
    "group_by_order" real,
    "group_by_sort" character varying(4),
    "aggregation" character varying(20),
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_timeline_view_columns_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_timeline_view_range_v2" (
    "id" character varying(20) NOT NULL,
    "fk_view_id" character varying(20),
    "fk_from_column_id" character varying(20),
    "fk_to_column_id" character varying(20),
    "label" character varying(40),
    "base_id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_timeline_view_range_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_timeline_view_v2" (
    "fk_view_id" character varying(20) NOT NULL,
    "base_id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "title" character varying(255),
    "meta" "text",
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_timeline_view_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_trash" (
    "id" character varying(20) NOT NULL,
    "name" character varying(255),
    "parent_name" character varying(255),
    "resource_type" character varying(255),
    "resource_id" character varying(255),
    "parent_type" character varying(255),
    "parent_id" character varying(20),
    "deleted_by" character varying(20),
    "deleted_at" timestamp with time zone,
    "cleanup_due_at" timestamp with time zone,
    "related_items" "text",
    "meta" "text",
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL
);


ALTER TABLE "public"."nc_trash" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_usage_stats" (
    "fk_workspace_id" character varying(20) NOT NULL,
    "usage_type" character varying(255) NOT NULL,
    "period_start" timestamp with time zone NOT NULL,
    "count" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_usage_stats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_user_comment_notifications_preference" (
    "id" character varying(20) NOT NULL,
    "row_id" character varying(255),
    "user_id" character varying(20),
    "fk_model_id" character varying(20),
    "source_id" character varying(20),
    "base_id" character varying(20),
    "preferences" character varying(255),
    "fk_workspace_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_user_comment_notifications_preference" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_user_refresh_tokens" (
    "fk_user_id" character varying(20),
    "token" character varying(255),
    "meta" "text",
    "expires_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_user_refresh_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_users_v2" (
    "id" character varying(20) NOT NULL,
    "email" character varying(255),
    "password" character varying(255),
    "salt" character varying(255),
    "invite_token" character varying(255),
    "invite_token_expires" character varying(255),
    "reset_password_expires" timestamp with time zone,
    "reset_password_token" character varying(255),
    "email_verification_token" character varying(255),
    "email_verified" boolean,
    "roles" character varying(255) DEFAULT 'editor'::character varying,
    "token_version" character varying(255),
    "blocked" boolean DEFAULT false,
    "blocked_reason" character varying(255),
    "deleted_at" timestamp with time zone,
    "is_deleted" boolean DEFAULT false,
    "meta" "text",
    "display_name" character varying(255),
    "user_name" character varying(255),
    "bio" character varying(255),
    "location" character varying(255),
    "website" character varying(255),
    "avatar" character varying(255),
    "is_new_user" boolean,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "canonical_email" character varying(255),
    "stripe_customer_id" character varying(255),
    "totp_secret" "text",
    "totp_enabled" boolean DEFAULT false,
    "totp_backup_codes" "text",
    "last_active_at" timestamp with time zone
);


ALTER TABLE "public"."nc_users_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_view_sections" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20),
    "source_id" character varying(20),
    "fk_model_id" character varying(20) NOT NULL,
    "title" character varying(255) NOT NULL,
    "order" real,
    "meta" "text",
    "created_by" character varying(20),
    "updated_by" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."nc_view_sections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_views_v2" (
    "id" character varying(20) NOT NULL,
    "source_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_model_id" character varying(20),
    "title" character varying(255),
    "type" integer,
    "is_default" boolean,
    "show_system_fields" boolean,
    "lock_type" character varying(255) DEFAULT 'collaborative'::character varying,
    "uuid" character varying(255),
    "password" character varying(255),
    "show" boolean,
    "order" real,
    "meta" "text",
    "description" "text",
    "created_by" character varying(20),
    "owned_by" character varying(20),
    "fk_workspace_id" character varying(20),
    "attachment_mode_column_id" character varying(20),
    "expanded_record_mode" character varying(255),
    "fk_custom_url_id" character varying(20),
    "row_coloring_mode" character varying(10),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "fk_view_section_id" character varying(20),
    "deleted" boolean,
    "allow_sync" boolean DEFAULT false
);


ALTER TABLE "public"."nc_views_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_widgets_v2" (
    "id" character varying(20) NOT NULL,
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20) NOT NULL,
    "fk_dashboard_id" character varying(20) NOT NULL,
    "fk_model_id" character varying(20),
    "fk_view_id" character varying(20),
    "title" character varying(255) NOT NULL,
    "description" "text",
    "type" character varying(50) NOT NULL,
    "config" "text",
    "meta" "text",
    "order" integer,
    "position" "text",
    "error" boolean,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "deleted" boolean
);


ALTER TABLE "public"."nc_widgets_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nc_workflows" (
    "id" character varying(20) NOT NULL,
    "title" character varying(255) NOT NULL,
    "description" "text",
    "fk_workspace_id" character varying(20),
    "base_id" character varying(20),
    "enabled" boolean DEFAULT false,
    "nodes" "text",
    "edges" "text",
    "meta" "text",
    "order" real,
    "created_by" character varying(20),
    "updated_by" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "draft" "text"
);


ALTER TABLE "public"."nc_workflows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification" (
    "id" character varying(20) NOT NULL,
    "type" character varying(40),
    "body" "text",
    "is_read" boolean DEFAULT false,
    "is_deleted" boolean DEFAULT false,
    "fk_user_id" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."notification" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "handle" "text",
    "display_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "avatar_url" "text",
    "first_name" "text",
    "last_name" "text",
    "home_city" "text",
    "home_state" "text"
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."saved_lists" (
    "user_id" "uuid" NOT NULL,
    "list_id" "uuid" NOT NULL,
    "saved_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."saved_lists" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stars" (
    "user_id" "uuid" NOT NULL,
    "entity_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."stars" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."workspace" (
    "id" character varying(20) NOT NULL,
    "title" character varying(255),
    "description" "text",
    "meta" "text",
    "fk_user_id" character varying(20),
    "deleted" boolean DEFAULT false,
    "deleted_at" timestamp with time zone,
    "order" real,
    "status" smallint DEFAULT '0'::smallint,
    "message" character varying(256),
    "plan" character varying(20) DEFAULT 'free'::character varying,
    "infra_meta" "text",
    "fk_org_id" character varying(20),
    "stripe_customer_id" character varying(255),
    "grace_period_start_at" timestamp with time zone,
    "api_grace_period_start_at" timestamp with time zone,
    "automation_grace_period_start_at" timestamp with time zone,
    "loyal" boolean DEFAULT false,
    "loyalty_discount_used" boolean DEFAULT false,
    "db_job_id" character varying(20),
    "fk_db_instance_id" character varying(20),
    "segment_code" integer,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."workspace" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."workspace_user" (
    "fk_workspace_id" character varying(20) NOT NULL,
    "fk_user_id" character varying(20) NOT NULL,
    "roles" character varying(255),
    "invite_token" character varying(255),
    "invite_accepted" boolean DEFAULT false,
    "deleted" boolean DEFAULT false,
    "deleted_at" timestamp with time zone,
    "order" real,
    "invited_by" character varying(20),
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "scim_external_id" character varying(255),
    "scim_managed" boolean DEFAULT false,
    "scim_user_name" character varying(255),
    "scim_meta" "text"
);


ALTER TABLE "public"."workspace_user" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."xc_knex_migrationsv0" (
    "id" integer NOT NULL,
    "name" character varying(255),
    "batch" integer,
    "migration_time" timestamp with time zone
);


ALTER TABLE "public"."xc_knex_migrationsv0" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."xc_knex_migrationsv0_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."xc_knex_migrationsv0_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."xc_knex_migrationsv0_id_seq" OWNED BY "public"."xc_knex_migrationsv0"."id";



CREATE TABLE IF NOT EXISTS "public"."xc_knex_migrationsv0_lock" (
    "index" integer NOT NULL,
    "is_locked" integer
);


ALTER TABLE "public"."xc_knex_migrationsv0_lock" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."xc_knex_migrationsv0_lock_index_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."xc_knex_migrationsv0_lock_index_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."xc_knex_migrationsv0_lock_index_seq" OWNED BY "public"."xc_knex_migrationsv0_lock"."index";



ALTER TABLE ONLY "public"."nc_api_tokens" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."nc_api_tokens_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."nc_ry6x___Features" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."nc_ry6x___Features_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."nc_store" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."nc_store_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."xc_knex_migrationsv0" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."xc_knex_migrationsv0_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."xc_knex_migrationsv0_lock" ALTER COLUMN "index" SET DEFAULT "nextval"('"public"."xc_knex_migrationsv0_lock_index_seq"'::"regclass");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."entities"
    ADD CONSTRAINT "entities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."entity_categories"
    ADD CONSTRAINT "entity_categories_pkey" PRIMARY KEY ("entity_id", "category_id");



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_pkey" PRIMARY KEY ("requester_id", "addressee_id");



ALTER TABLE ONLY "public"."hidden_entities"
    ADD CONSTRAINT "hidden_entities_pkey" PRIMARY KEY ("user_id", "entity_id");



ALTER TABLE ONLY "public"."nc_api_token_scopes"
    ADD CONSTRAINT "idx_api_token_scopes_unique" UNIQUE ("fk_api_token_id", "resource_type", "resource_id");



ALTER TABLE ONLY "public"."nc_api_tokens"
    ADD CONSTRAINT "idx_api_tokens_hash" UNIQUE ("token_hash");



ALTER TABLE ONLY "public"."list_items"
    ADD CONSTRAINT "list_items_pkey" PRIMARY KEY ("list_id", "entity_id");



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "lists_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_addons"
    ADD CONSTRAINT "nc_addons_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_api_token_scopes"
    ADD CONSTRAINT "nc_api_token_scopes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_api_tokens"
    ADD CONSTRAINT "nc_api_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_audit_v2"
    ADD CONSTRAINT "nc_audit_v2_pkx" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_automation_executions"
    ADD CONSTRAINT "nc_automation_executions_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_automation_subscribers"
    ADD CONSTRAINT "nc_automation_subscribers_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_automation_subscribers"
    ADD CONSTRAINT "nc_automation_subscribers_unique_idx" UNIQUE ("base_id", "fk_automation_id", "fk_user_id");



ALTER TABLE ONLY "public"."nc_automations"
    ADD CONSTRAINT "nc_automations_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_base_users_v2"
    ADD CONSTRAINT "nc_base_users_v2_pkey" PRIMARY KEY ("base_id", "fk_user_id");



ALTER TABLE ONLY "public"."nc_base_variables"
    ADD CONSTRAINT "nc_base_variables_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_base_variables"
    ADD CONSTRAINT "nc_base_variables_ws_base_key_unique" UNIQUE ("fk_workspace_id", "base_id", "key");



ALTER TABLE ONLY "public"."nc_sources_v2"
    ADD CONSTRAINT "nc_bases_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_bookmark_groups"
    ADD CONSTRAINT "nc_bookmark_groups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_bookmarks"
    ADD CONSTRAINT "nc_bookmarks_fk_user_id_target_type_target_id_unique" UNIQUE ("fk_user_id", "target_type", "target_id");



ALTER TABLE ONLY "public"."nc_bookmarks"
    ADD CONSTRAINT "nc_bookmarks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_calendar_view_columns_v2"
    ADD CONSTRAINT "nc_calendar_view_columns_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_calendar_view_range_v2"
    ADD CONSTRAINT "nc_calendar_view_range_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_calendar_view_v2"
    ADD CONSTRAINT "nc_calendar_view_v2_pkey" PRIMARY KEY ("base_id", "fk_view_id");



ALTER TABLE ONLY "public"."nc_chat_messages"
    ADD CONSTRAINT "nc_chat_messages_pkey" PRIMARY KEY ("fk_workspace_id", "id");



ALTER TABLE ONLY "public"."nc_chat_sessions"
    ADD CONSTRAINT "nc_chat_sessions_pkey" PRIMARY KEY ("fk_workspace_id", "id");



ALTER TABLE ONLY "public"."nc_col_barcode_v2"
    ADD CONSTRAINT "nc_col_barcode_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_col_button_v2"
    ADD CONSTRAINT "nc_col_button_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_col_formula_v2"
    ADD CONSTRAINT "nc_col_formula_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_col_long_text_v2"
    ADD CONSTRAINT "nc_col_long_text_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_col_lookup_v2"
    ADD CONSTRAINT "nc_col_lookup_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_col_qrcode_v2"
    ADD CONSTRAINT "nc_col_qrcode_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_col_relations_v2"
    ADD CONSTRAINT "nc_col_relations_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_col_rollup_v2"
    ADD CONSTRAINT "nc_col_rollup_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_col_select_options_v2"
    ADD CONSTRAINT "nc_col_select_options_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_columns_v2"
    ADD CONSTRAINT "nc_columns_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_comment_reactions"
    ADD CONSTRAINT "nc_comment_reactions_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_comments"
    ADD CONSTRAINT "nc_comments_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_custom_urls_v2"
    ADD CONSTRAINT "nc_custom_urls_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_dashboards_v2"
    ADD CONSTRAINT "nc_dashboards_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_data_reflection"
    ADD CONSTRAINT "nc_data_reflection_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_date_dependency_v2"
    ADD CONSTRAINT "nc_date_dep_gantt_view_id_unique" UNIQUE ("fk_gantt_view_id");



ALTER TABLE ONLY "public"."nc_date_dependency_v2"
    ADD CONSTRAINT "nc_date_dependency_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_db_servers"
    ADD CONSTRAINT "nc_db_servers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_dependency_tracker"
    ADD CONSTRAINT "nc_dependency_tracker_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_disabled_models_for_role_v2"
    ADD CONSTRAINT "nc_disabled_models_for_role_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_doc_content_v2"
    ADD CONSTRAINT "nc_doc_content_v2_pkey" PRIMARY KEY ("base_id", "fk_doc_id");



ALTER TABLE ONLY "public"."nc_doc_revisions_v2"
    ADD CONSTRAINT "nc_doc_revisions_v2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_docs_v2"
    ADD CONSTRAINT "nc_docs_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_extensions"
    ADD CONSTRAINT "nc_extensions_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_file_references"
    ADD CONSTRAINT "nc_file_references_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_filter_exp_v2"
    ADD CONSTRAINT "nc_filter_exp_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_follower"
    ADD CONSTRAINT "nc_follower_pkey" PRIMARY KEY ("fk_user_id", "fk_follower_id");



ALTER TABLE ONLY "public"."nc_form_view_columns_v2"
    ADD CONSTRAINT "nc_form_view_columns_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_form_view_v2"
    ADD CONSTRAINT "nc_form_view_v2_pkey" PRIMARY KEY ("base_id", "fk_view_id");



ALTER TABLE ONLY "public"."nc_gallery_view_columns_v2"
    ADD CONSTRAINT "nc_gallery_view_columns_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_gallery_view_v2"
    ADD CONSTRAINT "nc_gallery_view_v2_pkey" PRIMARY KEY ("base_id", "fk_view_id");



ALTER TABLE ONLY "public"."nc_gantt_view_columns_v2"
    ADD CONSTRAINT "nc_gantt_view_columns_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_gantt_view_v2"
    ADD CONSTRAINT "nc_gantt_view_v2_pkey" PRIMARY KEY ("base_id", "fk_view_id");



ALTER TABLE ONLY "public"."nc_gcp_marketplace_accounts"
    ADD CONSTRAINT "nc_gcp_marketplace_accounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_gcp_marketplace_accounts"
    ADD CONSTRAINT "nc_gcp_marketplace_accounts_procurement_account_id_unique" UNIQUE ("procurement_account_id");



ALTER TABLE ONLY "public"."nc_gcp_marketplace_entitlements"
    ADD CONSTRAINT "nc_gcp_marketplace_entitlements_entitlement_id_unique" UNIQUE ("entitlement_id");



ALTER TABLE ONLY "public"."nc_gcp_marketplace_entitlements"
    ADD CONSTRAINT "nc_gcp_marketplace_entitlements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_grid_view_columns_v2"
    ADD CONSTRAINT "nc_grid_view_columns_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_grid_view_v2"
    ADD CONSTRAINT "nc_grid_view_v2_pkey" PRIMARY KEY ("base_id", "fk_view_id");



ALTER TABLE ONLY "public"."nc_hook_logs_v2"
    ADD CONSTRAINT "nc_hook_logs_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_hook_trigger_fields"
    ADD CONSTRAINT "nc_hook_trigger_fields_pkey" PRIMARY KEY ("fk_workspace_id", "base_id", "fk_hook_id", "fk_column_id");



ALTER TABLE ONLY "public"."nc_hooks_v2"
    ADD CONSTRAINT "nc_hooks_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_installations"
    ADD CONSTRAINT "nc_installations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_integration_links_v2"
    ADD CONSTRAINT "nc_integration_links_v2_fk_integration_id_base_id_unique" UNIQUE ("fk_integration_id", "base_id");



ALTER TABLE ONLY "public"."nc_integration_links_v2"
    ADD CONSTRAINT "nc_integration_links_v2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_integrations_store_v2"
    ADD CONSTRAINT "nc_integrations_store_v2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_integrations_v2"
    ADD CONSTRAINT "nc_integrations_v2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_jobs"
    ADD CONSTRAINT "nc_jobs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_kanban_view_columns_v2"
    ADD CONSTRAINT "nc_kanban_view_columns_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_kanban_view_v2"
    ADD CONSTRAINT "nc_kanban_view_v2_pkey" PRIMARY KEY ("base_id", "fk_view_id");



ALTER TABLE ONLY "public"."nc_mail_sends"
    ADD CONSTRAINT "nc_mail_sends_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_managed_app_versions"
    ADD CONSTRAINT "nc_managed_app_versions_number_unique_idx" UNIQUE ("fk_managed_app_id", "version_number");



ALTER TABLE ONLY "public"."nc_managed_app_versions"
    ADD CONSTRAINT "nc_managed_app_versions_unique_idx" UNIQUE ("fk_managed_app_id", "version");



ALTER TABLE ONLY "public"."nc_map_view_columns_v2"
    ADD CONSTRAINT "nc_map_view_columns_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_map_view_v2"
    ADD CONSTRAINT "nc_map_view_v2_pkey" PRIMARY KEY ("base_id", "fk_view_id");



ALTER TABLE ONLY "public"."nc_mcp_tokens"
    ADD CONSTRAINT "nc_mcp_tokens_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_model_stats_v2"
    ADD CONSTRAINT "nc_model_stats_v2_pkey" PRIMARY KEY ("fk_workspace_id", "base_id", "fk_model_id");



ALTER TABLE ONLY "public"."nc_models_v2"
    ADD CONSTRAINT "nc_models_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_oauth_authorization_codes"
    ADD CONSTRAINT "nc_oauth_authorization_codes_pkey" PRIMARY KEY ("code");



ALTER TABLE ONLY "public"."nc_oauth_clients"
    ADD CONSTRAINT "nc_oauth_clients_pkey" PRIMARY KEY ("client_id");



ALTER TABLE ONLY "public"."nc_oauth_tokens"
    ADD CONSTRAINT "nc_oauth_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_operation_logs"
    ADD CONSTRAINT "nc_operation_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_org_domain"
    ADD CONSTRAINT "nc_org_domain_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_org"
    ADD CONSTRAINT "nc_org_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_org_users"
    ADD CONSTRAINT "nc_org_users_pkey" PRIMARY KEY ("fk_org_id", "fk_user_id");



ALTER TABLE ONLY "public"."nc_list_view_columns_v2"
    ADD CONSTRAINT "nc_outline_view_columns_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_list_view_levels_v2"
    ADD CONSTRAINT "nc_outline_view_levels_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_list_view_v2"
    ADD CONSTRAINT "nc_outline_view_v2_pkey" PRIMARY KEY ("base_id", "fk_view_id");



ALTER TABLE ONLY "public"."nc_permission_subjects"
    ADD CONSTRAINT "nc_permission_subjects_pkey" PRIMARY KEY ("base_id", "fk_permission_id", "subject_type", "subject_id");



ALTER TABLE ONLY "public"."nc_permissions"
    ADD CONSTRAINT "nc_permissions_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_plans"
    ADD CONSTRAINT "nc_plans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_plugins_v2"
    ADD CONSTRAINT "nc_plugins_v2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_principal_assignments"
    ADD CONSTRAINT "nc_principal_assignments_pk" PRIMARY KEY ("resource_type", "resource_id", "principal_type", "principal_ref_id");



ALTER TABLE ONLY "public"."nc_bases_v2"
    ADD CONSTRAINT "nc_projects_v2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_record_templates"
    ADD CONSTRAINT "nc_record_templates_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_rls_policies"
    ADD CONSTRAINT "nc_rls_policies_pk" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_rls_policy_subjects"
    ADD CONSTRAINT "nc_rls_policy_subjects_pk" PRIMARY KEY ("fk_rls_policy_id", "subject_type", "subject_id");



ALTER TABLE ONLY "public"."nc_row_color_conditions"
    ADD CONSTRAINT "nc_row_color_conditions_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_ry6x___Features"
    ADD CONSTRAINT "nc_ry6x___Features_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_sandbox_changelog"
    ADD CONSTRAINT "nc_sandbox_changelog_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_managed_app_deployment_logs"
    ADD CONSTRAINT "nc_sandbox_deployment_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_managed_app_versions"
    ADD CONSTRAINT "nc_sandbox_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_managed_apps"
    ADD CONSTRAINT "nc_sandboxes_base_id_unique" UNIQUE ("base_id");



ALTER TABLE ONLY "public"."nc_managed_apps"
    ADD CONSTRAINT "nc_sandboxes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_sandboxes_v2"
    ADD CONSTRAINT "nc_sandboxes_production_base_unique" UNIQUE ("production_base_id");



ALTER TABLE ONLY "public"."nc_sandboxes_v2"
    ADD CONSTRAINT "nc_sandboxes_v2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_scim_config"
    ADD CONSTRAINT "nc_scim_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_sandbox_changelog"
    ADD CONSTRAINT "nc_scl_sandbox_seq_unique" UNIQUE ("fk_sandbox_id", "seq");



ALTER TABLE ONLY "public"."nc_scripts"
    ADD CONSTRAINT "nc_scripts_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_snapshots"
    ADD CONSTRAINT "nc_snapshots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_sort_v2"
    ADD CONSTRAINT "nc_sort_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_sql_executor_v2"
    ADD CONSTRAINT "nc_sql_executor_v2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_sso_client_domain"
    ADD CONSTRAINT "nc_sso_client_domain_pkey" PRIMARY KEY ("fk_sso_client_id");



ALTER TABLE ONLY "public"."nc_sso_client"
    ADD CONSTRAINT "nc_sso_client_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_store"
    ADD CONSTRAINT "nc_store_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_subscription_addons"
    ADD CONSTRAINT "nc_subscription_addons_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_subscriptions"
    ADD CONSTRAINT "nc_subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_sync_configs"
    ADD CONSTRAINT "nc_sync_configs_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_sync_logs_v2"
    ADD CONSTRAINT "nc_sync_logs_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_sync_mappings"
    ADD CONSTRAINT "nc_sync_mappings_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_sync_source_v2"
    ADD CONSTRAINT "nc_sync_source_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_table_sync_column_mappings"
    ADD CONSTRAINT "nc_table_sync_column_mappings_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_table_sync_mappings"
    ADD CONSTRAINT "nc_table_sync_mappings_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_table_syncs"
    ADD CONSTRAINT "nc_table_syncs_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_teams"
    ADD CONSTRAINT "nc_teams_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_teams"
    ADD CONSTRAINT "nc_teams_scim_external_id_unique" UNIQUE ("scim_external_id");



ALTER TABLE ONLY "public"."nc_timeline_view_columns_v2"
    ADD CONSTRAINT "nc_timeline_view_columns_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_timeline_view_range_v2"
    ADD CONSTRAINT "nc_timeline_view_range_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_timeline_view_v2"
    ADD CONSTRAINT "nc_timeline_view_v2_pkey" PRIMARY KEY ("base_id", "fk_view_id");



ALTER TABLE ONLY "public"."nc_trash"
    ADD CONSTRAINT "nc_trash_base_id_resource_type_resource_id_unique" UNIQUE ("base_id", "resource_type", "resource_id");



ALTER TABLE ONLY "public"."nc_trash"
    ADD CONSTRAINT "nc_trash_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_usage_stats"
    ADD CONSTRAINT "nc_usage_stats_pkey" PRIMARY KEY ("fk_workspace_id", "usage_type", "period_start");



ALTER TABLE ONLY "public"."nc_user_comment_notifications_preference"
    ADD CONSTRAINT "nc_user_comment_notifications_preference_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_users_v2"
    ADD CONSTRAINT "nc_users_v2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_view_sections"
    ADD CONSTRAINT "nc_view_sections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nc_views_v2"
    ADD CONSTRAINT "nc_views_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_widgets_v2"
    ADD CONSTRAINT "nc_widgets_v2_pkey" PRIMARY KEY ("base_id", "id");



ALTER TABLE ONLY "public"."nc_workflows"
    ADD CONSTRAINT "nc_workflows_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification"
    ADD CONSTRAINT "notification_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_handle_key" UNIQUE ("handle");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."saved_lists"
    ADD CONSTRAINT "saved_lists_pkey" PRIMARY KEY ("user_id", "list_id");



ALTER TABLE ONLY "public"."stars"
    ADD CONSTRAINT "stars_pkey" PRIMARY KEY ("user_id", "entity_id");



ALTER TABLE ONLY "public"."workspace"
    ADD CONSTRAINT "workspace_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."workspace_user"
    ADD CONSTRAINT "workspace_user_pkey" PRIMARY KEY ("fk_workspace_id", "fk_user_id");



ALTER TABLE ONLY "public"."xc_knex_migrationsv0_lock"
    ADD CONSTRAINT "xc_knex_migrationsv0_lock_pkey" PRIMARY KEY ("index");



ALTER TABLE ONLY "public"."xc_knex_migrationsv0"
    ADD CONSTRAINT "xc_knex_migrationsv0_pkey" PRIMARY KEY ("id");



CREATE INDEX "categories_path_idx" ON "public"."categories" USING "gist" ("path");



CREATE INDEX "entities_location_idx" ON "public"."entities" USING "gist" ("location");



CREATE UNIQUE INDEX "entities_osm_id_unique" ON "public"."entities" USING "btree" ("osm_id") WHERE ("osm_id" IS NOT NULL);



CREATE INDEX "idx_api_token_scopes_resource" ON "public"."nc_api_token_scopes" USING "btree" ("resource_type", "resource_id");



CREATE INDEX "idx_api_token_scopes_token" ON "public"."nc_api_token_scopes" USING "btree" ("fk_api_token_id");



CREATE INDEX "idx_nc_form_view_columns_row_id" ON "public"."nc_form_view_columns_v2" USING "btree" ("row_id");



CREATE UNIQUE INDEX "lists_one_default_per_owner" ON "public"."lists" USING "btree" ("owner_id") WHERE "is_default_list";



CREATE INDEX "nc_addons_addon_key_idx" ON "public"."nc_addons" USING "btree" ("addon_key");



CREATE INDEX "nc_addons_stripe_product_idx" ON "public"."nc_addons" USING "btree" ("stripe_product_id");



CREATE INDEX "nc_api_tokens_fk_sso_client_id_index" ON "public"."nc_api_tokens" USING "btree" ("fk_sso_client_id");



CREATE INDEX "nc_api_tokens_fk_user_id_index" ON "public"."nc_api_tokens" USING "btree" ("fk_user_id");



CREATE INDEX "nc_audit_v2_fk_org_id_idx" ON "public"."nc_audit_v2" USING "btree" ("fk_org_id");



CREATE INDEX "nc_audit_v2_fk_workspace_idx" ON "public"."nc_audit_v2" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_audit_v2_old_id_index" ON "public"."nc_audit_v2" USING "btree" ("old_id");



CREATE INDEX "nc_audit_v2_tenant_idx" ON "public"."nc_audit_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_automation_executions_error_notify_idx" ON "public"."nc_automation_executions" USING "btree" ("status", "error_notified_at");



CREATE INDEX "nc_automation_executions_oldpk_idx" ON "public"."nc_automation_executions" USING "btree" ("id");



CREATE INDEX "nc_automation_executions_resume_idx" ON "public"."nc_automation_executions" USING "btree" ("fk_workspace_id", "base_id", "resume_at");



CREATE INDEX "nc_automation_subscribers_automation_idx" ON "public"."nc_automation_subscribers" USING "btree" ("fk_automation_id");



CREATE INDEX "nc_automation_subscribers_user_idx" ON "public"."nc_automation_subscribers" USING "btree" ("fk_user_id");



CREATE INDEX "nc_automations_context_idx" ON "public"."nc_automations" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_automations_enabled_idx" ON "public"."nc_automations" USING "btree" ("enabled");



CREATE INDEX "nc_automations_oldpk_idx" ON "public"."nc_automations" USING "btree" ("id");



CREATE INDEX "nc_automations_order_idx" ON "public"."nc_automations" USING "btree" ("base_id", "order");



CREATE INDEX "nc_automations_type_idx" ON "public"."nc_automations" USING "btree" ("type");



CREATE INDEX "nc_base_users_v2_base_id_fk_workspace_id_index" ON "public"."nc_base_users_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_base_users_v2_invited_by_index" ON "public"."nc_base_users_v2" USING "btree" ("invited_by");



CREATE INDEX "nc_base_variables_base_ws_index" ON "public"."nc_base_variables" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_bases_is_sandbox_idx" ON "public"."nc_bases_v2" USING "btree" ("is_sandbox");



CREATE INDEX "nc_bases_is_sandbox_production_idx" ON "public"."nc_bases_v2" USING "btree" ("is_sandbox_production");



CREATE INDEX "nc_bases_managed_app_auto_update_idx" ON "public"."nc_bases_v2" USING "btree" ("managed_app_id", "auto_update");



CREATE INDEX "nc_bases_managed_app_id_idx" ON "public"."nc_bases_v2" USING "btree" ("managed_app_id");



CREATE INDEX "nc_bases_managed_app_master_idx" ON "public"."nc_bases_v2" USING "btree" ("managed_app_master");



CREATE INDEX "nc_bases_managed_app_version_id_idx" ON "public"."nc_bases_v2" USING "btree" ("managed_app_version_id");



CREATE INDEX "nc_bases_v2_fk_custom_url_id_index" ON "public"."nc_bases_v2" USING "btree" ("fk_custom_url_id");



CREATE INDEX "nc_bases_v2_fk_workspace_id_index" ON "public"."nc_bases_v2" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_bookmark_groups_fk_user_id_index" ON "public"."nc_bookmark_groups" USING "btree" ("fk_user_id");



CREATE INDEX "nc_bookmarks_fk_group_id_index" ON "public"."nc_bookmarks" USING "btree" ("fk_group_id");



CREATE INDEX "nc_bookmarks_fk_user_id_index" ON "public"."nc_bookmarks" USING "btree" ("fk_user_id");



CREATE INDEX "nc_calendar_view_columns_v2_base_id_fk_workspace_id_index" ON "public"."nc_calendar_view_columns_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_calendar_view_columns_v2_fk_view_id_fk_column_id_index" ON "public"."nc_calendar_view_columns_v2" USING "btree" ("fk_view_id", "fk_column_id");



CREATE INDEX "nc_calendar_view_columns_v2_oldpk_idx" ON "public"."nc_calendar_view_columns_v2" USING "btree" ("id");



CREATE INDEX "nc_calendar_view_range_v2_base_id_fk_workspace_id_index" ON "public"."nc_calendar_view_range_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_calendar_view_range_v2_oldpk_idx" ON "public"."nc_calendar_view_range_v2" USING "btree" ("id");



CREATE INDEX "nc_calendar_view_v2_base_id_fk_workspace_id_index" ON "public"."nc_calendar_view_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_calendar_view_v2_oldpk_idx" ON "public"."nc_calendar_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_chat_messages_session_idx" ON "public"."nc_chat_messages" USING "btree" ("fk_session_id");



CREATE INDEX "nc_chat_sessions_user_idx" ON "public"."nc_chat_sessions" USING "btree" ("fk_user_id");



CREATE INDEX "nc_col_barcode_v2_base_id_fk_workspace_id_index" ON "public"."nc_col_barcode_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_col_barcode_v2_fk_column_id_index" ON "public"."nc_col_barcode_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_col_barcode_v2_oldpk_idx" ON "public"."nc_col_barcode_v2" USING "btree" ("id");



CREATE INDEX "nc_col_button_context" ON "public"."nc_col_button_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_col_button_v2_fk_column_id_index" ON "public"."nc_col_button_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_col_button_v2_oldpk_idx" ON "public"."nc_col_button_v2" USING "btree" ("id");



CREATE INDEX "nc_col_formula_v2_base_id_fk_workspace_id_index" ON "public"."nc_col_formula_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_col_formula_v2_fk_column_id_index" ON "public"."nc_col_formula_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_col_formula_v2_oldpk_idx" ON "public"."nc_col_formula_v2" USING "btree" ("id");



CREATE INDEX "nc_col_long_text_context" ON "public"."nc_col_long_text_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_col_long_text_v2_fk_column_id_index" ON "public"."nc_col_long_text_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_col_long_text_v2_oldpk_idx" ON "public"."nc_col_long_text_v2" USING "btree" ("id");



CREATE INDEX "nc_col_lookup_v2_base_id_fk_workspace_id_index" ON "public"."nc_col_lookup_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_col_lookup_v2_fk_column_id_index" ON "public"."nc_col_lookup_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_col_lookup_v2_fk_lookup_column_id_index" ON "public"."nc_col_lookup_v2" USING "btree" ("fk_lookup_column_id");



CREATE INDEX "nc_col_lookup_v2_fk_relation_column_id_index" ON "public"."nc_col_lookup_v2" USING "btree" ("fk_relation_column_id");



CREATE INDEX "nc_col_lookup_v2_oldpk_idx" ON "public"."nc_col_lookup_v2" USING "btree" ("id");



CREATE INDEX "nc_col_qrcode_v2_base_id_fk_workspace_id_index" ON "public"."nc_col_qrcode_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_col_qrcode_v2_fk_column_id_index" ON "public"."nc_col_qrcode_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_col_qrcode_v2_oldpk_idx" ON "public"."nc_col_qrcode_v2" USING "btree" ("id");



CREATE INDEX "nc_col_relations_v2_base_id_fk_workspace_id_index" ON "public"."nc_col_relations_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_col_relations_v2_fk_child_column_id_index" ON "public"."nc_col_relations_v2" USING "btree" ("fk_child_column_id");



CREATE INDEX "nc_col_relations_v2_fk_column_id_index" ON "public"."nc_col_relations_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_col_relations_v2_fk_display_value_column_id_index" ON "public"."nc_col_relations_v2" USING "btree" ("fk_display_value_column_id");



CREATE INDEX "nc_col_relations_v2_fk_mm_child_column_id_index" ON "public"."nc_col_relations_v2" USING "btree" ("fk_mm_child_column_id");



CREATE INDEX "nc_col_relations_v2_fk_mm_model_id_index" ON "public"."nc_col_relations_v2" USING "btree" ("fk_mm_model_id");



CREATE INDEX "nc_col_relations_v2_fk_mm_parent_column_id_index" ON "public"."nc_col_relations_v2" USING "btree" ("fk_mm_parent_column_id");



CREATE INDEX "nc_col_relations_v2_fk_parent_column_id_index" ON "public"."nc_col_relations_v2" USING "btree" ("fk_parent_column_id");



CREATE INDEX "nc_col_relations_v2_fk_related_model_id_index" ON "public"."nc_col_relations_v2" USING "btree" ("fk_related_model_id");



CREATE INDEX "nc_col_relations_v2_fk_target_view_id_index" ON "public"."nc_col_relations_v2" USING "btree" ("fk_target_view_id");



CREATE INDEX "nc_col_relations_v2_oldpk_idx" ON "public"."nc_col_relations_v2" USING "btree" ("id");



CREATE INDEX "nc_col_rollup_v2_base_id_fk_workspace_id_index" ON "public"."nc_col_rollup_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_col_rollup_v2_fk_column_id_index" ON "public"."nc_col_rollup_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_col_rollup_v2_fk_relation_column_id_index" ON "public"."nc_col_rollup_v2" USING "btree" ("fk_relation_column_id");



CREATE INDEX "nc_col_rollup_v2_fk_rollup_column_id_index" ON "public"."nc_col_rollup_v2" USING "btree" ("fk_rollup_column_id");



CREATE INDEX "nc_col_rollup_v2_oldpk_idx" ON "public"."nc_col_rollup_v2" USING "btree" ("id");



CREATE INDEX "nc_col_select_options_v2_base_id_fk_workspace_id_index" ON "public"."nc_col_select_options_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_col_select_options_v2_fk_column_id_index" ON "public"."nc_col_select_options_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_col_select_options_v2_oldpk_idx" ON "public"."nc_col_select_options_v2" USING "btree" ("id");



CREATE INDEX "nc_columns_v2_base_id_fk_workspace_id_index" ON "public"."nc_columns_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_columns_v2_fk_model_id_index" ON "public"."nc_columns_v2" USING "btree" ("fk_model_id");



CREATE INDEX "nc_columns_v2_oldpk_idx" ON "public"."nc_columns_v2" USING "btree" ("id");



CREATE INDEX "nc_comment_reactions_base_id_fk_workspace_id_index" ON "public"."nc_comment_reactions" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_comment_reactions_comment_id_index" ON "public"."nc_comment_reactions" USING "btree" ("comment_id");



CREATE INDEX "nc_comment_reactions_oldpk_idx" ON "public"."nc_comment_reactions" USING "btree" ("id");



CREATE INDEX "nc_comment_reactions_row_id_index" ON "public"."nc_comment_reactions" USING "btree" ("row_id");



CREATE INDEX "nc_comments_base_id_fk_workspace_id_index" ON "public"."nc_comments" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_comments_doc_idx" ON "public"."nc_comments" USING "btree" ("fk_doc_id");



CREATE INDEX "nc_comments_oldpk_idx" ON "public"."nc_comments" USING "btree" ("id");



CREATE INDEX "nc_comments_row_id_fk_model_id_index" ON "public"."nc_comments" USING "btree" ("row_id", "fk_model_id");



CREATE INDEX "nc_custom_urls_context" ON "public"."nc_custom_urls_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_custom_urls_v2_custom_path_index" ON "public"."nc_custom_urls_v2" USING "btree" ("custom_path");



CREATE INDEX "nc_custom_urls_v2_fk_dashboard_id_index" ON "public"."nc_custom_urls_v2" USING "btree" ("fk_dashboard_id");



CREATE INDEX "nc_custom_urls_v2_oldpk_idx" ON "public"."nc_custom_urls_v2" USING "btree" ("id");



CREATE INDEX "nc_dashboards_context" ON "public"."nc_dashboards_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_dashboards_v2_oldpk_idx" ON "public"."nc_dashboards_v2" USING "btree" ("id");



CREATE INDEX "nc_data_reflection_fk_workspace_id_index" ON "public"."nc_data_reflection" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_date_dep_context_idx" ON "public"."nc_date_dependency_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_date_dep_model_idx" ON "public"."nc_date_dependency_v2" USING "btree" ("fk_model_id");



CREATE INDEX "nc_date_dep_model_view_idx" ON "public"."nc_date_dependency_v2" USING "btree" ("fk_model_id", "fk_gantt_view_id");



CREATE INDEX "nc_dependency_tracker_context_idx" ON "public"."nc_dependency_tracker" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_dependency_tracker_dependent_idx" ON "public"."nc_dependency_tracker" USING "btree" ("dependent_type", "dependent_id");



CREATE INDEX "nc_dependency_tracker_oldpk_idx" ON "public"."nc_dependency_tracker" USING "btree" ("id");



CREATE INDEX "nc_dependency_tracker_queryable_field_0_idx" ON "public"."nc_dependency_tracker" USING "btree" ("queryable_field_0");



CREATE INDEX "nc_dependency_tracker_queryable_field_1_idx" ON "public"."nc_dependency_tracker" USING "btree" ("queryable_field_1");



CREATE INDEX "nc_dependency_tracker_queryable_field_2_idx" ON "public"."nc_dependency_tracker" USING "btree" ("queryable_field_2");



CREATE INDEX "nc_dependency_tracker_source_idx" ON "public"."nc_dependency_tracker" USING "btree" ("source_type", "source_id");



CREATE INDEX "nc_disabled_models_for_role_v2_base_id_fk_workspace_id_index" ON "public"."nc_disabled_models_for_role_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_disabled_models_for_role_v2_fk_view_id_index" ON "public"."nc_disabled_models_for_role_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_disabled_models_for_role_v2_oldpk_idx" ON "public"."nc_disabled_models_for_role_v2" USING "btree" ("id");



CREATE INDEX "nc_doc_content_v2_tenant_idx" ON "public"."nc_doc_content_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_doc_revisions_v2_doc_created_idx" ON "public"."nc_doc_revisions_v2" USING "btree" ("fk_doc_id", "created_at");



CREATE INDEX "nc_doc_revisions_v2_tenant_idx" ON "public"."nc_doc_revisions_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_docs_v2_tenant_idx" ON "public"."nc_docs_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_docs_v2_tree_idx" ON "public"."nc_docs_v2" USING "btree" ("base_id", "parent_id", "order");



CREATE INDEX "nc_extensions_base_id_fk_workspace_id_index" ON "public"."nc_extensions" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_extensions_oldpk_idx" ON "public"."nc_extensions" USING "btree" ("id");



CREATE INDEX "nc_filter_exp_rls_policy_idx" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_rls_policy_id");



CREATE INDEX "nc_filter_exp_v2_base_id_fk_workspace_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_filter_exp_v2_fk_button_col_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_button_col_id");



CREATE INDEX "nc_filter_exp_v2_fk_column_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_filter_exp_v2_fk_hook_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_hook_id");



CREATE INDEX "nc_filter_exp_v2_fk_level_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_level_id");



CREATE INDEX "nc_filter_exp_v2_fk_link_col_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_link_col_id");



CREATE INDEX "nc_filter_exp_v2_fk_parent_column_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_parent_column_id");



CREATE INDEX "nc_filter_exp_v2_fk_parent_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_parent_id");



CREATE INDEX "nc_filter_exp_v2_fk_value_col_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_value_col_id");



CREATE INDEX "nc_filter_exp_v2_fk_view_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_filter_exp_v2_fk_widget_id_index" ON "public"."nc_filter_exp_v2" USING "btree" ("fk_widget_id");



CREATE INDEX "nc_filter_exp_v2_oldpk_idx" ON "public"."nc_filter_exp_v2" USING "btree" ("id");



CREATE INDEX "nc_follower_fk_follower_id_index" ON "public"."nc_follower" USING "btree" ("fk_follower_id");



CREATE INDEX "nc_follower_fk_user_id_index" ON "public"."nc_follower" USING "btree" ("fk_user_id");



CREATE INDEX "nc_form_view_columns_v2_base_id_fk_workspace_id_index" ON "public"."nc_form_view_columns_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_form_view_columns_v2_fk_column_id_index" ON "public"."nc_form_view_columns_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_form_view_columns_v2_fk_view_id_fk_column_id_index" ON "public"."nc_form_view_columns_v2" USING "btree" ("fk_view_id", "fk_column_id");



CREATE INDEX "nc_form_view_columns_v2_fk_view_id_index" ON "public"."nc_form_view_columns_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_form_view_columns_v2_oldpk_idx" ON "public"."nc_form_view_columns_v2" USING "btree" ("id");



CREATE INDEX "nc_form_view_v2_base_id_fk_workspace_id_index" ON "public"."nc_form_view_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_form_view_v2_fk_view_id_index" ON "public"."nc_form_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_form_view_v2_oldpk_idx" ON "public"."nc_form_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_fr_context" ON "public"."nc_file_references" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_fr_doc_idx" ON "public"."nc_file_references" USING "btree" ("base_id", "fk_doc_id");



CREATE INDEX "nc_fr_revision_idx" ON "public"."nc_file_references" USING "btree" ("base_id", "fk_revision_id") WHERE ("fk_revision_id" IS NOT NULL);



CREATE INDEX "nc_fr_row_idx" ON "public"."nc_file_references" USING "btree" ("base_id", "fk_column_id", "fk_row_id");



CREATE INDEX "nc_fr_session_idx" ON "public"."nc_file_references" USING "btree" ("base_id", "fk_session_id");



CREATE INDEX "nc_gallery_view_columns_v2_base_id_fk_workspace_id_index" ON "public"."nc_gallery_view_columns_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_gallery_view_columns_v2_fk_column_id_index" ON "public"."nc_gallery_view_columns_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_gallery_view_columns_v2_fk_view_id_fk_column_id_index" ON "public"."nc_gallery_view_columns_v2" USING "btree" ("fk_view_id", "fk_column_id");



CREATE INDEX "nc_gallery_view_columns_v2_fk_view_id_index" ON "public"."nc_gallery_view_columns_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_gallery_view_columns_v2_oldpk_idx" ON "public"."nc_gallery_view_columns_v2" USING "btree" ("id");



CREATE INDEX "nc_gallery_view_v2_base_id_fk_workspace_id_index" ON "public"."nc_gallery_view_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_gallery_view_v2_fk_view_id_index" ON "public"."nc_gallery_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_gallery_view_v2_oldpk_idx" ON "public"."nc_gallery_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_gantt_view_columns_v2_base_id_fk_workspace_id_index" ON "public"."nc_gantt_view_columns_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_gantt_view_columns_v2_fk_view_id_fk_column_id_index" ON "public"."nc_gantt_view_columns_v2" USING "btree" ("fk_view_id", "fk_column_id");



CREATE INDEX "nc_gantt_view_columns_v2_oldpk_idx" ON "public"."nc_gantt_view_columns_v2" USING "btree" ("id");



CREATE INDEX "nc_gantt_view_v2_base_id_fk_workspace_id_index" ON "public"."nc_gantt_view_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_gantt_view_v2_oldpk_idx" ON "public"."nc_gantt_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_gcp_mp_accounts_link_token_idx" ON "public"."nc_gcp_marketplace_accounts" USING "btree" ("link_token");



CREATE INDEX "nc_gcp_mp_accounts_user_idx" ON "public"."nc_gcp_marketplace_accounts" USING "btree" ("fk_user_id");



CREATE INDEX "nc_gcp_mp_ent_account_idx" ON "public"."nc_gcp_marketplace_entitlements" USING "btree" ("fk_gcp_account_id");



CREATE INDEX "nc_gcp_mp_ent_install_idx" ON "public"."nc_gcp_marketplace_entitlements" USING "btree" ("fk_installation_id");



CREATE INDEX "nc_grid_view_columns_v2_base_id_fk_workspace_id_index" ON "public"."nc_grid_view_columns_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_grid_view_columns_v2_fk_column_id_index" ON "public"."nc_grid_view_columns_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_grid_view_columns_v2_fk_view_id_fk_column_id_index" ON "public"."nc_grid_view_columns_v2" USING "btree" ("fk_view_id", "fk_column_id");



CREATE INDEX "nc_grid_view_columns_v2_fk_view_id_index" ON "public"."nc_grid_view_columns_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_grid_view_columns_v2_oldpk_idx" ON "public"."nc_grid_view_columns_v2" USING "btree" ("id");



CREATE INDEX "nc_grid_view_v2_base_id_fk_workspace_id_index" ON "public"."nc_grid_view_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_grid_view_v2_fk_view_id_index" ON "public"."nc_grid_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_grid_view_v2_oldpk_idx" ON "public"."nc_grid_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_hook_logs_error_notify_idx" ON "public"."nc_hook_logs_v2" USING "btree" ("error_notified_at");



CREATE INDEX "nc_hook_logs_v2_base_id_fk_workspace_id_index" ON "public"."nc_hook_logs_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_hook_logs_v2_oldpk_idx" ON "public"."nc_hook_logs_v2" USING "btree" ("id");



CREATE INDEX "nc_hooks_v2_base_id_fk_workspace_id_index" ON "public"."nc_hooks_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_hooks_v2_fk_model_id_index" ON "public"."nc_hooks_v2" USING "btree" ("fk_model_id");



CREATE INDEX "nc_hooks_v2_oldpk_idx" ON "public"."nc_hooks_v2" USING "btree" ("id");



CREATE INDEX "nc_il_integration_idx" ON "public"."nc_integration_links_v2" USING "btree" ("fk_integration_id");



CREATE INDEX "nc_il_ws_base_idx" ON "public"."nc_integration_links_v2" USING "btree" ("fk_workspace_id", "base_id");



CREATE INDEX "nc_installations_fk_user_id_idx" ON "public"."nc_installations" USING "btree" ("fk_user_id");



CREATE INDEX "nc_installations_license_key_idx" ON "public"."nc_installations" USING "btree" ("license_key");



CREATE INDEX "nc_integrations_store_v2_fk_integration_id_index" ON "public"."nc_integrations_store_v2" USING "btree" ("fk_integration_id");



CREATE INDEX "nc_integrations_v2_created_by_index" ON "public"."nc_integrations_v2" USING "btree" ("created_by");



CREATE INDEX "nc_integrations_v2_fk_workspace_id_index" ON "public"."nc_integrations_v2" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_integrations_v2_type_index" ON "public"."nc_integrations_v2" USING "btree" ("type");



CREATE INDEX "nc_jobs_context" ON "public"."nc_jobs" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_kanban_view_columns_v2_base_id_fk_workspace_id_index" ON "public"."nc_kanban_view_columns_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_kanban_view_columns_v2_fk_column_id_index" ON "public"."nc_kanban_view_columns_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_kanban_view_columns_v2_fk_view_id_fk_column_id_index" ON "public"."nc_kanban_view_columns_v2" USING "btree" ("fk_view_id", "fk_column_id");



CREATE INDEX "nc_kanban_view_columns_v2_fk_view_id_index" ON "public"."nc_kanban_view_columns_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_kanban_view_columns_v2_oldpk_idx" ON "public"."nc_kanban_view_columns_v2" USING "btree" ("id");



CREATE INDEX "nc_kanban_view_v2_base_id_fk_workspace_id_index" ON "public"."nc_kanban_view_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_kanban_view_v2_fk_grp_col_id_index" ON "public"."nc_kanban_view_v2" USING "btree" ("fk_grp_col_id");



CREATE INDEX "nc_kanban_view_v2_fk_view_id_index" ON "public"."nc_kanban_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_kanban_view_v2_oldpk_idx" ON "public"."nc_kanban_view_v2" USING "btree" ("fk_view_id");



CREATE UNIQUE INDEX "nc_mail_sends_dedupe_uq" ON "public"."nc_mail_sends" USING "btree" ("event", "dedupe_key") WHERE ("dedupe_key" IS NOT NULL);



CREATE INDEX "nc_mail_sends_dispatch_idx" ON "public"."nc_mail_sends" USING "btree" ("status", "scheduled_for");



CREATE INDEX "nc_mail_sends_message_idx" ON "public"."nc_mail_sends" USING "btree" ("ses_message_id");



CREATE INDEX "nc_mail_sends_user_idx" ON "public"."nc_mail_sends" USING "btree" ("fk_user_id", "created_at");



CREATE INDEX "nc_managed_app_deployment_logs_managed_app_id_idx" ON "public"."nc_managed_app_deployment_logs" USING "btree" ("fk_managed_app_id");



CREATE INDEX "nc_managed_app_versions_managed_app_id_idx" ON "public"."nc_managed_app_versions" USING "btree" ("fk_managed_app_id");



CREATE INDEX "nc_managed_app_versions_ordering_idx" ON "public"."nc_managed_app_versions" USING "btree" ("fk_managed_app_id", "version_number");



CREATE INDEX "nc_managed_app_versions_status_idx" ON "public"."nc_managed_app_versions" USING "btree" ("fk_managed_app_id", "status");



CREATE INDEX "nc_map_view_columns_v2_base_id_fk_workspace_id_index" ON "public"."nc_map_view_columns_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_map_view_columns_v2_fk_column_id_index" ON "public"."nc_map_view_columns_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_map_view_columns_v2_fk_view_id_fk_column_id_index" ON "public"."nc_map_view_columns_v2" USING "btree" ("fk_view_id", "fk_column_id");



CREATE INDEX "nc_map_view_columns_v2_fk_view_id_index" ON "public"."nc_map_view_columns_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_map_view_columns_v2_oldpk_idx" ON "public"."nc_map_view_columns_v2" USING "btree" ("id");



CREATE INDEX "nc_map_view_v2_base_id_fk_workspace_id_index" ON "public"."nc_map_view_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_map_view_v2_fk_geo_data_col_id_index" ON "public"."nc_map_view_v2" USING "btree" ("fk_geo_data_col_id");



CREATE INDEX "nc_map_view_v2_fk_view_id_index" ON "public"."nc_map_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_map_view_v2_oldpk_idx" ON "public"."nc_map_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_mc_tokens_context" ON "public"."nc_mcp_tokens" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_mcp_tokens_oldpk_idx" ON "public"."nc_mcp_tokens" USING "btree" ("id");



CREATE INDEX "nc_model_stats_v2_base_id_fk_workspace_id_index" ON "public"."nc_model_stats_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_model_stats_v2_fk_workspace_id_index" ON "public"."nc_model_stats_v2" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_model_stats_v2_oldpk_idx" ON "public"."nc_model_stats_v2" USING "btree" ("fk_workspace_id", "fk_model_id");



CREATE INDEX "nc_models_v2_base_id_fk_workspace_id_index" ON "public"."nc_models_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_models_v2_oldpk_idx" ON "public"."nc_models_v2" USING "btree" ("id");



CREATE INDEX "nc_models_v2_source_id_index" ON "public"."nc_models_v2" USING "btree" ("source_id");



CREATE INDEX "nc_models_v2_tree_idx" ON "public"."nc_models_v2" USING "btree" ("base_id", "type", "parent_id", "order");



CREATE INDEX "nc_models_v2_type_index" ON "public"."nc_models_v2" USING "btree" ("type");



CREATE INDEX "nc_models_v2_uuid_index" ON "public"."nc_models_v2" USING "btree" ("uuid");



CREATE INDEX "nc_oauth_authorization_codes_code_index" ON "public"."nc_oauth_authorization_codes" USING "btree" ("code");



CREATE INDEX "nc_oauth_authorization_codes_expires_at_index" ON "public"."nc_oauth_authorization_codes" USING "btree" ("expires_at");



CREATE INDEX "nc_oauth_authorization_codes_fk_client_id_fk_user_id_index" ON "public"."nc_oauth_authorization_codes" USING "btree" ("fk_client_id", "fk_user_id");



CREATE INDEX "nc_oauth_authorization_codes_fk_client_id_index" ON "public"."nc_oauth_authorization_codes" USING "btree" ("fk_client_id");



CREATE INDEX "nc_oauth_authorization_codes_fk_user_id_index" ON "public"."nc_oauth_authorization_codes" USING "btree" ("fk_user_id");



CREATE INDEX "nc_oauth_authorization_codes_is_used_index" ON "public"."nc_oauth_authorization_codes" USING "btree" ("is_used");



CREATE INDEX "nc_oauth_clients_fk_user_id_index" ON "public"."nc_oauth_clients" USING "btree" ("fk_user_id");



CREATE INDEX "nc_oauth_tokens_access_token_expires_at_index" ON "public"."nc_oauth_tokens" USING "btree" ("access_token_expires_at");



CREATE INDEX "nc_oauth_tokens_access_token_index" ON "public"."nc_oauth_tokens" USING "btree" ("access_token");



CREATE INDEX "nc_oauth_tokens_fk_client_id_fk_user_id_index" ON "public"."nc_oauth_tokens" USING "btree" ("fk_client_id", "fk_user_id");



CREATE INDEX "nc_oauth_tokens_fk_client_id_index" ON "public"."nc_oauth_tokens" USING "btree" ("fk_client_id");



CREATE INDEX "nc_oauth_tokens_fk_user_id_index" ON "public"."nc_oauth_tokens" USING "btree" ("fk_user_id");



CREATE INDEX "nc_oauth_tokens_is_revoked_access_token_expires_at_index" ON "public"."nc_oauth_tokens" USING "btree" ("is_revoked", "access_token_expires_at");



CREATE INDEX "nc_oauth_tokens_is_revoked_index" ON "public"."nc_oauth_tokens" USING "btree" ("is_revoked");



CREATE INDEX "nc_oauth_tokens_last_used_at_index" ON "public"."nc_oauth_tokens" USING "btree" ("last_used_at");



CREATE INDEX "nc_oauth_tokens_refresh_token_expires_at_index" ON "public"."nc_oauth_tokens" USING "btree" ("refresh_token_expires_at");



CREATE INDEX "nc_oauth_tokens_refresh_token_index" ON "public"."nc_oauth_tokens" USING "btree" ("refresh_token");



CREATE INDEX "nc_op_logs_cleanup_due_at_idx" ON "public"."nc_operation_logs" USING "btree" ("cleanup_due_at");



CREATE INDEX "nc_op_logs_user_tab_scope_status_seq_idx" ON "public"."nc_operation_logs" USING "btree" ("fk_user_id", "tab_id", "scope_type", "scope_id", "status", "seq");



CREATE INDEX "nc_org_domain_domain_index" ON "public"."nc_org_domain" USING "btree" ("domain");



CREATE INDEX "nc_org_domain_fk_org_id_index" ON "public"."nc_org_domain" USING "btree" ("fk_org_id");



CREATE INDEX "nc_org_domain_fk_user_id_index" ON "public"."nc_org_domain" USING "btree" ("fk_user_id");



CREATE INDEX "nc_org_fk_user_id_index" ON "public"."nc_org" USING "btree" ("fk_user_id");



CREATE INDEX "nc_org_slug_index" ON "public"."nc_org" USING "btree" ("slug");



CREATE INDEX "nc_org_users_fk_user_id_index" ON "public"."nc_org_users" USING "btree" ("fk_user_id");



CREATE INDEX "nc_org_users_scim_external_id_idx" ON "public"."nc_org_users" USING "btree" ("scim_external_id");



CREATE INDEX "nc_org_users_scim_managed_idx" ON "public"."nc_org_users" USING "btree" ("scim_managed");



CREATE INDEX "nc_outline_view_columns_v2_base_id_fk_workspace_id_index" ON "public"."nc_list_view_columns_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_outline_view_columns_v2_fk_view_id_fk_column_id_index" ON "public"."nc_list_view_columns_v2" USING "btree" ("fk_view_id", "fk_column_id");



CREATE INDEX "nc_outline_view_columns_v2_fk_view_id_index" ON "public"."nc_list_view_columns_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_outline_view_levels_v2_base_id_fk_workspace_id_index" ON "public"."nc_list_view_levels_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_outline_view_levels_v2_fk_view_id_index" ON "public"."nc_list_view_levels_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_outline_view_v2_base_id_fk_workspace_id_index" ON "public"."nc_list_view_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_outline_view_v2_fk_view_id_index" ON "public"."nc_list_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_permission_subjects_context" ON "public"."nc_permission_subjects" USING "btree" ("fk_workspace_id", "base_id");



CREATE INDEX "nc_permission_subjects_oldpk_idx" ON "public"."nc_permission_subjects" USING "btree" ("fk_permission_id", "subject_type", "subject_id");



CREATE INDEX "nc_permissions_context" ON "public"."nc_permissions" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_permissions_entity" ON "public"."nc_permissions" USING "btree" ("entity", "entity_id", "permission");



CREATE INDEX "nc_permissions_oldpk_idx" ON "public"."nc_permissions" USING "btree" ("id");



CREATE INDEX "nc_plans_stripe_product_idx" ON "public"."nc_plans" USING "btree" ("stripe_product_id");



CREATE INDEX "nc_principal_assignments_principal_idx" ON "public"."nc_principal_assignments" USING "btree" ("principal_type", "principal_ref_id");



CREATE INDEX "nc_principal_assignments_principal_resource_idx" ON "public"."nc_principal_assignments" USING "btree" ("principal_type", "principal_ref_id", "resource_type");



CREATE INDEX "nc_principal_assignments_resource_idx" ON "public"."nc_principal_assignments" USING "btree" ("resource_type", "resource_id");



CREATE INDEX "nc_principal_assignments_resource_principal_type_idx" ON "public"."nc_principal_assignments" USING "btree" ("resource_type", "resource_id", "principal_type");



CREATE INDEX "nc_project_users_v2_fk_user_id_index" ON "public"."nc_base_users_v2" USING "btree" ("fk_user_id");



CREATE INDEX "nc_record_audit_v2_tenant_idx" ON "public"."nc_audit_v2" USING "btree" ("base_id", "fk_model_id", "row_id", "fk_workspace_id");



CREATE INDEX "nc_record_templates_base_id_index" ON "public"."nc_record_templates" USING "btree" ("base_id");



CREATE INDEX "nc_record_templates_fk_model_id_index" ON "public"."nc_record_templates" USING "btree" ("fk_model_id");



CREATE INDEX "nc_record_templates_fk_workspace_id_index" ON "public"."nc_record_templates" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_rls_policies_model_default_idx" ON "public"."nc_rls_policies" USING "btree" ("fk_model_id", "is_default");



CREATE INDEX "nc_rls_policies_model_enabled_idx" ON "public"."nc_rls_policies" USING "btree" ("fk_model_id", "enabled");



CREATE INDEX "nc_rls_policy_subjects_context_idx" ON "public"."nc_rls_policy_subjects" USING "btree" ("fk_workspace_id", "base_id");



CREATE INDEX "nc_row_color_conditions_fk_view_id_index" ON "public"."nc_row_color_conditions" USING "btree" ("fk_view_id");



CREATE INDEX "nc_row_color_conditions_fk_workspace_id_base_id_index" ON "public"."nc_row_color_conditions" USING "btree" ("fk_workspace_id", "base_id");



CREATE INDEX "nc_row_color_conditions_oldpk_idx" ON "public"."nc_row_color_conditions" USING "btree" ("id");



CREATE INDEX "nc_ry6x___Features_deleted_idx" ON "public"."nc_ry6x___Features" USING "btree" ("__nc_deleted");



CREATE INDEX "nc_ry6x___Features_order_idx" ON "public"."nc_ry6x___Features" USING "btree" ("nc_order");



CREATE INDEX "nc_sandbox_deployment_logs_base_created_idx" ON "public"."nc_managed_app_deployment_logs" USING "btree" ("base_id", "created_at");



CREATE INDEX "nc_sandbox_deployment_logs_base_id_idx" ON "public"."nc_managed_app_deployment_logs" USING "btree" ("base_id");



CREATE INDEX "nc_sandbox_deployment_logs_from_version_idx" ON "public"."nc_managed_app_deployment_logs" USING "btree" ("from_version_id");



CREATE INDEX "nc_sandbox_deployment_logs_status_idx" ON "public"."nc_managed_app_deployment_logs" USING "btree" ("status");



CREATE INDEX "nc_sandbox_deployment_logs_to_version_idx" ON "public"."nc_managed_app_deployment_logs" USING "btree" ("to_version_id");



CREATE INDEX "nc_sandbox_deployment_logs_workspace_id_idx" ON "public"."nc_managed_app_deployment_logs" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_sandbox_versions_workspace_id_idx" ON "public"."nc_managed_app_versions" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_sandboxes_base_id_idx" ON "public"."nc_managed_apps" USING "btree" ("base_id");



CREATE INDEX "nc_sandboxes_category_idx" ON "public"."nc_managed_apps" USING "btree" ("category");



CREATE INDEX "nc_sandboxes_created_by_idx" ON "public"."nc_managed_apps" USING "btree" ("created_by");



CREATE INDEX "nc_sandboxes_deleted_idx" ON "public"."nc_managed_apps" USING "btree" ("deleted");



CREATE INDEX "nc_sandboxes_v2_created_by_idx" ON "public"."nc_sandboxes_v2" USING "btree" ("created_by");



CREATE INDEX "nc_sandboxes_v2_production_base_id_idx" ON "public"."nc_sandboxes_v2" USING "btree" ("production_base_id");



CREATE INDEX "nc_sandboxes_v2_sandbox_base_id_idx" ON "public"."nc_sandboxes_v2" USING "btree" ("sandbox_base_id");



CREATE INDEX "nc_sandboxes_v2_workspace_id_idx" ON "public"."nc_sandboxes_v2" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_sandboxes_visibility_idx" ON "public"."nc_managed_apps" USING "btree" ("visibility");



CREATE INDEX "nc_sandboxes_workspace_id_idx" ON "public"."nc_managed_apps" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_scim_config_org_idx" ON "public"."nc_scim_config" USING "btree" ("fk_org_id");



CREATE INDEX "nc_scl_base_id_index" ON "public"."nc_sandbox_changelog" USING "btree" ("base_id");



CREATE INDEX "nc_scl_entity_type_id_index" ON "public"."nc_sandbox_changelog" USING "btree" ("entity_type", "entity_id");



CREATE INDEX "nc_scl_sandbox_seq_index" ON "public"."nc_sandbox_changelog" USING "btree" ("fk_sandbox_id", "seq");



CREATE INDEX "nc_scripts_context" ON "public"."nc_scripts" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_scripts_oldpk_idx" ON "public"."nc_scripts" USING "btree" ("id");



CREATE INDEX "nc_snapshot_context" ON "public"."nc_snapshots" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_sort_v2_base_id_fk_workspace_id_index" ON "public"."nc_sort_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_sort_v2_fk_column_id_index" ON "public"."nc_sort_v2" USING "btree" ("fk_column_id");



CREATE INDEX "nc_sort_v2_fk_level_id_index" ON "public"."nc_sort_v2" USING "btree" ("fk_level_id");



CREATE INDEX "nc_sort_v2_fk_view_id_index" ON "public"."nc_sort_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_sort_v2_oldpk_idx" ON "public"."nc_sort_v2" USING "btree" ("id");



CREATE INDEX "nc_source_v2_base_id_fk_workspace_id_index" ON "public"."nc_sources_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_source_v2_fk_integration_id_index" ON "public"."nc_sources_v2" USING "btree" ("fk_integration_id");



CREATE INDEX "nc_source_v2_fk_sql_executor_id_index" ON "public"."nc_sources_v2" USING "btree" ("fk_sql_executor_id");



CREATE INDEX "nc_sources_v2_oldpk_idx" ON "public"."nc_sources_v2" USING "btree" ("id");



CREATE INDEX "nc_sso_client_domain_name_index" ON "public"."nc_sso_client" USING "btree" ("domain_name");



CREATE INDEX "nc_sso_client_fk_user_id_index" ON "public"."nc_sso_client" USING "btree" ("fk_user_id");



CREATE INDEX "nc_sso_client_fk_workspace_id_index" ON "public"."nc_sso_client" USING "btree" ("fk_org_id");



CREATE INDEX "nc_store_key_index" ON "public"."nc_store" USING "btree" ("key");



CREATE INDEX "nc_subscription_addons_key_idx" ON "public"."nc_subscription_addons" USING "btree" ("addon_key");



CREATE INDEX "nc_subscription_addons_sub_idx" ON "public"."nc_subscription_addons" USING "btree" ("fk_subscription_id");



CREATE INDEX "nc_subscriptions_org_idx" ON "public"."nc_subscriptions" USING "btree" ("fk_org_id");



CREATE INDEX "nc_subscriptions_stripe_subscription_idx" ON "public"."nc_subscriptions" USING "btree" ("stripe_subscription_id");



CREATE INDEX "nc_subscriptions_ws_idx" ON "public"."nc_subscriptions" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_sync_configs_context" ON "public"."nc_sync_configs" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_sync_configs_oldpk_idx" ON "public"."nc_sync_configs" USING "btree" ("id");



CREATE INDEX "nc_sync_configs_parent_idx" ON "public"."nc_sync_configs" USING "btree" ("fk_parent_sync_config_id");



CREATE INDEX "nc_sync_logs_v2_base_id_fk_workspace_id_index" ON "public"."nc_sync_logs_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_sync_logs_v2_oldpk_idx" ON "public"."nc_sync_logs_v2" USING "btree" ("id");



CREATE INDEX "nc_sync_mappings_context" ON "public"."nc_sync_mappings" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_sync_mappings_oldpk_idx" ON "public"."nc_sync_mappings" USING "btree" ("id");



CREATE INDEX "nc_sync_mappings_sync_config_idx" ON "public"."nc_sync_mappings" USING "btree" ("fk_sync_config_id");



CREATE INDEX "nc_sync_source_v2_base_id_fk_workspace_id_index" ON "public"."nc_sync_source_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_sync_source_v2_oldpk_idx" ON "public"."nc_sync_source_v2" USING "btree" ("id");



CREATE INDEX "nc_sync_source_v2_source_id_index" ON "public"."nc_sync_source_v2" USING "btree" ("source_id");



CREATE INDEX "nc_teams_created_by_idx" ON "public"."nc_teams" USING "btree" ("created_by");



CREATE INDEX "nc_teams_org_idx" ON "public"."nc_teams" USING "btree" ("fk_org_id");



CREATE INDEX "nc_teams_parent_idx" ON "public"."nc_teams" USING "btree" ("fk_parent_team_id");



CREATE INDEX "nc_teams_scim_external_id_idx" ON "public"."nc_teams" USING "btree" ("scim_external_id");



CREATE INDEX "nc_teams_scim_managed_idx" ON "public"."nc_teams" USING "btree" ("scim_managed");



CREATE INDEX "nc_teams_workspace_idx" ON "public"."nc_teams" USING "btree" ("fk_workspace_id");



CREATE INDEX "nc_timeline_view_columns_v2_base_id_fk_workspace_id_index" ON "public"."nc_timeline_view_columns_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_timeline_view_columns_v2_fk_view_id_fk_column_id_index" ON "public"."nc_timeline_view_columns_v2" USING "btree" ("fk_view_id", "fk_column_id");



CREATE INDEX "nc_timeline_view_columns_v2_oldpk_idx" ON "public"."nc_timeline_view_columns_v2" USING "btree" ("id");



CREATE INDEX "nc_timeline_view_range_v2_base_id_fk_workspace_id_index" ON "public"."nc_timeline_view_range_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_timeline_view_range_v2_oldpk_idx" ON "public"."nc_timeline_view_range_v2" USING "btree" ("id");



CREATE INDEX "nc_timeline_view_v2_base_id_fk_workspace_id_index" ON "public"."nc_timeline_view_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_timeline_view_v2_oldpk_idx" ON "public"."nc_timeline_view_v2" USING "btree" ("fk_view_id");



CREATE INDEX "nc_trash_base_id_fk_workspace_id_index" ON "public"."nc_trash" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_trash_cleanup_due_at_index" ON "public"."nc_trash" USING "btree" ("cleanup_due_at");



CREATE INDEX "nc_ts_ws_base_idx" ON "public"."nc_table_syncs" USING "btree" ("fk_workspace_id", "base_id");



CREATE INDEX "nc_tscm_dest_col_idx" ON "public"."nc_table_sync_column_mappings" USING "btree" ("dest_column_id");



CREATE INDEX "nc_tscm_mapping_idx" ON "public"."nc_table_sync_column_mappings" USING "btree" ("fk_table_sync_mapping_id");



CREATE INDEX "nc_tscm_source_col_idx" ON "public"."nc_table_sync_column_mappings" USING "btree" ("source_workspace_id", "source_base_id", "source_column_id");



CREATE INDEX "nc_tscm_sync_idx" ON "public"."nc_table_sync_column_mappings" USING "btree" ("fk_table_sync_id");



CREATE INDEX "nc_tsm_source_idx" ON "public"."nc_table_sync_mappings" USING "btree" ("source_workspace_id", "source_base_id", "source_table_id");



CREATE INDEX "nc_tsm_source_uuid_idx" ON "public"."nc_table_sync_mappings" USING "btree" ("source_uuid");



CREATE INDEX "nc_tsm_table_sync_idx" ON "public"."nc_table_sync_mappings" USING "btree" ("fk_table_sync_id");



CREATE INDEX "nc_usage_stats_ws_period_idx" ON "public"."nc_usage_stats" USING "btree" ("fk_workspace_id", "period_start");



CREATE INDEX "nc_user_comment_notifications_preference_base_id_fk_workspace_i" ON "public"."nc_user_comment_notifications_preference" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_user_refresh_tokens_expires_at_index" ON "public"."nc_user_refresh_tokens" USING "btree" ("expires_at");



CREATE INDEX "nc_user_refresh_tokens_fk_user_id_index" ON "public"."nc_user_refresh_tokens" USING "btree" ("fk_user_id");



CREATE INDEX "nc_user_refresh_tokens_token_index" ON "public"."nc_user_refresh_tokens" USING "btree" ("token");



CREATE INDEX "nc_users_v2_canonical_email_index" ON "public"."nc_users_v2" USING "btree" ("canonical_email");



CREATE INDEX "nc_users_v2_email_index" ON "public"."nc_users_v2" USING "btree" ("email");



CREATE INDEX "nc_users_v2_last_active_at_idx" ON "public"."nc_users_v2" USING "btree" ("last_active_at");



CREATE INDEX "nc_view_sections_context" ON "public"."nc_view_sections" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_view_sections_model_idx" ON "public"."nc_view_sections" USING "btree" ("fk_model_id");



CREATE INDEX "nc_views_v2_base_id_fk_workspace_id_index" ON "public"."nc_views_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_views_v2_created_by_index" ON "public"."nc_views_v2" USING "btree" ("created_by");



CREATE INDEX "nc_views_v2_fk_custom_url_id_index" ON "public"."nc_views_v2" USING "btree" ("fk_custom_url_id");



CREATE INDEX "nc_views_v2_fk_model_id_index" ON "public"."nc_views_v2" USING "btree" ("fk_model_id");



CREATE INDEX "nc_views_v2_oldpk_idx" ON "public"."nc_views_v2" USING "btree" ("id");



CREATE INDEX "nc_views_v2_owned_by_index" ON "public"."nc_views_v2" USING "btree" ("owned_by");



CREATE INDEX "nc_widgets_context" ON "public"."nc_widgets_v2" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_widgets_dashboard_idx" ON "public"."nc_widgets_v2" USING "btree" ("fk_dashboard_id");



CREATE INDEX "nc_widgets_v2_oldpk_idx" ON "public"."nc_widgets_v2" USING "btree" ("id");



CREATE INDEX "nc_workflow_executions_context_idx" ON "public"."nc_automation_executions" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_workflow_executions_workflow_idx" ON "public"."nc_automation_executions" USING "btree" ("fk_workflow_id");



CREATE INDEX "nc_workflows_context_idx" ON "public"."nc_workflows" USING "btree" ("base_id", "fk_workspace_id");



CREATE INDEX "nc_workspace_user_scim_external_id_idx" ON "public"."workspace_user" USING "btree" ("scim_external_id");



CREATE INDEX "nc_workspace_user_scim_managed_idx" ON "public"."workspace_user" USING "btree" ("scim_managed");



CREATE INDEX "notification_created_at_index" ON "public"."notification" USING "btree" ("created_at");



CREATE INDEX "notification_fk_user_id_index" ON "public"."notification" USING "btree" ("fk_user_id");



CREATE INDEX "org_domain_fk_workspace_id_idx" ON "public"."nc_org_domain" USING "btree" ("fk_workspace_id");



CREATE INDEX "share_uuid_idx" ON "public"."nc_dashboards_v2" USING "btree" ("uuid");



CREATE INDEX "sso_client_fk_workspace_id_idx" ON "public"."nc_sso_client" USING "btree" ("fk_workspace_id");



CREATE INDEX "sync_configs_integration_model" ON "public"."nc_sync_configs" USING "btree" ("fk_model_id", "fk_integration_id");



CREATE INDEX "user_comments_preference_index" ON "public"."nc_user_comment_notifications_preference" USING "btree" ("user_id", "row_id", "fk_model_id");



CREATE INDEX "workspace_fk_org_id_index" ON "public"."workspace" USING "btree" ("fk_org_id");



CREATE INDEX "workspace_user_invited_by_index" ON "public"."workspace_user" USING "btree" ("invited_by");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."categories"("id");



ALTER TABLE ONLY "public"."entity_categories"
    ADD CONSTRAINT "entity_categories_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id");



ALTER TABLE ONLY "public"."entity_categories"
    ADD CONSTRAINT "entity_categories_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "public"."entities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_addressee_id_fkey" FOREIGN KEY ("addressee_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."friendships"
    ADD CONSTRAINT "friendships_requester_id_fkey" FOREIGN KEY ("requester_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hidden_entities"
    ADD CONSTRAINT "hidden_entities_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "public"."entities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hidden_entities"
    ADD CONSTRAINT "hidden_entities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_items"
    ADD CONSTRAINT "list_items_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "public"."entities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_items"
    ADD CONSTRAINT "list_items_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "lists_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."saved_lists"
    ADD CONSTRAINT "saved_lists_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."saved_lists"
    ADD CONSTRAINT "saved_lists_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."stars"
    ADD CONSTRAINT "stars_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "public"."entities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."stars"
    ADD CONSTRAINT "stars_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



CREATE POLICY "Addressee accepts or blocks" ON "public"."friendships" FOR UPDATE USING (("auth"."uid"() = "addressee_id"));



CREATE POLICY "Categories are publicly readable" ON "public"."categories" FOR SELECT USING (true);



CREATE POLICY "Create your own lists" ON "public"."lists" FOR INSERT WITH CHECK (("owner_id" = "auth"."uid"()));



CREATE POLICY "Delete your own lists" ON "public"."lists" FOR DELETE USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "Either side can remove" ON "public"."friendships" FOR DELETE USING ((("auth"."uid"() = "requester_id") OR ("auth"."uid"() = "addressee_id")));



CREATE POLICY "Entities are publicly readable" ON "public"."entities" FOR SELECT USING (true);



CREATE POLICY "Owner adds items" ON "public"."list_items" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_items"."list_id") AND ("l"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owner removes items" ON "public"."list_items" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_items"."list_id") AND ("l"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owner updates items" ON "public"."list_items" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_items"."list_id") AND ("l"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owners can add items to their own lists" ON "public"."list_items" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_items"."list_id") AND ("l"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owners can remove items from their own lists" ON "public"."list_items" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_items"."list_id") AND ("l"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owners can update their own lists" ON "public"."lists" FOR UPDATE TO "authenticated" USING (("owner_id" = "auth"."uid"())) WITH CHECK (("owner_id" = "auth"."uid"()));



CREATE POLICY "Profiles are publicly readable" ON "public"."profiles" FOR SELECT USING (true);



CREATE POLICY "See your own friendships" ON "public"."friendships" FOR SELECT USING ((("auth"."uid"() = "requester_id") OR ("auth"."uid"() = "addressee_id")));



CREATE POLICY "Send requests as yourself" ON "public"."friendships" FOR INSERT WITH CHECK (("auth"."uid"() = "requester_id"));



CREATE POLICY "Update your own lists" ON "public"."lists" FOR UPDATE USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "Users can create their own lists" ON "public"."lists" FOR INSERT TO "authenticated" WITH CHECK (("owner_id" = "auth"."uid"()));



CREATE POLICY "Users can delete their own hidden entities" ON "public"."hidden_entities" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can delete their own lists" ON "public"."lists" FOR DELETE TO "authenticated" USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "Users can delete their own stars" ON "public"."stars" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can insert their own hidden entities" ON "public"."hidden_entities" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can insert their own stars" ON "public"."stars" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view items of visible lists" ON "public"."list_items" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_items"."list_id") AND (("l"."owner_id" = "auth"."uid"()) OR ("l"."visibility" = 'public'::"text") OR (("l"."visibility" = 'friends'::"text") AND (EXISTS ( SELECT 1
           FROM "public"."friendships" "f"
          WHERE (("f"."status" = 'accepted'::"text") AND ((("f"."requester_id" = "auth"."uid"()) AND ("f"."addressee_id" = "l"."owner_id")) OR (("f"."addressee_id" = "auth"."uid"()) AND ("f"."requester_id" = "l"."owner_id"))))))))))));



CREATE POLICY "Users can view their own hidden entities" ON "public"."hidden_entities" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view their own profile" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("id" = "auth"."uid"()));



CREATE POLICY "Users can view their own stars" ON "public"."stars" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view visible lists" ON "public"."lists" FOR SELECT TO "authenticated" USING ((("owner_id" = "auth"."uid"()) OR ("visibility" = 'public'::"text") OR (("visibility" = 'friends'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."friendships" "f"
  WHERE (("f"."status" = 'accepted'::"text") AND ((("f"."requester_id" = "auth"."uid"()) AND ("f"."addressee_id" = "lists"."owner_id")) OR (("f"."addressee_id" = "auth"."uid"()) AND ("f"."requester_id" = "lists"."owner_id")))))))));



CREATE POLICY "Users hide for themselves" ON "public"."hidden_entities" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users save lists for themselves" ON "public"."saved_lists" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Users star for themselves" ON "public"."stars" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users unhide their own" ON "public"."hidden_entities" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users unsave their own" ON "public"."saved_lists" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users unstar their own" ON "public"."stars" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users update their own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users view their own and friends' stars" ON "public"."stars" FOR SELECT USING ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."friendships" "f"
  WHERE (("f"."status" = 'accepted'::"text") AND ((("f"."requester_id" = "auth"."uid"()) AND ("f"."addressee_id" = "stars"."user_id")) OR (("f"."addressee_id" = "auth"."uid"()) AND ("f"."requester_id" = "stars"."user_id"))))))));



CREATE POLICY "Users view their own hidden list" ON "public"."hidden_entities" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users view their own saved lists" ON "public"."saved_lists" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "View items of visible lists" ON "public"."list_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE ("l"."id" = "list_items"."list_id"))));



CREATE POLICY "View own, public, or friends-only lists" ON "public"."lists" FOR SELECT USING ((("owner_id" = "auth"."uid"()) OR ("visibility" = 'public'::"text") OR (("visibility" = 'friends'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."friendships" "f"
  WHERE (("f"."status" = 'accepted'::"text") AND ((("f"."requester_id" = "auth"."uid"()) AND ("f"."addressee_id" = "lists"."owner_id")) OR (("f"."addressee_id" = "auth"."uid"()) AND ("f"."requester_id" = "lists"."owner_id")))))))));



ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."entities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."entity_categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."friendships" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."hidden_entities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."list_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."lists" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_addons" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_api_token_scopes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_api_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_audit_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_automation_executions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_automation_subscribers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_automations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_base_users_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_base_variables" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_bases_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_bookmark_groups" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_bookmarks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_calendar_view_columns_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_calendar_view_range_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_calendar_view_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_chat_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_chat_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_col_barcode_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_col_button_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_col_formula_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_col_long_text_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_col_lookup_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_col_qrcode_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_col_relations_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_col_rollup_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_col_select_options_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_columns_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_comment_reactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_comments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_custom_urls_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_dashboards_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_data_reflection" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_date_dependency_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_db_servers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_dependency_tracker" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_disabled_models_for_role_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_doc_content_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_doc_revisions_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_docs_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_extensions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_file_references" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_filter_exp_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_follower" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_form_view_columns_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_form_view_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_gallery_view_columns_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_gallery_view_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_gantt_view_columns_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_gantt_view_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_gcp_marketplace_accounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_gcp_marketplace_entitlements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_grid_view_columns_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_grid_view_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_hook_logs_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_hook_trigger_fields" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_hooks_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_installations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_integration_links_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_integrations_store_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_integrations_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_jobs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_kanban_view_columns_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_kanban_view_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_list_view_columns_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_list_view_levels_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_list_view_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_mail_sends" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_managed_app_deployment_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_managed_app_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_managed_apps" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_map_view_columns_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_map_view_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_mcp_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_model_stats_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_models_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_oauth_authorization_codes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_oauth_clients" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_oauth_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_operation_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_org" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_org_domain" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_org_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_permission_subjects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_plans" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_plugins_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_principal_assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_record_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_rls_policies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_rls_policy_subjects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_row_color_conditions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_ry6x___Features" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sandbox_changelog" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sandboxes_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_scim_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_scripts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_snapshots" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sort_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sources_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sql_executor_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sso_client" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sso_client_domain" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_store" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_subscription_addons" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sync_configs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sync_logs_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sync_mappings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_sync_source_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_table_sync_column_mappings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_table_sync_mappings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_table_syncs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_teams" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_timeline_view_columns_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_timeline_view_range_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_timeline_view_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_trash" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_usage_stats" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_user_comment_notifications_preference" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_user_refresh_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_users_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_view_sections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_views_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_widgets_v2" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nc_workflows" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."saved_lists" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."stars" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."workspace" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."workspace_user" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."xc_knex_migrationsv0" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."xc_knex_migrationsv0_lock" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";











































































GRANT ALL ON FUNCTION "public"."lquery_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."lquery_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."lquery_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lquery_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."lquery_out"("public"."lquery") TO "postgres";
GRANT ALL ON FUNCTION "public"."lquery_out"("public"."lquery") TO "anon";
GRANT ALL ON FUNCTION "public"."lquery_out"("public"."lquery") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lquery_out"("public"."lquery") TO "service_role";



GRANT ALL ON FUNCTION "public"."lquery_recv"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."lquery_recv"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."lquery_recv"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lquery_recv"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."lquery_send"("public"."lquery") TO "postgres";
GRANT ALL ON FUNCTION "public"."lquery_send"("public"."lquery") TO "anon";
GRANT ALL ON FUNCTION "public"."lquery_send"("public"."lquery") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lquery_send"("public"."lquery") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_out"("public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_out"("public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_out"("public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_out"("public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_recv"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_recv"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_recv"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_recv"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_send"("public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_send"("public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_send"("public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_send"("public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_gist_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_gist_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_gist_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_gist_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_gist_out"("public"."ltree_gist") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_gist_out"("public"."ltree_gist") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_gist_out"("public"."ltree_gist") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_gist_out"("public"."ltree_gist") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltxtq_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltxtq_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."ltxtq_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltxtq_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltxtq_out"("public"."ltxtquery") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltxtq_out"("public"."ltxtquery") TO "anon";
GRANT ALL ON FUNCTION "public"."ltxtq_out"("public"."ltxtquery") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltxtq_out"("public"."ltxtquery") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltxtq_recv"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltxtq_recv"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ltxtq_recv"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltxtq_recv"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltxtq_send"("public"."ltxtquery") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltxtq_send"("public"."ltxtquery") TO "anon";
GRANT ALL ON FUNCTION "public"."ltxtq_send"("public"."ltxtquery") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltxtq_send"("public"."ltxtquery") TO "service_role";







































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































GRANT ALL ON FUNCTION "public"."_lt_q_regex"("public"."ltree"[], "public"."lquery"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_lt_q_regex"("public"."ltree"[], "public"."lquery"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_lt_q_regex"("public"."ltree"[], "public"."lquery"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_lt_q_regex"("public"."ltree"[], "public"."lquery"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_lt_q_rregex"("public"."lquery"[], "public"."ltree"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_lt_q_rregex"("public"."lquery"[], "public"."ltree"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_lt_q_rregex"("public"."lquery"[], "public"."ltree"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_lt_q_rregex"("public"."lquery"[], "public"."ltree"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltq_extract_regex"("public"."ltree"[], "public"."lquery") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltq_extract_regex"("public"."ltree"[], "public"."lquery") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltq_extract_regex"("public"."ltree"[], "public"."lquery") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltq_extract_regex"("public"."ltree"[], "public"."lquery") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltq_regex"("public"."ltree"[], "public"."lquery") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltq_regex"("public"."ltree"[], "public"."lquery") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltq_regex"("public"."ltree"[], "public"."lquery") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltq_regex"("public"."ltree"[], "public"."lquery") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltq_rregex"("public"."lquery", "public"."ltree"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltq_rregex"("public"."lquery", "public"."ltree"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_ltq_rregex"("public"."lquery", "public"."ltree"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltq_rregex"("public"."lquery", "public"."ltree"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_consistent"("internal", "public"."ltree"[], smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_consistent"("internal", "public"."ltree"[], smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_consistent"("internal", "public"."ltree"[], smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_consistent"("internal", "public"."ltree"[], smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_extract_isparent"("public"."ltree"[], "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_extract_isparent"("public"."ltree"[], "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_extract_isparent"("public"."ltree"[], "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_extract_isparent"("public"."ltree"[], "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_extract_risparent"("public"."ltree"[], "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_extract_risparent"("public"."ltree"[], "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_extract_risparent"("public"."ltree"[], "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_extract_risparent"("public"."ltree"[], "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_gist_options"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_gist_options"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_gist_options"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_gist_options"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_isparent"("public"."ltree"[], "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_isparent"("public"."ltree"[], "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_isparent"("public"."ltree"[], "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_isparent"("public"."ltree"[], "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_r_isparent"("public"."ltree", "public"."ltree"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_r_isparent"("public"."ltree", "public"."ltree"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_r_isparent"("public"."ltree", "public"."ltree"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_r_isparent"("public"."ltree", "public"."ltree"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_r_risparent"("public"."ltree", "public"."ltree"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_r_risparent"("public"."ltree", "public"."ltree"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_r_risparent"("public"."ltree", "public"."ltree"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_r_risparent"("public"."ltree", "public"."ltree"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_risparent"("public"."ltree"[], "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_risparent"("public"."ltree"[], "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_risparent"("public"."ltree"[], "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_risparent"("public"."ltree"[], "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_same"("public"."ltree_gist", "public"."ltree_gist", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_same"("public"."ltree_gist", "public"."ltree_gist", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_same"("public"."ltree_gist", "public"."ltree_gist", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_same"("public"."ltree_gist", "public"."ltree_gist", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltree_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltree_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltree_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltree_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltxtq_exec"("public"."ltree"[], "public"."ltxtquery") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltxtq_exec"("public"."ltree"[], "public"."ltxtquery") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltxtq_exec"("public"."ltree"[], "public"."ltxtquery") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltxtq_exec"("public"."ltree"[], "public"."ltxtquery") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltxtq_extract_exec"("public"."ltree"[], "public"."ltxtquery") TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltxtq_extract_exec"("public"."ltree"[], "public"."ltxtquery") TO "anon";
GRANT ALL ON FUNCTION "public"."_ltxtq_extract_exec"("public"."ltree"[], "public"."ltxtquery") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltxtq_extract_exec"("public"."ltree"[], "public"."ltxtquery") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ltxtq_rexec"("public"."ltxtquery", "public"."ltree"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."_ltxtq_rexec"("public"."ltxtquery", "public"."ltree"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."_ltxtq_rexec"("public"."ltxtquery", "public"."ltree"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ltxtq_rexec"("public"."ltxtquery", "public"."ltree"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_list_entities"("p_list_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_list_entities"("p_list_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_list_meta"("p_list_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_list_meta"("p_list_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_lists_shared_with_me"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_lists_shared_with_me"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_lists_shared_with_me"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_home_location"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_home_location"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_my_saved_lists"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_saved_lists"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_saved_lists"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_starred_entities"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_starred_entities"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_profile_lists"("target_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_profile_lists"("target_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_profile_starred_entities"("target_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_profile_starred_entities"("target_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";



GRANT ALL ON FUNCTION "public"."hash_ltree"("public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."hash_ltree"("public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."hash_ltree"("public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hash_ltree"("public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."hash_ltree_extended"("public"."ltree", bigint) TO "postgres";
GRANT ALL ON FUNCTION "public"."hash_ltree_extended"("public"."ltree", bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."hash_ltree_extended"("public"."ltree", bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hash_ltree_extended"("public"."ltree", bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."index"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."index"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."index"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."index"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."index"("public"."ltree", "public"."ltree", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."index"("public"."ltree", "public"."ltree", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."index"("public"."ltree", "public"."ltree", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."index"("public"."ltree", "public"."ltree", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."lca"("public"."ltree"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lca"("public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."lt_q_regex"("public"."ltree", "public"."lquery"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."lt_q_regex"("public"."ltree", "public"."lquery"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."lt_q_regex"("public"."ltree", "public"."lquery"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."lt_q_regex"("public"."ltree", "public"."lquery"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."lt_q_rregex"("public"."lquery"[], "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."lt_q_rregex"("public"."lquery"[], "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."lt_q_rregex"("public"."lquery"[], "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lt_q_rregex"("public"."lquery"[], "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltq_regex"("public"."ltree", "public"."lquery") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltq_regex"("public"."ltree", "public"."lquery") TO "anon";
GRANT ALL ON FUNCTION "public"."ltq_regex"("public"."ltree", "public"."lquery") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltq_regex"("public"."ltree", "public"."lquery") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltq_rregex"("public"."lquery", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltq_rregex"("public"."lquery", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltq_rregex"("public"."lquery", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltq_rregex"("public"."lquery", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree2text"("public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree2text"("public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree2text"("public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree2text"("public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_addltree"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_addltree"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_addltree"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_addltree"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_addtext"("public"."ltree", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_addtext"("public"."ltree", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_addtext"("public"."ltree", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_addtext"("public"."ltree", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_cmp"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_cmp"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_cmp"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_cmp"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_consistent"("internal", "public"."ltree", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_consistent"("internal", "public"."ltree", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_consistent"("internal", "public"."ltree", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_consistent"("internal", "public"."ltree", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_eq"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_eq"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_eq"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_eq"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_ge"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_ge"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_ge"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_ge"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_gist_options"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_gist_options"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_gist_options"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_gist_options"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_gt"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_gt"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_gt"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_gt"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_isparent"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_isparent"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_isparent"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_isparent"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_le"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_le"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_le"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_le"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_lt"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_lt"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_lt"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_lt"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_ne"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_ne"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_ne"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_ne"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_risparent"("public"."ltree", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_risparent"("public"."ltree", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_risparent"("public"."ltree", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_risparent"("public"."ltree", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_same"("public"."ltree_gist", "public"."ltree_gist", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_same"("public"."ltree_gist", "public"."ltree_gist", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_same"("public"."ltree_gist", "public"."ltree_gist", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_same"("public"."ltree_gist", "public"."ltree_gist", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_textadd"("text", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_textadd"("text", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_textadd"("text", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_textadd"("text", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltree_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltree_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ltree_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltree_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltreeparentsel"("internal", "oid", "internal", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."ltreeparentsel"("internal", "oid", "internal", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."ltreeparentsel"("internal", "oid", "internal", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltreeparentsel"("internal", "oid", "internal", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."ltxtq_exec"("public"."ltree", "public"."ltxtquery") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltxtq_exec"("public"."ltree", "public"."ltxtquery") TO "anon";
GRANT ALL ON FUNCTION "public"."ltxtq_exec"("public"."ltree", "public"."ltxtquery") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltxtq_exec"("public"."ltree", "public"."ltxtquery") TO "service_role";



GRANT ALL ON FUNCTION "public"."ltxtq_rexec"("public"."ltxtquery", "public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."ltxtq_rexec"("public"."ltxtquery", "public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."ltxtq_rexec"("public"."ltxtquery", "public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ltxtq_rexec"("public"."ltxtquery", "public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."nlevel"("public"."ltree") TO "postgres";
GRANT ALL ON FUNCTION "public"."nlevel"("public"."ltree") TO "anon";
GRANT ALL ON FUNCTION "public"."nlevel"("public"."ltree") TO "authenticated";
GRANT ALL ON FUNCTION "public"."nlevel"("public"."ltree") TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";



GRANT ALL ON FUNCTION "public"."search_entities"("ref_lat" double precision, "ref_lng" double precision, "radius_miles" double precision, "category_path" "public"."ltree", "show_hidden" boolean, "recommended_only" boolean, "starred_only" boolean, "name_query" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."search_entities"("ref_lat" double precision, "ref_lng" double precision, "radius_miles" double precision, "category_path" "public"."ltree", "show_hidden" boolean, "recommended_only" boolean, "starred_only" boolean, "name_query" "text") TO "authenticated";



GRANT ALL ON FUNCTION "public"."subltree"("public"."ltree", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subltree"("public"."ltree", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subltree"("public"."ltree", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subltree"("public"."ltree", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."subpath"("public"."ltree", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subpath"("public"."ltree", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subpath"("public"."ltree", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subpath"("public"."ltree", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."subpath"("public"."ltree", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subpath"("public"."ltree", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subpath"("public"."ltree", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subpath"("public"."ltree", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."text2ltree"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."text2ltree"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."text2ltree"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."text2ltree"("text") TO "service_role";

















































































GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."categories" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."categories" TO "authenticated";
GRANT ALL ON TABLE "public"."categories" TO "service_role";



GRANT ALL ON TABLE "public"."entities" TO "service_role";



GRANT ALL ON TABLE "public"."entity_categories" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."friendships" TO "anon";
GRANT ALL ON TABLE "public"."friendships" TO "authenticated";
GRANT ALL ON TABLE "public"."friendships" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."hidden_entities" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."hidden_entities" TO "authenticated";
GRANT ALL ON TABLE "public"."hidden_entities" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."list_items" TO "anon";
GRANT ALL ON TABLE "public"."list_items" TO "authenticated";
GRANT ALL ON TABLE "public"."list_items" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."lists" TO "anon";
GRANT ALL ON TABLE "public"."lists" TO "authenticated";
GRANT ALL ON TABLE "public"."lists" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_addons" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_addons" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_addons" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_api_token_scopes" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_api_token_scopes" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_api_token_scopes" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_api_tokens" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_api_tokens" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_api_tokens" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_audit_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_audit_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_audit_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_automation_executions" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_automation_executions" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_automation_executions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_automation_subscribers" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_automation_subscribers" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_automation_subscribers" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_automations" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_automations" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_automations" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_base_users_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_base_users_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_base_users_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_base_variables" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_base_variables" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_base_variables" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_bases_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_bases_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_bases_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_bookmark_groups" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_bookmark_groups" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_bookmark_groups" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_bookmarks" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_bookmarks" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_bookmarks" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_calendar_view_columns_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_calendar_view_columns_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_calendar_view_columns_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_calendar_view_range_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_calendar_view_range_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_calendar_view_range_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_calendar_view_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_calendar_view_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_calendar_view_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_chat_messages" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_chat_messages" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_chat_messages" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_chat_sessions" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_chat_sessions" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_chat_sessions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_barcode_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_barcode_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_barcode_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_button_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_button_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_button_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_formula_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_formula_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_formula_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_long_text_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_long_text_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_long_text_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_lookup_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_lookup_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_lookup_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_qrcode_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_qrcode_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_qrcode_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_relations_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_relations_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_relations_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_rollup_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_rollup_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_rollup_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_select_options_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_select_options_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_col_select_options_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_columns_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_columns_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_columns_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_comment_reactions" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_comment_reactions" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_comment_reactions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_comments" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_comments" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_comments" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_custom_urls_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_custom_urls_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_custom_urls_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_dashboards_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_dashboards_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_dashboards_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_data_reflection" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_data_reflection" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_data_reflection" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_date_dependency_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_date_dependency_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_date_dependency_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_db_servers" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_db_servers" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_db_servers" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_dependency_tracker" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_dependency_tracker" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_dependency_tracker" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_disabled_models_for_role_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_disabled_models_for_role_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_disabled_models_for_role_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_doc_content_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_doc_content_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_doc_content_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_doc_revisions_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_doc_revisions_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_doc_revisions_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_docs_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_docs_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_docs_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_extensions" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_extensions" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_extensions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_file_references" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_file_references" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_file_references" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_filter_exp_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_filter_exp_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_filter_exp_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_follower" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_follower" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_follower" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_form_view_columns_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_form_view_columns_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_form_view_columns_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_form_view_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_form_view_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_form_view_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gallery_view_columns_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gallery_view_columns_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gallery_view_columns_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gallery_view_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gallery_view_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gallery_view_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gantt_view_columns_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gantt_view_columns_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gantt_view_columns_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gantt_view_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gantt_view_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gantt_view_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gcp_marketplace_accounts" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gcp_marketplace_accounts" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gcp_marketplace_accounts" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gcp_marketplace_entitlements" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gcp_marketplace_entitlements" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_gcp_marketplace_entitlements" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_grid_view_columns_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_grid_view_columns_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_grid_view_columns_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_grid_view_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_grid_view_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_grid_view_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_hook_logs_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_hook_logs_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_hook_logs_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_hook_trigger_fields" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_hook_trigger_fields" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_hook_trigger_fields" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_hooks_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_hooks_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_hooks_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_installations" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_installations" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_installations" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_integration_links_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_integration_links_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_integration_links_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_integrations_store_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_integrations_store_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_integrations_store_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_integrations_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_integrations_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_integrations_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_jobs" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_jobs" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_jobs" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_kanban_view_columns_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_kanban_view_columns_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_kanban_view_columns_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_kanban_view_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_kanban_view_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_kanban_view_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_list_view_columns_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_list_view_columns_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_list_view_columns_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_list_view_levels_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_list_view_levels_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_list_view_levels_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_list_view_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_list_view_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_list_view_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_mail_sends" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_mail_sends" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_mail_sends" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_managed_app_deployment_logs" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_managed_app_deployment_logs" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_managed_app_deployment_logs" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_managed_app_versions" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_managed_app_versions" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_managed_app_versions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_managed_apps" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_managed_apps" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_managed_apps" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_map_view_columns_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_map_view_columns_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_map_view_columns_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_map_view_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_map_view_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_map_view_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_mcp_tokens" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_mcp_tokens" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_mcp_tokens" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_model_stats_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_model_stats_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_model_stats_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_models_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_models_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_models_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_oauth_authorization_codes" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_oauth_authorization_codes" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_oauth_authorization_codes" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_oauth_clients" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_oauth_clients" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_oauth_clients" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_oauth_tokens" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_oauth_tokens" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_oauth_tokens" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_operation_logs" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_operation_logs" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_operation_logs" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_org" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_org" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_org" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_org_domain" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_org_domain" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_org_domain" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_org_users" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_org_users" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_org_users" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_permission_subjects" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_permission_subjects" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_permission_subjects" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_permissions" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_permissions" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_permissions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_plans" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_plans" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_plans" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_plugins_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_plugins_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_plugins_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_principal_assignments" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_principal_assignments" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_principal_assignments" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_record_templates" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_record_templates" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_record_templates" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_rls_policies" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_rls_policies" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_rls_policies" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_rls_policy_subjects" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_rls_policy_subjects" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_rls_policy_subjects" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_row_color_conditions" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_row_color_conditions" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_row_color_conditions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_ry6x___Features" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_ry6x___Features" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_ry6x___Features" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sandbox_changelog" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sandbox_changelog" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sandbox_changelog" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sandboxes_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sandboxes_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sandboxes_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_scim_config" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_scim_config" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_scim_config" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_scripts" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_scripts" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_scripts" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_snapshots" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_snapshots" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_snapshots" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sort_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sort_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sort_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sources_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sources_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sources_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sql_executor_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sql_executor_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sql_executor_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sso_client" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sso_client" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sso_client" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sso_client_domain" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sso_client_domain" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sso_client_domain" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_store" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_store" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_store" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_subscription_addons" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_subscription_addons" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_subscription_addons" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_subscriptions" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_subscriptions" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_subscriptions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_configs" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_configs" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_configs" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_logs_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_logs_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_logs_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_mappings" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_mappings" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_mappings" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_source_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_source_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_sync_source_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_table_sync_column_mappings" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_table_sync_column_mappings" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_table_sync_column_mappings" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_table_sync_mappings" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_table_sync_mappings" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_table_sync_mappings" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_table_syncs" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_table_syncs" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_table_syncs" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_teams" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_teams" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_teams" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_timeline_view_columns_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_timeline_view_columns_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_timeline_view_columns_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_timeline_view_range_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_timeline_view_range_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_timeline_view_range_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_timeline_view_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_timeline_view_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_timeline_view_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_trash" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_trash" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_trash" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_usage_stats" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_usage_stats" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_usage_stats" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_user_comment_notifications_preference" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_user_comment_notifications_preference" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_user_comment_notifications_preference" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_user_refresh_tokens" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_user_refresh_tokens" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_user_refresh_tokens" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_users_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_users_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_users_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_view_sections" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_view_sections" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_view_sections" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_views_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_views_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_views_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_widgets_v2" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_widgets_v2" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_widgets_v2" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_workflows" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_workflows" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."nc_workflows" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."notification" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."notification" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."notification" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."profiles" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."profiles" TO "anon";
GRANT SELECT("id") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("handle") ON TABLE "public"."profiles" TO "anon";
GRANT SELECT("handle") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("display_name") ON TABLE "public"."profiles" TO "anon";
GRANT SELECT("display_name") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."profiles" TO "anon";
GRANT SELECT("created_at") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("avatar_url") ON TABLE "public"."profiles" TO "anon";
GRANT SELECT("avatar_url") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("first_name") ON TABLE "public"."profiles" TO "anon";
GRANT SELECT("first_name") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("last_name") ON TABLE "public"."profiles" TO "anon";
GRANT SELECT("last_name") ON TABLE "public"."profiles" TO "authenticated";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."saved_lists" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."saved_lists" TO "authenticated";
GRANT ALL ON TABLE "public"."saved_lists" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."stars" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."stars" TO "authenticated";
GRANT ALL ON TABLE "public"."stars" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."workspace" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."workspace" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."workspace" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."workspace_user" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."workspace_user" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."workspace_user" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."xc_knex_migrationsv0" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."xc_knex_migrationsv0" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."xc_knex_migrationsv0" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."xc_knex_migrationsv0_lock" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."xc_knex_migrationsv0_lock" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."xc_knex_migrationsv0_lock" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "service_role";



































