-- App schema baseline: production as of 2026-10-02 (derived from supabase/baseline.sql).
-- NocoDB's own tables (nc_*, xc_*, workspace, workspace_user, notification) are left out.
-- Already live in production: mark as applied there, never run it there.


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

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "extensions";

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

ALTER TABLE ONLY "public"."list_items"
    ADD CONSTRAINT "list_items_pkey" PRIMARY KEY ("list_id", "entity_id");

ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "lists_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_handle_key" UNIQUE ("handle");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."saved_lists"
    ADD CONSTRAINT "saved_lists_pkey" PRIMARY KEY ("user_id", "list_id");

ALTER TABLE ONLY "public"."stars"
    ADD CONSTRAINT "stars_pkey" PRIMARY KEY ("user_id", "entity_id");

CREATE INDEX "categories_path_idx" ON "public"."categories" USING "gist" ("path");

CREATE INDEX "entities_location_idx" ON "public"."entities" USING "gist" ("location");

CREATE UNIQUE INDEX "entities_osm_id_unique" ON "public"."entities" USING "btree" ("osm_id") WHERE ("osm_id" IS NOT NULL);

CREATE UNIQUE INDEX "lists_one_default_per_owner" ON "public"."lists" USING "btree" ("owner_id") WHERE "is_default_list";

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

ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."saved_lists" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."stars" ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA "public" TO "postgres";

GRANT USAGE ON SCHEMA "public" TO "anon";

GRANT USAGE ON SCHEMA "public" TO "authenticated";

GRANT USAGE ON SCHEMA "public" TO "service_role";

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

GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";

GRANT ALL ON FUNCTION "public"."search_entities"("ref_lat" double precision, "ref_lng" double precision, "radius_miles" double precision, "category_path" "public"."ltree", "show_hidden" boolean, "recommended_only" boolean, "starred_only" boolean, "name_query" "text") TO "anon";

GRANT ALL ON FUNCTION "public"."search_entities"("ref_lat" double precision, "ref_lng" double precision, "radius_miles" double precision, "category_path" "public"."ltree", "show_hidden" boolean, "recommended_only" boolean, "starred_only" boolean, "name_query" "text") TO "authenticated";

-- Start from zero so the result matches production whatever this project's default grants are.
REVOKE ALL ON TABLE "public"."categories" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON TABLE "public"."entities" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON TABLE "public"."entity_categories" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON TABLE "public"."friendships" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON TABLE "public"."hidden_entities" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON TABLE "public"."list_items" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON TABLE "public"."lists" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON TABLE "public"."profiles" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON TABLE "public"."saved_lists" FROM "anon", "authenticated", "service_role";
REVOKE ALL ON TABLE "public"."stars" FROM "anon", "authenticated", "service_role";

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
