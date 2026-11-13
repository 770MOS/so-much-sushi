-- Friends, a friend's page and account settings (build step 6, mocked and approved 2026-11-12).
--
-- * Friend requests go through functions. Before this, a signed-in person could write the
--   friendships table directly: add a row already marked accepted, or (as the person asked)
--   rewrite who sent it, and so see anyone's favorites and Friends lists without their say.
--   Now: send_friend_request, answer_friend_request and remove_friend; direct inserts and
--   updates are no longer allowed (removing a row yourself still is).
-- * Invite links: each person can get a link (my_invite_code, renewable so an old link stops
--   working); opening it while signed in makes the two of you friends (accept_invite).
-- * friends_overview()       the Friends page: requests to you, requests you sent, your friends.
-- * find_people(q)           people by name or username.
-- * person_page(handle)      a person's page: their favorites (friends only) and the lists the
--                            viewer may see.
-- * Settings: name on public lists (first name and last initial, or full name), who sees new
--   lists (new lists start with it), email choices (kept for when those emails are sent),
--   my_settings() to read them, my_data_export() for "Download your data".
SET search_path = public, extensions;

-- ---------------------------------------------------------------- columns
ALTER TABLE public.profiles
  ADD COLUMN public_name_full boolean NOT NULL DEFAULT false,
  ADD COLUMN new_list_visibility text NOT NULL DEFAULT 'private'
    CHECK (new_list_visibility IN ('private', 'friends', 'public')),
  ADD COLUMN email_friend_requests boolean NOT NULL DEFAULT true,
  ADD COLUMN email_place_requests boolean NOT NULL DEFAULT true,
  ADD COLUMN invite_code text UNIQUE;

ALTER TABLE public.friendships ADD COLUMN accepted_at timestamptz;
UPDATE public.friendships SET accepted_at = created_at WHERE status = 'accepted' AND accepted_at IS NULL;

-- ---------------------------------------------------------------- friendships through functions
DROP POLICY IF EXISTS "Send requests as yourself" ON public.friendships;
DROP POLICY IF EXISTS "Addressee accepts or blocks" ON public.friendships;
REVOKE INSERT, UPDATE, TRUNCATE ON public.friendships FROM anon, authenticated;

