-- Category model: every entity has exactly one required MAIN category (one of four roots);
-- subcategories (entity_categories) and attributes are optional detail added over time.
--
--   restaurants  Restaurants
--   drinks       Drinks (bars, breweries, wineries, distilleries)      [was: bars]
--   coffee       Coffee (coffee, tea, juice)
--   markets      Bakeries and Markets (bakeries, desserts, delis, specialty food shops)  [new]
--
-- Existing category ids are kept; only names and paths change.

SET search_path = public, extensions;

-- 1. Roots.
UPDATE public.categories SET slug = 'drinks', name = 'Drinks' WHERE slug = 'bars';
UPDATE public.categories SET name = 'Coffee' WHERE slug = 'coffee';
INSERT INTO public.categories (name, slug, path) VALUES ('Bakeries and Markets', 'markets', 'markets')
  ON CONFLICT (slug) DO NOTHING;
UPDATE public.categories SET name = 'Bakery' WHERE slug = 'bakery';

-- 2. Move branches: bars.* -> drinks.*, restaurants.bakery and restaurants.deli -> markets.*
UPDATE public.categories SET path = CASE WHEN nlevel(path) = 1 THEN 'drinks'::public.ltree
                                         ELSE 'drinks'::public.ltree || subpath(path, 1) END
  WHERE path <@ 'bars'::public.ltree;
UPDATE public.categories c SET parent_id = (SELECT id FROM public.categories WHERE slug = 'markets'),
                               path = ('markets.' || c.slug)::public.ltree
  WHERE c.slug IN ('bakery', 'deli');

-- 3. New subcategories, parents first. Parents are looked up by slug.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('fast_food', 'Fast Food', 'restaurants'), ('chicken', 'Chicken and Wings', 'restaurants'),
    ('barbecue', 'Barbecue', 'restaurants'), ('steakhouse', 'Steakhouse', 'restaurants'),
    ('breakfast_brunch', 'Breakfast and Brunch', 'restaurants'), ('salad', 'Salad', 'restaurants'),
    ('sandwiches', 'Sandwiches', 'restaurants'), ('food_truck', 'Food Truck or Stand', 'restaurants'),
    ('vegetarian_vegan', 'Vegetarian and Vegan', 'restaurants'), ('hawaiian', 'Hawaiian and Poke', 'restaurants'),
    ('spanish', 'Spanish and Tapas', 'restaurants'), ('european', 'Other European', 'restaurants'),
    ('latin_american', 'Latin American', 'restaurants'), ('african', 'African', 'restaurants'),
    ('burgers', 'Burgers', 'american'), ('southern', 'Southern and Soul Food', 'american'),
    ('cajun_creole', 'Cajun and Creole', 'american'), ('diner', 'Diner', 'american'),
    ('bar_and_grill', 'Bar and Grill', 'american'),
    ('chinese', 'Chinese', 'asian'), ('korean', 'Korean', 'asian'), ('vietnamese', 'Vietnamese', 'asian'),
    ('filipino', 'Filipino', 'asian'), ('asian_fusion', 'Asian Fusion', 'asian'), ('afghan', 'Afghan', 'asian'),
    ('pakistani', 'Pakistani', 'asian'), ('ramen', 'Ramen', 'japanese'),
    ('salvadoran', 'Salvadoran', 'latin_american'), ('peruvian', 'Peruvian', 'latin_american'),
    ('caribbean', 'Caribbean', 'latin_american'), ('brazilian', 'Brazilian', 'latin_american'),
    ('tacos', 'Tacos', 'mexican'), ('tex_mex', 'Tex-Mex', 'mexican'),
    ('ethiopian', 'Ethiopian', 'african'), ('persian', 'Persian', 'middle_eastern'),
    ('sports_bar', 'Sports Bar', 'bar'), ('pub', 'Pub', 'bar'), ('beer_bar', 'Beer Bar and Beer Garden', 'bar'),
    ('lounge', 'Lounge', 'bar'), ('hookah_bar', 'Hookah Bar', 'bar'), ('gay_bar', 'Gay Bar', 'bar'),
    ('distillery', 'Distillery', 'drinks'), ('winery', 'Winery', 'drinks'),
    ('tea', 'Tea', 'coffee'), ('bubble_tea', 'Bubble Tea', 'coffee'), ('juice_smoothies', 'Juice and Smoothies', 'coffee'),
    ('bagels', 'Bagels', 'bakery'),
    ('desserts', 'Desserts', 'markets'), ('ice_cream', 'Ice Cream and Frozen Desserts', 'desserts'),
    ('donuts', 'Donuts', 'desserts'), ('candy_chocolate', 'Candy and Chocolate', 'desserts'),
    ('butcher', 'Butcher', 'markets'), ('cheese_shop', 'Cheese Shop', 'markets'),
    ('seafood_market', 'Seafood Market', 'markets'), ('specialty_grocery', 'Specialty Grocery', 'markets'),
    ('farmers_market', 'Farmers Market', 'markets'), ('wine_liquor', 'Wine and Liquor Shop', 'markets')
  ) AS t(slug, name, parent_slug)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.categories WHERE slug = r.parent_slug) THEN
      RAISE EXCEPTION 'parent % not found for %', r.parent_slug, r.slug;
    END IF;
    INSERT INTO public.categories (parent_id, name, slug, path)
    SELECT p.id, r.name, r.slug, (p.path::text || '.' || r.slug)::public.ltree
    FROM public.categories p WHERE p.slug = r.parent_slug
    ON CONFLICT (slug) DO NOTHING;
  END LOOP;
