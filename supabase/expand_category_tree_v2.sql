-- Expands the category tree: adds American, French, Indian, Deli, Seafood,
-- Mediterranean (+ Greek), Middle Eastern (+ Israeli, Lebanese, Turkish), and
-- Cocktail Bar / Wine Bar (as children of Bar); reparents Sushi under a new
-- Japanese node (previously a direct child of Asian).
--
-- The prior tree was too coarse for the type/cuisine search filter - only
-- Asian/Italian/Mexican/Bakery existed under Restaurants, and there was no
-- way to distinguish a plain Bar from a Cocktail Bar/Wine Bar, or Sushi from
-- other Japanese food.
--
-- This was applied directly against the live database via the Supabase SQL
-- Editor before being committed here - this file is the first tracked
-- record of it. IDs below match the live rows exactly, so it's safe/
-- idempotent to replay against the current database or a fresh one.

-- New top-level restaurant cuisines
INSERT INTO categories (id, parent_id, name, slug, path) VALUES
  ('3ab0c78e-8054-41e6-9762-c7c7893063cb', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'American', 'american', 'restaurants.american'),
  ('3d5821b6-603c-4fd0-af25-d5b86a74b6ec', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'French', 'french', 'restaurants.french'),
  ('6417c712-1e89-406e-8943-ecc5cb10bcff', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Indian', 'indian', 'restaurants.indian'),
  ('74ab18c1-2df8-4387-b06b-e7c857322675', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Deli', 'deli', 'restaurants.deli'),
  ('f00df833-01e8-4d87-9657-2336a301d200', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Seafood', 'seafood', 'restaurants.seafood'),
  ('b6106f78-ee59-4b74-b582-45a9dcd99ad7', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Mediterranean', 'mediterranean', 'restaurants.mediterranean'),
  ('072abf57-3b37-4cf3-9406-2d05b38a0048', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Middle Eastern', 'middle_eastern', 'restaurants.middle_eastern')
ON CONFLICT (id) DO NOTHING;

-- Children of the new Mediterranean / Middle Eastern nodes
INSERT INTO categories (id, parent_id, name, slug, path) VALUES
  ('3c2db49d-be98-4968-88ff-9b71464db73a', 'b6106f78-ee59-4b74-b582-45a9dcd99ad7', 'Greek', 'greek', 'restaurants.mediterranean.greek'),
  ('9d524474-3444-482a-b530-8e1afe66f1b8', '072abf57-3b37-4cf3-9406-2d05b38a0048', 'Israeli', 'israeli', 'restaurants.middle_eastern.israeli'),
  ('760757db-8fb2-4f37-9bf4-e72edbd90324', '072abf57-3b37-4cf3-9406-2d05b38a0048', 'Lebanese', 'lebanese', 'restaurants.middle_eastern.lebanese'),
  ('327493b8-eaf6-49fc-b52d-59ed67376f95', '072abf57-3b37-4cf3-9406-2d05b38a0048', 'Turkish', 'turkish', 'restaurants.middle_eastern.turkish')
ON CONFLICT (id) DO NOTHING;

-- Japanese, as the new parent of Sushi (previously a direct child of Asian)
INSERT INTO categories (id, parent_id, name, slug, path) VALUES
  ('c54357b7-54f5-4054-beb8-caa87b02ac31', 'e4210e11-96f7-4ccf-8f5d-41698f773a0c', 'Japanese', 'japanese', 'restaurants.asian.japanese')
ON CONFLICT (id) DO NOTHING;

-- Reparent Sushi under Japanese
UPDATE categories
SET parent_id = 'c54357b7-54f5-4054-beb8-caa87b02ac31',
    path = 'restaurants.asian.japanese.sushi'
WHERE id = '8fc96754-71ce-4443-a5f6-16c71774187d';

-- Cocktail Bar / Wine Bar, as children of Bar
INSERT INTO categories (id, parent_id, name, slug, path) VALUES
  ('4ff8c8d7-8522-489a-b2d3-4b4fda64146e', 'fc86b041-a611-4a07-84a8-cb2935befae0', 'Cocktail Bar', 'cocktail_bar', 'bars.bar.cocktail_bar'),
  ('2676f2cc-66a9-49c1-9354-67eaeb4e7a86', 'fc86b041-a611-4a07-84a8-cb2935befae0', 'Wine Bar', 'wine_bar', 'bars.bar.wine_bar')
ON CONFLICT (id) DO NOTHING;

NOTIFY pgrst, 'reload schema';