-- The friendship between the viewer and someone else, either way round.
CREATE FUNCTION public.friendship_with(viewer uuid, other uuid)
  RETURNS TABLE(requester_id uuid, addressee_id uuid, status text)
  LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT f.requester_id, f.addressee_id, f.status FROM friendships f
  WHERE (f.requester_id = viewer AND f.addressee_id = other)
     OR (f.requester_id = other AND f.addressee_id = viewer)
  ORDER BY (f.status = 'accepted') DESC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.friendship_with(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- 'self', 'friends', 'sent' (viewer asked), 'received' (they asked) or 'none'. A block reads as
-- 'none' to the person blocked.
CREATE FUNCTION public.relation_to(viewer uuid, other uuid)
  RETURNS text
  LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN viewer IS NULL THEN 'none'
    WHEN viewer = other THEN 'self'
    ELSE COALESCE((
      SELECT CASE
        WHEN f.status = 'accepted' THEN 'friends'
        WHEN f.status = 'pending' AND f.requester_id = viewer THEN 'sent'
        WHEN f.status = 'pending' THEN 'received'
        ELSE 'none' END
      FROM public.friendship_with(viewer, other) f), 'none')
  END;
$$;
REVOKE ALL ON FUNCTION public.relation_to(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Ask someone to be friends. If they already asked you, you become friends. Returns the
-- relation afterwards: 'friends' or 'sent'.
CREATE FUNCTION public.send_friend_request(other uuid)
  RETURNS text
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_rel text;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Sign in to add friends' USING ERRCODE = '42501'; END IF;
  IF other IS NULL OR other = v_me OR NOT EXISTS (SELECT 1 FROM profiles WHERE id = other) THEN
    RAISE EXCEPTION 'No such person' USING ERRCODE = 'no_data_found';
  END IF;
  -- A block either way: say it was sent and change nothing.
  IF EXISTS (SELECT 1 FROM friendship_with(v_me, other) WHERE status = 'blocked') THEN RETURN 'sent'; END IF;
  v_rel := relation_to(v_me, other);
  IF v_rel = 'received' THEN
    UPDATE friendships SET status = 'accepted', accepted_at = now()
    WHERE requester_id = other AND addressee_id = v_me AND status = 'pending';
    RETURN 'friends';
  ELSIF v_rel IN ('friends', 'sent') THEN
    RETURN v_rel;
  END IF;
  INSERT INTO friendships (requester_id, addressee_id, status) VALUES (v_me, other, 'pending')
  ON CONFLICT (requester_id, addressee_id) DO NOTHING;
  RETURN 'sent';
END;
$$;

-- Accept or decline a request someone sent you. Returns 'friends' or 'none'.
CREATE FUNCTION public.answer_friend_request(other uuid, accept boolean)
  RETURNS text
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Sign in to answer requests' USING ERRCODE = '42501'; END IF;
  IF accept THEN
    UPDATE friendships SET status = 'accepted', accepted_at = now()
    WHERE requester_id = other AND addressee_id = v_me AND status = 'pending';
  ELSE
    DELETE FROM friendships WHERE requester_id = other AND addressee_id = v_me AND status = 'pending';
  END IF;
  RETURN relation_to(v_me, other);
END;
$$;

-- Remove a friend, or take back a request you sent. Returns 'none'.
CREATE FUNCTION public.remove_friend(other uuid)
  RETURNS text
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Sign in first' USING ERRCODE = '42501'; END IF;
  DELETE FROM friendships
  WHERE status IN ('accepted', 'pending')
    AND ((requester_id = v_me AND addressee_id = other)
      OR (requester_id = other AND addressee_id = v_me AND status = 'accepted'));
  RETURN relation_to(v_me, other);
END;
$$;

REVOKE ALL ON FUNCTION public.send_friend_request(uuid), public.answer_friend_request(uuid, boolean),
  public.remove_friend(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_friend_request(uuid), public.answer_friend_request(uuid, boolean),
  public.remove_friend(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------- invite links
-- The viewer's invite code, made the first time; renew = a new one, so the old link stops working.
CREATE FUNCTION public.my_invite_code(renew boolean DEFAULT false)
  RETURNS text
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_code text;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Sign in first' USING ERRCODE = '42501'; END IF;
  SELECT invite_code INTO v_code FROM profiles WHERE id = v_me;
  IF v_code IS NULL OR renew THEN
    v_code := substr(replace(gen_random_uuid()::text, '-', ''), 1, 16);
    UPDATE profiles SET invite_code = v_code WHERE id = v_me;
  END IF;
  RETURN v_code;
END;
$$;
REVOKE ALL ON FUNCTION public.my_invite_code(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_invite_code(boolean) TO authenticated, service_role;

-- Who an invite is from, for the invite page: their name (first name and last initial unless
-- they chose their full name), handle, and the viewer's relation to them. Null for a code
-- that doesn't exist (or no longer does).
CREATE FUNCTION public.invite_info(code text)
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'name', person_name(p.first_name, p.last_name, p.display_name, p.handle,
                        p.public_name_full OR relation_to(auth.uid(), p.id) IN ('self', 'friends')),
    'handle', p.handle,
    'relation', relation_to(auth.uid(), p.id))
  FROM profiles p
  WHERE p.invite_code IS NOT NULL AND p.invite_code = invite_info.code;
$$;
REVOKE ALL ON FUNCTION public.invite_info(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_info(text) TO anon, authenticated, service_role;

-- Opening an invite while signed in: the two become friends (the inviter agreed by sharing the
-- link). Returns {handle, relation}; null for a code that doesn't exist.
CREATE FUNCTION public.accept_invite(code text)
  RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_owner uuid;
  v_handle text;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Sign in first' USING ERRCODE = '42501'; END IF;
  SELECT id, handle INTO v_owner, v_handle FROM profiles WHERE invite_code IS NOT NULL AND invite_code = accept_invite.code;
  IF v_owner IS NULL THEN RETURN NULL; END IF;
  IF v_owner <> v_me AND NOT EXISTS (SELECT 1 FROM friendship_with(v_me, v_owner) WHERE status = 'blocked') THEN
    UPDATE friendships SET status = 'accepted', accepted_at = now()
    WHERE status = 'pending'
      AND ((requester_id = v_me AND addressee_id = v_owner) OR (requester_id = v_owner AND addressee_id = v_me));
    IF NOT FOUND AND relation_to(v_me, v_owner) <> 'friends' THEN
      INSERT INTO friendships (requester_id, addressee_id, status, accepted_at)
      VALUES (v_owner, v_me, 'accepted', now())
      ON CONFLICT (requester_id, addressee_id) DO UPDATE SET status = 'accepted', accepted_at = now();
    END IF;
  END IF;
  RETURN jsonb_build_object('handle', v_handle, 'relation', relation_to(v_me, v_owner));
END;
$$;
REVOKE ALL ON FUNCTION public.accept_invite(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_invite(text) TO authenticated, service_role;

-- ---------------------------------------------------------------- the Friends page
-- {incoming: [...], outgoing: [...], friends: [...]}; each person {id, name (full), handle,
-- in_common (friends you share), since (when asked, or friends since)}; friends also carry
-- favorites (how many) and shared_lists (their Friends and Public lists).
CREATE FUNCTION public.friends_overview()
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH v AS (SELECT auth.uid() AS uid),
  mine AS (
    SELECT CASE WHEN f.requester_id = v.uid THEN f.addressee_id ELSE f.requester_id END AS other,
           f.status, f.requester_id = v.uid AS i_asked, COALESCE(f.accepted_at, f.created_at) AS since
    FROM friendships f CROSS JOIN v
    WHERE v.uid IS NOT NULL AND (f.requester_id = v.uid OR f.addressee_id = v.uid) AND f.status IN ('pending', 'accepted')
  ),
  my_friends AS (SELECT other FROM mine WHERE status = 'accepted'),
  people AS (
    SELECT m.*, p.handle,
           person_name(p.first_name, p.last_name, p.display_name, p.handle, true) AS name,
           (SELECT count(*)::integer FROM friendships g
            WHERE g.status = 'accepted'
              AND ((g.requester_id = m.other AND g.addressee_id IN (SELECT other FROM my_friends))
                OR (g.addressee_id = m.other AND g.requester_id IN (SELECT other FROM my_friends)))) AS in_common,
           (SELECT count(*)::integer FROM stars s WHERE s.user_id = m.other) AS favorites,
           (SELECT count(*)::integer FROM lists l WHERE l.owner_id = m.other AND l.visibility IN ('friends', 'public')) AS shared_lists
    FROM mine m JOIN profiles p ON p.id = m.other
  )
  SELECT jsonb_build_object(
    'incoming', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', other, 'name', name, 'handle', handle,
                            'in_common', in_common, 'since', since) ORDER BY since DESC)
                          FROM people WHERE status = 'pending' AND NOT i_asked), '[]'::jsonb),
    'outgoing', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', other, 'name', name, 'handle', handle,
                            'in_common', in_common, 'since', since) ORDER BY since DESC)
                          FROM people WHERE status = 'pending' AND i_asked), '[]'::jsonb),
    'friends', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', other, 'name', name, 'handle', handle,
                            'in_common', in_common, 'since', since, 'favorites', favorites,
                            'shared_lists', shared_lists) ORDER BY lower(name))
                         FROM people WHERE status = 'accepted'), '[]'::jsonb));