END $$;

-- 4. The required main category. Existing rows (none in the sandbox) are backfilled from the
--    root of a category they already carry; a row with no category at all blocks the migration.
ALTER TABLE public.entities ADD COLUMN main_category_id uuid REFERENCES public.categories(id);
UPDATE public.entities e SET main_category_id = (
  SELECT root.id FROM public.entity_categories ec
  JOIN public.categories c ON c.id = ec.category_id
  JOIN public.categories root ON root.path = subpath(c.path, 0, 1)
  WHERE ec.entity_id = e.id ORDER BY nlevel(c.path) DESC LIMIT 1);
ALTER TABLE public.entities ALTER COLUMN main_category_id SET NOT NULL;
CREATE INDEX entities_main_category_idx ON public.entities (main_category_id);

CREATE FUNCTION public.check_main_category() RETURNS trigger
  LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.categories c WHERE c.id = NEW.main_category_id AND public.nlevel(c.path) = 1) THEN
    RAISE EXCEPTION 'main_category_id must be one of the top-level categories' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.check_main_category() FROM PUBLIC;
CREATE TRIGGER entities_check_main_category BEFORE INSERT OR UPDATE OF main_category_id ON public.entities
  FOR EACH ROW EXECUTE FUNCTION public.check_main_category();

-- 5. Attributes: flat, optional facts that cut across categories (Halal, Bring your own food).
CREATE TABLE public.attributes (
  id        smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug      text NOT NULL UNIQUE,
  name      text NOT NULL,
  grouping  text NOT NULL CHECK (grouping IN ('dietary', 'policy', 'setting'))
);
CREATE TABLE public.entity_attributes (
  entity_id    uuid NOT NULL REFERENCES public.entities(id) ON DELETE CASCADE,
  attribute_id smallint NOT NULL REFERENCES public.attributes(id),
  source_id    smallint NOT NULL REFERENCES public.sources(id),
  license      text NOT NULL,
  method       text NOT NULL CHECK (method IN ('survivorship', 'manual', 'user_report')),
  set_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (entity_id, attribute_id)
);
CREATE TRIGGER entity_attributes_check_source BEFORE INSERT OR UPDATE ON public.entity_attributes
  FOR EACH ROW EXECUTE FUNCTION public.check_provenance_source();
ALTER TABLE public.attributes        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entity_attributes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.attributes, public.entity_attributes FROM anon, authenticated;
GRANT ALL ON public.attributes, public.entity_attributes TO service_role;
INSERT INTO public.attributes (slug, name, grouping) VALUES
  ('halal', 'Halal', 'dietary'), ('kosher', 'Kosher', 'dietary'),
  ('gluten_free_options', 'Gluten-free options', 'dietary'), ('vegan_options', 'Vegan options', 'dietary'),
  ('vegetarian_options', 'Vegetarian options', 'dietary'),
  ('byo_food', 'Bring your own food', 'policy'), ('byob', 'BYOB', 'policy'), ('cash_only', 'Cash only', 'policy'),
  ('outdoor_seating', 'Outdoor seating', 'setting');

