-- Entity lifecycle: entities are never hard-deleted in normal operation.
--   status 'removed' = soft delete; status 'merged' = tombstone pointing at the survivor.
-- User data (stars, hides, list items) can no longer be destroyed by deleting an entity.

-- 1. Retire the OpenStreetMap-era provenance columns. Provenance moves to
--    source_records / entity_field_provenance (next migration). OSM is excluded as a source.
DROP INDEX IF EXISTS public.entities_osm_id_unique;
ALTER TABLE public.entities
  DROP CONSTRAINT IF EXISTS entities_source_code_check,
  DROP COLUMN IF EXISTS osm_id,
  DROP COLUMN IF EXISTS source_code,
  DROP COLUMN IF EXISTS source;

-- 2. Lifecycle columns.
ALTER TABLE public.entities
  ADD COLUMN postal_code  text,
  ADD COLUMN merged_into  uuid REFERENCES public.entities(id) ON DELETE RESTRICT,
  ADD COLUMN succeeded_by uuid REFERENCES public.entities(id) ON DELETE SET NULL,
  ADD COLUMN created_at   timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN updated_at   timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.entities
  DROP CONSTRAINT entities_status_check,
  ADD CONSTRAINT entities_status_check CHECK (status IN
    ('active', 'temporarily_closed', 'permanently_closed', 'merged', 'removed')),
  ADD CONSTRAINT entities_merged_into_check CHECK
    ((status = 'merged') = (merged_into IS NOT NULL) AND merged_into IS DISTINCT FROM id);

CREATE INDEX entities_merged_into_idx ON public.entities (merged_into) WHERE merged_into IS NOT NULL;

CREATE FUNCTION public.set_updated_at() RETURNS trigger
  LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC;

CREATE TRIGGER entities_set_updated_at BEFORE UPDATE ON public.entities
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 3. Deleting an entity that anyone has starred, hidden or listed is now refused
--    instead of silently deleting their data. (entity_categories stays CASCADE: entity data.)
ALTER TABLE public.stars
  DROP CONSTRAINT stars_entity_id_fkey,
  ADD CONSTRAINT stars_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entities(id) ON DELETE RESTRICT;
ALTER TABLE public.hidden_entities
  DROP CONSTRAINT hidden_entities_entity_id_fkey,
  ADD CONSTRAINT hidden_entities_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entities(id) ON DELETE RESTRICT;
ALTER TABLE public.list_items
  DROP CONSTRAINT list_items_entity_id_fkey,
  ADD CONSTRAINT list_items_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES public.entities(id) ON DELETE RESTRICT;

-- The merge procedure repoints these by entity_id; the primary keys lead with user/list.
CREATE INDEX stars_entity_id_idx           ON public.stars (entity_id);
CREATE INDEX hidden_entities_entity_id_idx ON public.hidden_entities (entity_id);
CREATE INDEX list_items_entity_id_idx      ON public.list_items (entity_id);

-- 4. Follow a tombstone chain (A merged into B, B merged into C) to the live entity.
CREATE FUNCTION public.resolve_entity(p_entity_id uuid) RETURNS uuid
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH RECURSIVE chain AS (
    SELECT e.id, e.merged_into, 0 AS depth FROM entities e WHERE e.id = p_entity_id
    UNION ALL
    SELECT e.id, e.merged_into, c.depth + 1
    FROM chain c JOIN entities e ON e.id = c.merged_into
    WHERE c.depth < 20
  )
  SELECT id FROM chain WHERE merged_into IS NULL LIMIT 1;
$$;
-- Venue pages are public, so old links must resolve for signed-out visitors too.
GRANT EXECUTE ON FUNCTION public.resolve_entity(uuid) TO anon, authenticated, service_role;

-- 5. Read functions honour the lifecycle. Signatures are unchanged.
--    Search never returns tombstones or removed entities.
CREATE OR REPLACE FUNCTION public.search_entities(
    ref_lat double precision, ref_lng double precision, radius_miles double precision,
    category_path public.ltree DEFAULT NULL, show_hidden boolean DEFAULT false,
    recommended_only boolean DEFAULT false, starred_only boolean DEFAULT false,
    name_query text DEFAULT NULL)
  RETURNS TABLE(id uuid, name text, address text, miles numeric, lat double precision, lng double precision,
                is_starred boolean, is_hidden boolean, recommended_by jsonb, recommended_count integer,
                status text, categories text[], category_paths text[])
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
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
      AND e.status NOT IN ('permanently_closed', 'merged', 'removed')
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

--    A venue link to a merged entity returns the survivor (its id is the survivor's id).
CREATE OR REPLACE FUNCTION public.get_entity_detail(p_entity_id uuid)
  RETURNS TABLE(id uuid, name text, address text, phone text, website text, hours jsonb, attributes jsonb,
                status text, lat double precision, lng double precision, is_starred boolean,
                categories text[], category_paths text[])
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
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
    WHERE e.id = resolve_entity(p_entity_id);
$$;