$$;
REVOKE ALL ON FUNCTION public.friends_overview() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.friends_overview() TO anon, authenticated, service_role;

-- People by name or username (two letters or more), for a signed-in viewer: up to 20, names
-- that start with the text first. Each with relation and friends in common.
CREATE FUNCTION public.find_people(q text)
  RETURNS TABLE(id uuid, name text, handle text, relation text, in_common integer)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH v AS (SELECT auth.uid() AS uid, lower(trim(coalesce(q, ''))) AS t),
  my_friends AS (
    SELECT CASE WHEN f.requester_id = v.uid THEN f.addressee_id ELSE f.requester_id END AS other
    FROM friendships f CROSS JOIN v
    WHERE f.status = 'accepted' AND (f.requester_id = v.uid OR f.addressee_id = v.uid)
  ),
  hits AS (
    SELECT p.*, person_name(p.first_name, p.last_name, p.display_name, p.handle, true) AS full_name
    FROM profiles p CROSS JOIN v
    WHERE v.uid IS NOT NULL AND length(v.t) >= 2 AND p.id <> v.uid
      AND (lower(coalesce(p.handle, '')) LIKE ltrim(v.t, '@') || '%'
           OR lower(concat_ws(' ', p.first_name, p.last_name)) LIKE '%' || v.t || '%'
           OR lower(coalesce(p.display_name, '')) LIKE '%' || v.t || '%')
      AND NOT EXISTS (SELECT 1 FROM friendships b WHERE b.status = 'blocked'
                      AND ((b.requester_id = p.id AND b.addressee_id = v.uid) OR (b.requester_id = v.uid AND b.addressee_id = p.id)))
  )
  SELECT h.id, h.full_name, h.handle, relation_to(v.uid, h.id),
         (SELECT count(*)::integer FROM friendships g
          WHERE g.status = 'accepted'
            AND ((g.requester_id = h.id AND g.addressee_id IN (SELECT other FROM my_friends))
              OR (g.addressee_id = h.id AND g.requester_id IN (SELECT other FROM my_friends))))
  FROM hits h CROSS JOIN v
  ORDER BY (lower(h.full_name) LIKE v.t || '%' OR lower(coalesce(h.handle, '')) LIKE ltrim(v.t, '@') || '%') DESC,
           lower(h.full_name), h.id
  LIMIT 20;
