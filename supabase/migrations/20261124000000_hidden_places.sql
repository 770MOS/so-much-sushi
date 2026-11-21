-- The Hidden places page (decided 2026-11-21, Johnny): one place to see every place you hid,
-- anywhere, so a place hidden by mistake can be found and shown again. Until now hidden places
-- could only be found from a search that happened to cover them.
--
-- * my_hidden()     every place the viewer hid, for the Hidden places page.
-- * place_detail()  also says whether the viewer hid the place (is_hidden), so a place's own
--                   page and panel can say so and offer to show it again: someone may send you
--                   a link to a place you hid (decided 2026-11-21, Johnny).
--
-- Nothing else changes: hiding and showing again are still rows in hidden_entities, written
-- by the person themself (its policies are in the baseline).

-- ---------------------------------------------------------------- my_hidden
-- Every place the viewer hid, with when (added_at), A-Z. The same rows as my_favorites. Places
-- that have since been merged into another or removed are left out: they are in no search
-- either. Nothing for a visitor.
CREATE FUNCTION public.my_hidden()
  RETURNS TABLE(id uuid, name text, address text, street text, city text, state text,
                lat double precision, lng double precision, status text,
                categories text[], category_paths text[], recommended_by jsonb, recommended_count integer,
                is_starred boolean, is_want boolean, added_at timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH v AS (SELECT auth.uid() AS uid),
  mine AS (SELECT h.entity_id, h.created_at FROM hidden_entities h JOIN v ON h.user_id = v.uid)
  SELECT p.*, m.created_at AS added_at
  FROM v
  CROSS JOIN LATERAL public.places_for_viewer(v.uid, ARRAY(SELECT entity_id FROM mine)) p
  JOIN mine m ON m.entity_id = p.id
  WHERE p.status NOT IN ('merged', 'removed')
  ORDER BY lower(p.name), p.id;
$$;
REVOKE ALL ON FUNCTION public.my_hidden() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_hidden() TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- place_detail
-- As in 20261113000000_place_panel.sql, with one more key:
--   is_hidden     the viewer hid this place (always false for a visitor).
-- Same arguments, so this replaces it in place and its grants stay as they are.
CREATE OR REPLACE FUNCTION public.place_detail(place_id uuid)
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH v AS (SELECT auth.uid() AS uid, public.resolve_entity(place_id) AS id),
  my_friends AS (
    SELECT DISTINCT CASE WHEN f.requester_id = v.uid THEN f.addressee_id ELSE f.requester_id END AS friend_id
    FROM friendships f CROSS JOIN v
    WHERE v.uid IS NOT NULL AND f.status = 'accepted'
      AND (f.requester_id = v.uid OR f.addressee_id = v.uid)
  ),
  fans AS (
    SELECT COALESCE(p.display_name, p.handle) AS name, p.handle, fs.created_at
    FROM stars fs
    JOIN my_friends mf ON mf.friend_id = fs.user_id
    JOIN profiles p ON p.id = fs.user_id
    CROSS JOIN v
    WHERE fs.entity_id = v.id
  )
  SELECT jsonb_build_object(
    'id', e.id,
    'name', e.name,
    'address', display_address(e.address, e.city, e.state, e.postal_code),
    'street', NULLIF(trim(e.address), ''),
    'city', NULLIF(trim(e.city), ''),
    'state', NULLIF(trim(e.state), ''),
    'postal_code', NULLIF(trim(e.postal_code), ''),
    'phone', NULLIF(trim(e.phone), ''),
    'website', NULLIF(trim(e.website), ''),
    'hours', CASE WHEN jsonb_typeof(e.hours) = 'string' THEN NULLIF(trim(e.hours #>> '{}'), '')
                  ELSE NULLIF(trim(e.attributes ->> 'opening_hours'), '') END,
    'status', e.status,
    'lat', ST_Y(e.location::geometry),
    'lng', ST_X(e.location::geometry),
    'categories', jsonb_build_array(jsonb_build_object('name', mc.name, 'path', mc.path::text))
                  || COALESCE((SELECT jsonb_agg(jsonb_build_object('name', c.name, 'path', c.path::text) ORDER BY c.path)
                               FROM entity_categories ec JOIN categories c ON c.id = ec.category_id
                               WHERE ec.entity_id = e.id AND c.id <> mc.id), '[]'::jsonb),
    'is_starred', v.uid IS NOT NULL AND EXISTS (
                    SELECT 1 FROM stars s WHERE s.user_id = v.uid AND s.entity_id = e.id),
    'is_want', v.uid IS NOT NULL AND EXISTS (
                 SELECT 1 FROM list_items li JOIN lists l ON l.id = li.list_id
                 WHERE l.owner_id = v.uid AND l.is_default_list AND li.entity_id = e.id),
    'is_hidden', v.uid IS NOT NULL AND EXISTS (
                   SELECT 1 FROM hidden_entities h WHERE h.user_id = v.uid AND h.entity_id = e.id),
    'lists', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name) ORDER BY lower(l.name))
                       FROM lists l JOIN list_items li ON li.list_id = l.id
                       WHERE v.uid IS NOT NULL AND l.owner_id = v.uid AND NOT l.is_default_list
                         AND li.entity_id = e.id), '[]'::jsonb),
    'friends', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', t.name, 'handle', t.handle) ORDER BY t.created_at)
                         FROM (SELECT * FROM fans ORDER BY created_at LIMIT 3) t), '[]'::jsonb),
    'friends_count', (SELECT count(*)::integer FROM fans),
    'sources', COALESCE((SELECT jsonb_agg(DISTINCT s.code)
                         FROM source_records sr JOIN sources s ON s.id = sr.source_id
                         WHERE sr.entity_id = e.id), '[]'::jsonb)
  )
  FROM v
  JOIN entities e ON e.id = v.id
  JOIN categories mc ON mc.id = e.main_category_id;
$$;
