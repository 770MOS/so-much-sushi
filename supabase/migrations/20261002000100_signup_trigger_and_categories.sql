-- What the schema dump could not capture, copied from production on 2026-10-02:
-- the sign-up trigger on auth.users and the category tree (same ids as production).
-- Already live in production: mark as applied there, never run it there.

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

INSERT INTO public.categories (id, parent_id, name, slug, path) VALUES
  ('cf5648c8-a0ae-45b9-a2ae-d8f1d7e1b2d1', NULL, 'Bars and nightlife', 'bars', 'bars'),
  ('f2fbe4e2-c2cd-4e19-b0fc-3fde493f53d5', NULL, 'Coffee and cafes', 'coffee', 'coffee'),
  ('c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', NULL, 'Restaurants', 'restaurants', 'restaurants'),
  ('fc86b041-a611-4a07-84a8-cb2935befae0', 'cf5648c8-a0ae-45b9-a2ae-d8f1d7e1b2d1', 'Bar', 'bar', 'bars.bar'),
  ('08e1e3e8-5723-404e-aca2-3e3265db0dd6', 'cf5648c8-a0ae-45b9-a2ae-d8f1d7e1b2d1', 'Brewery', 'brewery', 'bars.brewery'),
  ('3ab0c78e-8054-41e6-9762-c7c7893063cb', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'American', 'american', 'restaurants.american'),
  ('e4210e11-96f7-4ccf-8f5d-41698f773a0c', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Asian', 'asian', 'restaurants.asian'),
  ('d9878f7e-9a3a-4b41-a38e-300edf651d95', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Bakery and dessert', 'bakery', 'restaurants.bakery'),
  ('74ab18c1-2df8-4387-b06b-e7c857322675', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Deli', 'deli', 'restaurants.deli'),
  ('3d5821b6-603c-4fd0-af25-d5b86a74b6ec', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'French', 'french', 'restaurants.french'),
  ('6417c712-1e89-406e-8943-ecc5cb10bcff', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Indian', 'indian', 'restaurants.indian'),
  ('c3e399a5-d193-4922-a0a3-e9ee4e2b52a0', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Italian', 'italian', 'restaurants.italian'),
  ('b6106f78-ee59-4b74-b582-45a9dcd99ad7', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Mediterranean', 'mediterranean', 'restaurants.mediterranean'),
  ('a6ec9eac-936a-42ea-927a-0e946e50bd77', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Mexican', 'mexican', 'restaurants.mexican'),
  ('072abf57-3b37-4cf3-9406-2d05b38a0048', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Middle Eastern', 'middle_eastern', 'restaurants.middle_eastern'),
  ('f00df833-01e8-4d87-9657-2336a301d200', 'c68cbac2-5deb-4cd3-9c70-3bf6ddabe5a4', 'Seafood', 'seafood', 'restaurants.seafood'),
  ('4ff8c8d7-8522-489a-b2d3-4b4fda64146e', 'fc86b041-a611-4a07-84a8-cb2935befae0', 'Cocktail Bar', 'cocktail_bar', 'bars.bar.cocktail_bar'),
  ('2676f2cc-66a9-49c1-9354-67eaeb4e7a86', 'fc86b041-a611-4a07-84a8-cb2935befae0', 'Wine Bar', 'wine_bar', 'bars.bar.wine_bar'),
  ('c54357b7-54f5-4054-beb8-caa87b02ac31', 'e4210e11-96f7-4ccf-8f5d-41698f773a0c', 'Japanese', 'japanese', 'restaurants.asian.japanese'),
  ('7b23d016-ea67-4d08-b0f6-e3304da0d58d', 'e4210e11-96f7-4ccf-8f5d-41698f773a0c', 'Thai', 'thai', 'restaurants.asian.thai'),
  ('58291051-ac11-4832-b8b6-6149df8d9c7c', 'c3e399a5-d193-4922-a0a3-e9ee4e2b52a0', 'Pasta', 'pasta', 'restaurants.italian.pasta'),
  ('46efe22a-bd5a-46bd-834a-f6341e21c353', 'c3e399a5-d193-4922-a0a3-e9ee4e2b52a0', 'Pizza', 'pizza', 'restaurants.italian.pizza'),
  ('3c2db49d-be98-4968-88ff-9b71464db73a', 'b6106f78-ee59-4b74-b582-45a9dcd99ad7', 'Greek', 'greek', 'restaurants.mediterranean.greek'),
  ('9d524474-3444-482a-b530-8e1afe66f1b8', '072abf57-3b37-4cf3-9406-2d05b38a0048', 'Israeli', 'israeli', 'restaurants.middle_eastern.israeli'),
  ('760757db-8fb2-4f37-9bf4-e72edbd90324', '072abf57-3b37-4cf3-9406-2d05b38a0048', 'Lebanese', 'lebanese', 'restaurants.middle_eastern.lebanese'),
  ('327493b8-eaf6-49fc-b52d-59ed67376f95', '072abf57-3b37-4cf3-9406-2d05b38a0048', 'Turkish', 'turkish', 'restaurants.middle_eastern.turkish'),
  ('8fc96754-71ce-4443-a5f6-16c71774187d', 'c54357b7-54f5-4054-beb8-caa87b02ac31', 'Sushi', 'sushi', 'restaurants.asian.japanese.sushi')
ON CONFLICT (id) DO NOTHING;