$$;
REVOKE ALL ON FUNCTION public.find_people(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_people(text) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- a person's page
-- {id, name, handle, relation, friends_since, favorites_count, favorites, lists}:
--   name: full for the person, their friends, or if they chose it; else first name and last
--     initial;
--   favorites: their favorites as place rows (the viewer's own hearts in is_starred), for the
--     person and their friends only; favorites_count the same;
--   lists: the lists the viewer may see (all for the person; Friends and Public for a friend;
--     Public for anyone else) with place_count and towns.
-- Null when there's no one with that handle.
CREATE FUNCTION public.person_page(person_handle text)
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  WITH v AS (SELECT auth.uid() AS uid),
  p AS (
    SELECT pr.*, relation_to(v.uid, pr.id) AS rel FROM profiles pr CROSS JOIN v
    WHERE pr.handle IS NOT NULL AND lower(pr.handle) = lower(trim(person_page.person_handle))
    LIMIT 1
  ),
  favs AS (
    SELECT s.entity_id FROM stars s JOIN p ON s.user_id = p.id WHERE p.rel IN ('self', 'friends')
  ),
  shown_lists AS (
    SELECT l.* FROM lists l JOIN p ON l.owner_id = p.id
    WHERE p.rel = 'self' OR l.visibility = 'public' OR (p.rel = 'friends' AND l.visibility = 'friends')
  )
  SELECT jsonb_build_object(
    'id', p.id,
    'name', person_name(p.first_name, p.last_name, p.display_name, p.handle, p.public_name_full OR p.rel IN ('self', 'friends')),
    'handle', p.handle,
    'relation', p.rel,
    'friends_since', (SELECT f.accepted_at FROM friendships f
                      WHERE p.rel = 'friends' AND f.status = 'accepted'
                        AND ((f.requester_id = p.id AND f.addressee_id = v.uid) OR (f.requester_id = v.uid AND f.addressee_id = p.id))
                      LIMIT 1),
    'favorites_count', (SELECT count(*)::integer FROM favs),
    'favorites', COALESCE((
       SELECT jsonb_agg(to_jsonb(r) ORDER BY lower(r.name), r.id)
       FROM places_for_viewer(v.uid, ARRAY(SELECT entity_id FROM favs)) r), '[]'::jsonb),
    'lists', COALESCE((
       SELECT jsonb_agg(jsonb_build_object(
                'id', l.id, 'name', l.name, 'visibility', l.visibility, 'is_default', l.is_default_list,
                'place_count', (SELECT count(*)::integer FROM list_items li WHERE li.list_id = l.id),
                'towns', COALESCE((SELECT array_agg(t.city ORDER BY t.n DESC, t.city) FROM (
                            SELECT NULLIF(trim(e.city), '') AS city, count(*) AS n
                            FROM list_items li JOIN entities e ON e.id = li.entity_id
                            WHERE li.list_id = l.id AND NULLIF(trim(e.city), '') IS NOT NULL
                            GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 3) t), '{}'))
              ORDER BY l.is_default_list DESC, lower(l.name))
       FROM shown_lists l), '[]'::jsonb))
  FROM p CROSS JOIN v;
$$;
REVOKE ALL ON FUNCTION public.person_page(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.person_page(text) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------- the public-list name
-- list_page as before, with the owner's choice of full name on public lists.
CREATE OR REPLACE FUNCTION public.list_page(list_id uuid)
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
        'name', public.person_name(p.first_name, p.last_name, p.display_name, p.handle,
                                   l.is_owner OR l.is_friend OR p.public_name_full),
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

-- ---------------------------------------------------------------- new lists start with the setting
CREATE FUNCTION public.my_new_list_visibility()
  RETURNS text
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT new_list_visibility FROM profiles WHERE id = auth.uid()), 'private');
$$;
REVOKE ALL ON FUNCTION public.my_new_list_visibility() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_new_list_visibility() TO anon, authenticated, service_role;
ALTER TABLE public.lists ALTER COLUMN visibility SET DEFAULT public.my_new_list_visibility();

-- ---------------------------------------------------------------- settings and your data
-- The signed-in person's own settings (some of these columns aren't readable by others).
CREATE FUNCTION public.my_settings()
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'first_name', p.first_name, 'last_name', p.last_name, 'display_name', p.display_name, 'handle', p.handle,
    'public_name_full', p.public_name_full, 'new_list_visibility', p.new_list_visibility,
    'email_friend_requests', p.email_friend_requests, 'email_place_requests', p.email_place_requests,
    'home_city', p.home_city, 'home_state', p.home_state)
  FROM profiles p WHERE p.id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.my_settings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_settings() TO anon, authenticated, service_role;

