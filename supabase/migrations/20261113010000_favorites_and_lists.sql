-- Favorites, Lists and one list (build step 5, mocked and approved 2026-11-12).
--
-- * Want to try is ready-made: every account has one (created with the account, and added now
--   for accounts that don't have it yet). It starts as Just you, can't be deleted or renamed,
--   and its visibility can change like any list. (Before this it was made on first use by the
--   old Want to go button, which step 4 replaced, so newer accounts had none.)
-- * Who can see a list (decided 2026-11-12): 'private' = Just you, 'friends' = Friends,
--   'public' = anyone, signed in or not, by link or through search engines. Stored values are
--   unchanged; the existing row rules already let visitors read public lists.
-- * my_favorites()            every place the viewer favorited, for the Favorites page.
-- * list_page(list_id)        one list with its places, for the list page; visitors get public
--                             lists. {id, hidden: true} when the list exists but isn't shared
--                             with the viewer; null when there's no such list.
-- * lists_overview(lat, lng)  the viewer's own lists and the lists friends share with them,
--                             with place counts, towns, the closest place and a few points for
--                             each card's small map.
-- Place rows carry the same fields as search results, so pages show them the same way.
SET search_path = public, extensions;

-- ---------------------------------------------------------------- names
-- How a person's name shows (decided 2026-11-12): friends see the full name; anyone else
-- sees first name and last initial ("Priya S."). Account settings (step 6) will let people
-- choose the full name for public lists too.
CREATE FUNCTION public.person_name(
    first_name text, last_name text, display_name text, handle text, full_name boolean)
  RETURNS text
  LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  WITH n AS (
    SELECT NULLIF(trim(first_name), '') AS f, NULLIF(trim(last_name), '') AS l,
           NULLIF(trim(display_name), '') AS d, NULLIF(trim(handle), '') AS h
  )
  SELECT CASE
    WHEN full_name THEN COALESCE(n.d, CASE WHEN n.f IS NOT NULL AND n.l IS NOT NULL THEN n.f || ' ' || n.l END,
                                 n.f, n.h, 'Someone')
    WHEN n.f IS NOT NULL AND n.l IS NOT NULL THEN n.f || ' ' || upper(left(n.l, 1)) || '.'
    WHEN n.d ~ '\s' THEN split_part(n.d, ' ', 1) || ' ' || upper(left(regexp_replace(n.d, '^.*\s', ''), 1)) || '.'
    ELSE COALESCE(n.d, n.f, n.h, 'Someone')
  END
  FROM n;
$$;
REVOKE ALL ON FUNCTION public.person_name(text, text, text, text, boolean) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- Want to try for everyone
CREATE FUNCTION public.create_want_list()
  RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO lists (owner_id, name, visibility, is_default_list)
  VALUES (NEW.id, 'Want to try', 'private', true)
  ON CONFLICT (owner_id) WHERE is_default_list DO NOTHING;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.create_want_list() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER profiles_want_list AFTER INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.create_want_list();

INSERT INTO lists (owner_id, name, visibility, is_default_list)
SELECT p.id, 'Want to try', 'private', true
FROM profiles p
WHERE NOT EXISTS (SELECT 1 FROM lists l WHERE l.owner_id = p.id AND l.is_default_list);

-- Want to try stays: not deleted (the two older delete rules become one that leaves it out;
-- deleting an account still removes it), not renamed, and no other list becomes it.
DROP POLICY IF EXISTS "Delete your own lists" ON public.lists;
DROP POLICY IF EXISTS "Users can delete their own lists" ON public.lists;
CREATE POLICY "Delete your own lists except Want to try" ON public.lists FOR DELETE TO authenticated
  USING (owner_id = auth.uid() AND NOT is_default_list);

CREATE FUNCTION public.lists_keep_want_to_try()
  RETURNS trigger
  LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.is_default_list IS DISTINCT FROM OLD.is_default_list THEN
    RAISE EXCEPTION 'Want to try is the ready-made list; no other list can take its place'
      USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.is_default_list AND NEW.name IS DISTINCT FROM OLD.name THEN
    RAISE EXCEPTION 'Want to try can''t be renamed' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.lists_keep_want_to_try() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER lists_keep_want_to_try BEFORE UPDATE ON public.lists
  FOR EACH ROW EXECUTE FUNCTION public.lists_keep_want_to_try();

-- ---------------------------------------------------------------- place rows
-- Places as one viewer sees them: street and town, location, status, kinds (main first),
-- friends who favorited it (up to three named, earliest first, and how many in all), and the
-- viewer's own heart and Want to try. Internal: it takes the viewer as an argument.
CREATE FUNCTION public.places_for_viewer(viewer uuid, place_ids uuid[])
  RETURNS TABLE(id uuid, name text, address text, street text, city text, state text,
                lat double precision, lng double precision, status text,
                categories text[], category_paths text[], recommended_by jsonb, recommended_count integer,
                is_starred boolean, is_want boolean)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  WITH my_friends AS (
    SELECT DISTINCT CASE WHEN f.requester_id = viewer THEN f.addressee_id ELSE f.requester_id END AS friend_id
    FROM friendships f
    WHERE viewer IS NOT NULL AND f.status = 'accepted'
      AND (f.requester_id = viewer OR f.addressee_id = viewer)
  ),
  want_list AS (
    SELECT l.id FROM lists l WHERE viewer IS NOT NULL AND l.owner_id = viewer AND l.is_default_list
  )
  SELECT
    e.id, e.name,
    list_address(e.address, e.city) AS address,
    CASE WHEN NULLIF(trim(e.address), '') IS NULL THEN NULL
         ELSE split_part(list_address(e.address, e.city), ' · ', 1) END AS street,
    NULLIF(trim(e.city), '') AS city,
    NULLIF(trim(e.state), '') AS state,
    ST_Y(e.location::geometry) AS lat,
    ST_X(e.location::geometry) AS lng,
    e.status,
    ARRAY[mc.name] || COALESCE((
        SELECT array_agg(cat.name ORDER BY cat.path)
        FROM entity_categories ec JOIN categories cat ON cat.id = ec.category_id
        WHERE ec.entity_id = e.id AND cat.id <> mc.id), '{}') AS categories,
    ARRAY[mc.path::text] || COALESCE((
        SELECT array_agg(cat.path::text ORDER BY cat.path)
        FROM entity_categories ec JOIN categories cat ON cat.id = ec.category_id
        WHERE ec.entity_id = e.id AND cat.id <> mc.id), '{}') AS category_paths,
    (
      SELECT jsonb_agg(jsonb_build_object('name', t.name, 'handle', t.handle) ORDER BY t.starred_at)
      FROM (
        SELECT COALESCE(p.display_name, p.handle) AS name, p.handle, fs.created_at AS starred_at
        FROM stars fs
        JOIN my_friends mf ON mf.friend_id = fs.user_id
        JOIN profiles p ON p.id = fs.user_id
        WHERE fs.entity_id = e.id
        ORDER BY fs.created_at
        LIMIT 3
      ) t
    ) AS recommended_by,
    (SELECT count(*)::integer FROM stars fs JOIN my_friends mf ON mf.friend_id = fs.user_id
     WHERE fs.entity_id = e.id) AS recommended_count,
    viewer IS NOT NULL AND EXISTS (SELECT 1 FROM stars s WHERE s.user_id = viewer AND s.entity_id = e.id) AS is_starred,
    EXISTS (SELECT 1 FROM list_items li JOIN want_list w ON w.id = li.list_id WHERE li.entity_id = e.id) AS is_want
  FROM entities e
  JOIN categories mc ON mc.id = e.main_category_id
  WHERE e.id = ANY(place_ids);
$$;
REVOKE ALL ON FUNCTION public.places_for_viewer(uuid, uuid[]) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- my_favorites
-- Every place the viewer favorited, with when (added_at). Nothing for a visitor.
CREATE FUNCTION public.my_favorites()
  RETURNS TABLE(id uuid, name text, address text, street text, city text, state text,
                lat double precision, lng double precision, status text,
                categories text[], category_paths text[], recommended_by jsonb, recommended_count integer,
                is_starred boolean, is_want boolean, added_at timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH v AS (SELECT auth.uid() AS uid),
  mine AS (SELECT s.entity_id, s.created_at FROM stars s JOIN v ON s.user_id = v.uid)
  SELECT p.*, m.created_at AS added_at
  FROM v
  CROSS JOIN LATERAL public.places_for_viewer(v.uid, ARRAY(SELECT entity_id FROM mine)) p
  JOIN mine m ON m.entity_id = p.id
  ORDER BY lower(p.name), p.id;
$$;
REVOKE ALL ON FUNCTION public.my_favorites() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_favorites() TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- list_page
-- One list as the viewer may see it: the owner always; anyone for a public list; the owner's
-- friends for a friends' list.
--   id, name, description, visibility, is_default (Want to try), is_owner;
--   owner {name, handle}: the full name for the owner and their friends, else first name and
--     last initial;
--   places: place rows as above (the viewer's own hearts, friends and Want to try) with
--     added_at, A-Z.
-- {id, hidden: true} when the list isn't shared with the viewer; null when there's no such list.
CREATE FUNCTION public.list_page(list_id uuid)
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH v AS (SELECT auth.uid() AS uid),
  l AS (
    SELECT l.id, l.name, l.description, l.visibility, l.is_default_list, l.owner_id,
           v.uid IS NOT NULL AND l.owner_id = v.uid AS is_owner,
           v.uid IS NOT NULL AND EXISTS (
             SELECT 1 FROM friendships f
             WHERE f.status = 'accepted'
               AND ((f.requester_id = v.uid AND f.addressee_id = l.owner_id)
                 OR (f.addressee_id = v.uid AND f.requester_id = l.owner_id))) AS is_friend
    FROM lists l CROSS JOIN v
    WHERE l.id = list_page.list_id
  ),
  items AS (
    SELECT li.entity_id, li.added_at
    FROM list_items li JOIN l ON l.id = li.list_id
    WHERE l.is_owner OR l.visibility = 'public' OR (l.visibility = 'friends' AND l.is_friend)
  )
  SELECT CASE
    WHEN NOT (l.is_owner OR l.visibility = 'public' OR (l.visibility = 'friends' AND l.is_friend))
      THEN jsonb_build_object('id', l.id, 'hidden', true)
    ELSE jsonb_build_object(
      'id', l.id,
      'name', l.name,
      'description', NULLIF(trim(l.description), ''),
      'visibility', l.visibility,
      'is_default', l.is_default_list,
      'is_owner', l.is_owner,
      'owner', jsonb_build_object(
        'name', public.person_name(p.first_name, p.last_name, p.display_name, p.handle, l.is_owner OR l.is_friend),
        'handle', p.handle),
      'places', COALESCE((
        SELECT jsonb_agg(to_jsonb(r) || jsonb_build_object('added_at', i.added_at) ORDER BY lower(r.name), r.id)
        FROM public.places_for_viewer(v.uid, ARRAY(SELECT entity_id FROM items)) r
        JOIN items i ON i.entity_id = r.id), '[]'::jsonb))
  END
  FROM l
  JOIN profiles p ON p.id = l.owner_id
  CROSS JOIN v;
$$;
REVOKE ALL ON FUNCTION public.list_page(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_page(uuid) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- lists_overview
-- The Lists page: the viewer's own lists (is_mine) and the lists their friends share with them
-- (Friends or Public), each with
--   place_count; towns, the three with the most places (then A-Z), and town_count;
--   closest_miles from (ref_lat, ref_lng), null without a point or places;
--   points, up to 24 [lat, lng] of its latest places, for the card's small map;
--   owner_name and owner_handle for a friend's list (full name: they're friends).
-- Nothing for a visitor.
CREATE FUNCTION public.lists_overview(ref_lat double precision DEFAULT NULL, ref_lng double precision DEFAULT NULL)
  RETURNS TABLE(id uuid, name text, visibility text, is_default boolean, is_mine boolean,
                owner_name text, owner_handle text, place_count integer, towns text[], town_count integer,
                closest_miles numeric, points jsonb, created_at timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH v AS (
    SELECT auth.uid() AS uid,
           CASE WHEN ref_lat IS NOT NULL AND ref_lng IS NOT NULL
                THEN ST_SetSRID(ST_MakePoint(ref_lng, ref_lat), 4326)::geography END AS g
  ),
  my_friends AS (
    SELECT DISTINCT CASE WHEN f.requester_id = v.uid THEN f.addressee_id ELSE f.requester_id END AS friend_id
    FROM friendships f CROSS JOIN v
    WHERE v.uid IS NOT NULL AND f.status = 'accepted'
      AND (f.requester_id = v.uid OR f.addressee_id = v.uid)
  ),
  shown AS (
    SELECT l.*, l.owner_id = v.uid AS mine
    FROM lists l CROSS JOIN v
    WHERE v.uid IS NOT NULL
      AND (l.owner_id = v.uid
           OR (l.visibility IN ('friends', 'public') AND l.owner_id IN (SELECT friend_id FROM my_friends)))
  )
  SELECT
    s.id, s.name, s.visibility, s.is_default_list, s.mine,
    CASE WHEN s.mine THEN NULL ELSE public.person_name(p.first_name, p.last_name, p.display_name, p.handle, true) END,
    CASE WHEN s.mine THEN NULL ELSE p.handle END,
    c.place_count,
    COALESCE(tw.towns, '{}'),
    COALESCE(tw.town_count, 0),
    c.closest_miles,
    pt.points,
    s.created_at
  FROM shown s
  JOIN profiles p ON p.id = s.owner_id
  CROSS JOIN v
  CROSS JOIN LATERAL (
    SELECT count(*)::integer AS place_count,
           round((min(ST_Distance(e.location, v.g)) / 1609.34)::numeric, 2) AS closest_miles
    FROM list_items li JOIN entities e ON e.id = li.entity_id
    WHERE li.list_id = s.id
  ) c
  CROSS JOIN LATERAL (
    SELECT array_agg(t.city ORDER BY t.n DESC, t.city) FILTER (WHERE t.rn <= 3) AS towns,
           count(*)::integer AS town_count
    FROM (
      SELECT NULLIF(trim(e.city), '') AS city, count(*) AS n,
             row_number() OVER (ORDER BY count(*) DESC, NULLIF(trim(e.city), '')) AS rn
      FROM list_items li JOIN entities e ON e.id = li.entity_id
      WHERE li.list_id = s.id AND NULLIF(trim(e.city), '') IS NOT NULL
      GROUP BY 1
    ) t
  ) tw
  CROSS JOIN LATERAL (
    SELECT COALESCE(jsonb_agg(jsonb_build_array(round(ST_Y(x.location::geometry)::numeric, 5),
                                                round(ST_X(x.location::geometry)::numeric, 5))), '[]'::jsonb) AS points
    FROM (
      SELECT e.location FROM list_items li JOIN entities e ON e.id = li.entity_id
      WHERE li.list_id = s.id
      ORDER BY li.added_at DESC NULLS LAST, e.id
      LIMIT 24
    ) x
  ) pt
  ORDER BY s.mine DESC, s.is_default_list DESC, lower(s.name), s.id;
$$;
REVOKE ALL ON FUNCTION public.lists_overview(double precision, double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lists_overview(double precision, double precision) TO anon, authenticated, service_role;
