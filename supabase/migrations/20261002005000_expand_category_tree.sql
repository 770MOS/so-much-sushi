-- Expands the category tree for national coverage, based on what Overture Places actually
-- contains for the DC area. Additive only: no existing node is moved, renamed or removed,
-- so the app's type buttons (restaurants, bars, coffee, restaurants.bakery, bars.brewery)
-- are unaffected. Parents are looked up by slug, and rows are inserted parents-first.

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
  ('fast_food', 'Fast Food', 'restaurants'),
  ('chicken', 'Chicken and Wings', 'restaurants'),
  ('barbecue', 'Barbecue', 'restaurants'),
  ('steakhouse', 'Steakhouse', 'restaurants'),
  ('breakfast_brunch', 'Breakfast and Brunch', 'restaurants'),
  ('salad', 'Salad', 'restaurants'),
  ('sandwiches', 'Sandwiches', 'restaurants'),
  ('food_truck', 'Food Truck or Stand', 'restaurants'),
  ('vegetarian_vegan', 'Vegetarian and Vegan', 'restaurants'),
  ('hawaiian', 'Hawaiian and Poke', 'restaurants'),
  ('spanish', 'Spanish and Tapas', 'restaurants'),
  ('european', 'Other European', 'restaurants'),
  ('latin_american', 'Latin American', 'restaurants'),
  ('african', 'African', 'restaurants'),
  ('burgers', 'Burgers', 'american'),
  ('southern', 'Southern and Soul Food', 'american'),
  ('cajun_creole', 'Cajun and Creole', 'american'),
  ('diner', 'Diner', 'american'),
  ('bar_and_grill', 'Bar and Grill', 'american'),
  ('chinese', 'Chinese', 'asian'),
  ('korean', 'Korean', 'asian'),
  ('vietnamese', 'Vietnamese', 'asian'),
  ('filipino', 'Filipino', 'asian'),
  ('asian_fusion', 'Asian Fusion', 'asian'),
  ('afghan', 'Afghan', 'asian'),
  ('pakistani', 'Pakistani', 'asian'),
  ('ramen', 'Ramen', 'japanese'),
  ('salvadoran', 'Salvadoran', 'latin_american'),
  ('peruvian', 'Peruvian', 'latin_american'),
  ('caribbean', 'Caribbean', 'latin_american'),
  ('brazilian', 'Brazilian', 'latin_american'),
  ('tacos', 'Tacos', 'mexican'),
  ('tex_mex', 'Tex-Mex', 'mexican'),
  ('ethiopian', 'Ethiopian', 'african'),
  ('persian', 'Persian', 'middle_eastern'),
  ('ice_cream', 'Ice Cream and Frozen Desserts', 'bakery'),
  ('donuts', 'Donuts', 'bakery'),
  ('desserts', 'Desserts', 'bakery'),
  ('candy_chocolate', 'Candy and Chocolate', 'bakery'),
  ('bagels', 'Bagels', 'bakery'),
  ('sports_bar', 'Sports Bar', 'bar'),
  ('pub', 'Pub', 'bar'),
  ('beer_bar', 'Beer Bar and Beer Garden', 'bar'),
  ('lounge', 'Lounge', 'bar'),
  ('hookah_bar', 'Hookah Bar', 'bar'),
  ('gay_bar', 'Gay Bar', 'bar'),
  ('distillery', 'Distillery', 'bars'),
  ('winery', 'Winery', 'bars'),
  ('tea', 'Tea', 'coffee'),
  ('bubble_tea', 'Bubble Tea', 'coffee'),
  ('juice_smoothies', 'Juice and Smoothies', 'coffee')
  ) AS t(slug, name, parent_slug)
  LOOP
    INSERT INTO public.categories (parent_id, name, slug, path)
    SELECT p.id, r.name, r.slug, (p.path::text || '.' || r.slug)::public.ltree
    FROM public.categories p WHERE p.slug = r.parent_slug
    ON CONFLICT (slug) DO NOTHING;
    IF NOT FOUND AND NOT EXISTS (SELECT 1 FROM public.categories WHERE slug = r.slug) THEN
      RAISE EXCEPTION 'parent % not found for %', r.parent_slug, r.slug;
    END IF;
  END LOOP;
END $$;