-- Everything the person has made, as rows for a spreadsheet: their favorites, their lists'
-- places (an empty list as one row with no place), and their friends.
CREATE FUNCTION public.my_data_export()
  RETURNS TABLE(section text, list_name text, name text, address text, town text, state text,
                added timestamptz, place_id uuid)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH v AS (SELECT auth.uid() AS uid)
  SELECT * FROM (
    SELECT 'Favorite'::text, NULL::text, e.name, NULLIF(trim(e.address), ''), NULLIF(trim(e.city), ''),
           NULLIF(trim(e.state), ''), s.created_at, e.id
    FROM stars s JOIN v ON s.user_id = v.uid JOIN entities e ON e.id = s.entity_id
    UNION ALL
    SELECT 'List', l.name, e.name, NULLIF(trim(e.address), ''), NULLIF(trim(e.city), ''),
           NULLIF(trim(e.state), ''), COALESCE(li.added_at, l.created_at), e.id
    FROM lists l JOIN v ON l.owner_id = v.uid
    LEFT JOIN list_items li ON li.list_id = l.id
    LEFT JOIN entities e ON e.id = li.entity_id
    UNION ALL
    SELECT 'Friend', NULL, person_name(p.first_name, p.last_name, p.display_name, p.handle, true),
           CASE WHEN p.handle IS NOT NULL THEN '@' || p.handle END, NULL, NULL,
           COALESCE(f.accepted_at, f.created_at), NULL
    FROM friendships f JOIN v ON f.status = 'accepted' AND (f.requester_id = v.uid OR f.addressee_id = v.uid)
    JOIN profiles p ON p.id = CASE WHEN f.requester_id = v.uid THEN f.addressee_id ELSE f.requester_id END
  ) t(section, list_name, name, address, town, state, added, place_id)
  ORDER BY 1, 2 NULLS FIRST, lower(t.name);
$$;
REVOKE ALL ON FUNCTION public.my_data_export() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_data_export() TO authenticated, service_role;
