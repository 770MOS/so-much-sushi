-- The place panel and place page (build step 4, mocked 2026-11-10).
--
-- place_detail(place_id) gives everything the panel, the phone sheet and the full place page
-- show, in one call, as JSON:
--   id            the place shown: a merged place's survivor when the link was to the merged one
--                 (the page then moves the address to the survivor's link);
--   name, address (one line, as on the place page), street, city, state, postal_code;
--   phone, website, hours (text, when a source gave hours as text), status, lat, lng;
--   categories    [{name, path}], the main category first, then the finer kinds;
--   is_starred    one of the viewer's favorites;
--   is_want       on the viewer's ready-made Want to try list;
--   lists         the viewer's own other lists it's on, [{id, name}], A-Z;
--   friends       up to three friends who favorited it, earliest first, [{name, handle}],
--                 and friends_count, all of them (the panel names three, then "and N others");
--   sources       codes of the sources with a record for it ("Details from ..."), e.g.
--                 overture_places, alltheplaces, manual_research for places added by hand.
-- Null when there's no such place. A visitor gets the same place with no marks, lists or
-- friends. get_entity_detail stays for anything still calling it.
SET search_path = public, extensions;

CREATE FUNCTION public.place_detail(place_id uuid)
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
REVOKE ALL ON FUNCTION public.place_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_detail(uuid) TO anon, authenticated, service_role;