-- 6. Read functions use the main category, so an entity with no subcategory is still found.
--    Signatures are unchanged. categories / category_paths list the main category first.
CREATE OR REPLACE FUNCTION public.search_entities(
    ref_lat double precision, ref_lng double precision, radius_miles double precision,
    category_path public.ltree DEFAULT NULL, show_hidden boolean DEFAULT false,
    recommended_only boolean DEFAULT false, starred_only boolean DEFAULT false,
    name_query text DEFAULT NULL)
  RETURNS TABLE(id uuid, name text, address text, miles numeric, lat double precision, lng double precision,
                is_starred boolean, is_hidden boolean, recommended_by jsonb, recommended_count integer,
                status text, categories text[], category_paths text[])
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
    SELECT
        e.id, e.name, e.address,
        round((ST_Distance(
            e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography
        ) / 1609.34)::numeric, 2) AS miles,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        EXISTS (SELECT 1 FROM stars s WHERE s.entity_id = e.id AND s.user_id = auth.uid()) AS is_starred,
        EXISTS (SELECT 1 FROM hidden_entities h WHERE h.entity_id = e.id AND h.user_id = auth.uid()) AS is_hidden,
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
        ARRAY[mc.name] || COALESCE((
            SELECT array_agg(cat.name ORDER BY cat.path)
            FROM entity_categories ec2 JOIN categories cat ON cat.id = ec2.category_id
            WHERE ec2.entity_id = e.id AND cat.id <> mc.id), '{}') AS categories,
        ARRAY[mc.path::text] || COALESCE((
            SELECT array_agg(cat3.path::text ORDER BY cat3.path)
            FROM entity_categories ec3 JOIN categories cat3 ON cat3.id = ec3.category_id
            WHERE ec3.entity_id = e.id AND cat3.id <> mc.id), '{}') AS category_paths
    FROM entities e
    JOIN categories mc ON mc.id = e.main_category_id
    WHERE (category_path IS NULL
           OR mc.path <@ category_path
           OR EXISTS (SELECT 1 FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
                      WHERE ec.entity_id = e.id AND c.path <@ category_path))
      AND e.status NOT IN ('permanently_closed', 'merged', 'removed')
      AND ST_DWithin(
          e.location, ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography,
          radius_miles * 1609.34
      )
      AND (show_hidden OR NOT EXISTS (
              SELECT 1 FROM hidden_entities h2 WHERE h2.entity_id = e.id AND h2.user_id = auth.uid()))
      AND (NOT recommended_only OR EXISTS (
              SELECT 1 FROM stars fs3
              JOIN friendships f3 ON (
                  (f3.requester_id = auth.uid() AND f3.addressee_id = fs3.user_id)
                  OR (f3.addressee_id = auth.uid() AND f3.requester_id = fs3.user_id)
              )
              WHERE fs3.entity_id = e.id AND f3.status = 'accepted'))
      AND (NOT starred_only OR EXISTS (
              SELECT 1 FROM stars s4 WHERE s4.entity_id = e.id AND s4.user_id = auth.uid()))
      AND (name_query IS NULL OR trim(name_query) = '' OR e.name ILIKE '%' || trim(name_query) || '%')
    ORDER BY miles;
$$;

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
        EXISTS (SELECT 1 FROM stars s WHERE s.entity_id = e.id AND s.user_id = auth.uid()) AS is_starred,
        ARRAY[mc.name] || COALESCE((
            SELECT array_agg(cat.name ORDER BY cat.path)
            FROM entity_categories ec JOIN categories cat ON cat.id = ec.category_id
            WHERE ec.entity_id = e.id AND cat.id <> mc.id), '{}') AS categories,
        ARRAY[mc.path::text] || COALESCE((
            SELECT array_agg(cat2.path::text ORDER BY cat2.path)
            FROM entity_categories ec2 JOIN categories cat2 ON cat2.id = ec2.category_id
            WHERE ec2.entity_id = e.id AND cat2.id <> mc.id), '{}') AS category_paths
    FROM entities e
    JOIN categories mc ON mc.id = e.main_category_id
    WHERE e.id = resolve_entity(p_entity_id);
$$;

-- type_name is the main category; cuisine_name is the most specific subcategory, if any.
CREATE OR REPLACE FUNCTION public.get_my_starred_entities()
  RETURNS TABLE(id uuid, name text, address text, city text, state text, lat double precision, lng double precision,
                type_name text, cuisine_name text, recommended_by jsonb, recommended_count integer, category_paths text[])
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
    SELECT
        e.id, e.name, e.address, e.city, e.state,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        mc.name AS type_name,
        COALESCE(sub.name, mc.name) AS cuisine_name,
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
        ARRAY[mc.path::text] || COALESCE((
            SELECT array_agg(cat2.path::text ORDER BY cat2.path)
            FROM entity_categories ec2 JOIN categories cat2 ON cat2.id = ec2.category_id
            WHERE ec2.entity_id = e.id AND cat2.id <> mc.id), '{}') AS category_paths
    FROM stars s
    JOIN entities e    ON e.id = s.entity_id
    JOIN categories mc ON mc.id = e.main_category_id
    LEFT JOIN LATERAL (
        SELECT c.name FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
        WHERE ec.entity_id = e.id AND c.id <> mc.id ORDER BY nlevel(c.path) DESC, c.path LIMIT 1) sub ON true
    WHERE s.user_id = auth.uid()
    ORDER BY e.name;
$$;

CREATE OR REPLACE FUNCTION public.get_profile_starred_entities(target_user_id uuid)
  RETURNS TABLE(id uuid, name text, address text, city text, state text, lat double precision, lng double precision,
                type_name text, cuisine_name text, status text)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
    SELECT
        e.id, e.name, e.address, e.city, e.state,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        mc.name AS type_name,
        COALESCE(sub.name, mc.name) AS cuisine_name,
        e.status
    FROM stars s
    JOIN entities e    ON e.id = s.entity_id
    JOIN categories mc ON mc.id = e.main_category_id
    LEFT JOIN LATERAL (
        SELECT c.name FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
        WHERE ec.entity_id = e.id AND c.id <> mc.id ORDER BY nlevel(c.path) DESC, c.path LIMIT 1) sub ON true
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
