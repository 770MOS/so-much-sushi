-- Admin list and the functions behind the /admin review queue.
-- Everything here is service_role only: the app checks the signed-in user against
-- public.admins on the server, then calls these with the service role key.
SET search_path = public, extensions;

CREATE TABLE public.admins (
  user_id  uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email    text NOT NULL,
  added_by text NOT NULL,
  added_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admins FROM anon, authenticated;
GRANT ALL ON public.admins TO service_role;

-- Make an existing account an admin. The person must have signed up first.
CREATE FUNCTION public.add_admin_by_email(p_email text, p_added_by text)
  RETURNS uuid
  LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_user uuid;
BEGIN
  SELECT id INTO v_user FROM auth.users WHERE lower(email) = lower(trim(p_email));
  IF v_user IS NULL THEN RAISE EXCEPTION 'no account with email %; sign up first', p_email; END IF;
  INSERT INTO admins (user_id, email, added_by) VALUES (v_user, lower(trim(p_email)), p_added_by)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN v_user;
END $$;
REVOKE EXECUTE ON FUNCTION public.add_admin_by_email(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_admin_by_email(text, text) TO service_role;

-- Pending "are these the same place?" proposals, with both places side by side.
CREATE FUNCTION public.admin_pending_merges()
  RETURNS TABLE(event_id bigint, created_at timestamptz,
                a_id uuid, a_name text, a_address text, a_city text, a_state text, a_phone text, a_website text, a_status text,
                b_id uuid, b_name text, b_address text, b_city text, b_state text, b_phone text, b_website text, b_status text,
                distance_m integer, name_similarity numeric, same_phone boolean, same_website boolean)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT c.id, c.created_at,
         a.id, a.name, a.address, a.city, a.state, a.phone, a.website, a.status,
         b.id, b.name, b.address, b.city, b.state, b.phone, b.website, b.status,
         (c.evidence->>'distance_m')::integer, (c.evidence->>'name_similarity')::numeric,
         (c.evidence->>'same_phone')::boolean, (c.evidence->>'same_website')::boolean
  FROM change_events c
  JOIN entities a ON a.id = c.entity_id
  JOIN entities b ON b.id = (c.old_value->>'duplicate')::uuid
  WHERE c.status = 'pending' AND c.event_type = 'merge'
  ORDER BY c.id;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_pending_merges() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pending_merges() TO service_role;

-- Pending tag suggestions, optionally for one tag.
CREATE FUNCTION public.admin_pending_tags(p_tag text DEFAULT NULL, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
  RETURNS TABLE(event_id bigint, entity_id uuid, name text, address text, city text, state text,
                main_category text, tag_path text, tag_name text, keyword text)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT c.id, e.id, e.name, e.address, e.city, e.state, m.name,
         c.new_value->>'add_category', t.name, c.evidence->>'keyword'
  FROM change_events c
  JOIN entities e ON e.id = c.entity_id
  JOIN categories m ON m.id = e.main_category_id
  LEFT JOIN categories t ON t.path = (c.new_value->>'add_category')::ltree
  WHERE c.status = 'pending' AND c.field = 'categories' AND c.new_value ? 'add_category'
    AND (p_tag IS NULL OR c.new_value->>'add_category' = p_tag)
  ORDER BY c.new_value->>'add_category', e.name, c.id
  LIMIT p_limit OFFSET p_offset;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_pending_tags(text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pending_tags(text, integer, integer) TO service_role;

CREATE FUNCTION public.admin_pending_tag_counts()
  RETURNS TABLE(tag_path text, tag_name text, pending bigint)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT c.new_value->>'add_category', max(t.name), count(*)
  FROM change_events c
  LEFT JOIN categories t ON t.path = (c.new_value->>'add_category')::ltree
  WHERE c.status = 'pending' AND c.field = 'categories' AND c.new_value ? 'add_category'
  GROUP BY 1 ORDER BY 3 DESC, 1;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_pending_tag_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pending_tag_counts() TO service_role;

-- Decide several tag suggestions at once. Returns how many were decided.
CREATE FUNCTION public.decide_tag_suggestions(p_events bigint[], p_accept boolean, p_decided_by text)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_id bigint; v_n integer := 0;
BEGIN
  FOR v_id IN SELECT c.id FROM change_events c
              WHERE c.id = ANY(p_events) AND c.status = 'pending' AND c.field = 'categories' ORDER BY c.id LOOP
    PERFORM decide_tag_suggestion(v_id, p_accept, p_decided_by);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION public.decide_tag_suggestions(bigint[], boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.decide_tag_suggestions(bigint[], boolean, text) TO service_role;

-- Decide several merge proposals at once. Accepting merges the duplicate into the
-- survivor with merge_entities(); the survivor keeps its own field values.
-- A proposal whose two places have since become one is closed as superseded.
CREATE FUNCTION public.decide_merge_proposals(p_events bigint[], p_accept boolean, p_decided_by text)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v change_events%ROWTYPE; v_dup uuid; v_sur uuid; v_n integer := 0;
BEGIN
  FOR v IN SELECT * FROM change_events c
           WHERE c.id = ANY(p_events) AND c.status = 'pending' AND c.event_type = 'merge'
           ORDER BY c.id FOR UPDATE LOOP
    v_sur := resolve_entity(v.entity_id);
    v_dup := resolve_entity((v.old_value->>'duplicate')::uuid);
    IF v_sur = v_dup THEN
      UPDATE change_events SET status = 'superseded', decided_by = p_decided_by, decided_at = now() WHERE id = v.id;
    ELSIF p_accept THEN
      PERFORM merge_entities(v_dup, v_sur, p_decided_by, 'review queue proposal ' || v.id);
      UPDATE change_events SET status = 'approved', decided_by = p_decided_by, decided_at = now(), applied_at = now() WHERE id = v.id;
    ELSE
      UPDATE change_events SET status = 'rejected', decided_by = p_decided_by, decided_at = now() WHERE id = v.id;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION public.decide_merge_proposals(bigint[], boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.decide_merge_proposals(bigint[], boolean, text) TO service_role;
