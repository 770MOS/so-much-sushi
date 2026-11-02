-- Request a place (agreed 2026-11-02).
--
-- Signed-in people can tell us about a food or drink place that is missing. A request
-- never creates a place by itself: it waits in the admin review queue, where an admin
--   adds it         - it becomes a place added by hand (one we are responsible for),
--   links it        - we already have it, or
--   declines it.
-- People can see what happened to their own requests.
--
-- People confirm the details come from their own visit, the place's sign or its own
-- website, not from Google Maps, Yelp or another app, so what we keep stays ours.
--
-- For signed-in people (SECURITY DEFINER, authenticated only):
--   request_similar_places(lat, lng, name, phone)  places we may already have, shown first
--   submit_place_request(values)                   sends a request
--   my_place_requests()                            their own requests and what happened
-- For the admin screens (service_role only):
--   admin_pending_place_requests(), admin_get_place_request(id),
--   admin_approve_place_request(id, values, by, note), admin_link_place_request(id, place, by, note),
--   admin_decline_place_requests(ids, by, note)
SET search_path = public, extensions;

CREATE TABLE public.place_requests (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  requested_by     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  name             text NOT NULL,
  main_category_id uuid NOT NULL REFERENCES public.categories(id),
  location         geography(Point, 4326) NOT NULL,
  address          text,
  city             text,
  state            text,
  postal_code      text,
  phone            text,
  website          text,
  note             text,
  -- The person confirmed the details are their own knowledge (see above).
  own_knowledge    boolean NOT NULL CHECK (own_knowledge),
  status           text NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'added', 'already_listed', 'declined')),
  -- The place it became (added) or turned out to be (already_listed).
  entity_id        uuid REFERENCES public.entities(id),
  decided_by       text,
  decided_at       timestamptz,
  decision_note    text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT place_requests_entity_check CHECK ((status IN ('added', 'already_listed')) = (entity_id IS NOT NULL)),
  CONSTRAINT place_requests_decided_check CHECK ((status = 'pending') = (decided_at IS NULL))
);
CREATE INDEX place_requests_pending_idx ON public.place_requests (created_at) WHERE status = 'pending';
CREATE INDEX place_requests_requested_by_idx ON public.place_requests (requested_by, created_at);
CREATE INDEX place_requests_location_idx ON public.place_requests USING gist (location);

ALTER TABLE public.place_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.place_requests FROM anon, authenticated;
GRANT ALL ON public.place_requests TO service_role;

-- Places we may already have, shown before a request is sent. Only places people can
-- see in search (not permanently closed, merged or removed).
CREATE FUNCTION public.request_similar_places(p_lat double precision, p_lng double precision, p_name text, p_phone text DEFAULT NULL)
  RETURNS TABLE(id uuid, name text, address text, city text, state text, distance_m integer)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT s.id, s.name, s.address, s.city, s.state, s.distance_m
  FROM admin_similar_places(p_lat, p_lng, p_name, p_phone) s
  JOIN entities e ON e.id = s.id
  WHERE auth.uid() IS NOT NULL
    AND NULLIF(trim(p_name), '') IS NOT NULL
    AND e.status NOT IN ('permanently_closed', 'merged', 'removed')
  ORDER BY s.distance_m;
$$;
REVOKE EXECUTE ON FUNCTION public.request_similar_places(double precision, double precision, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_similar_places(double precision, double precision, text, text) TO authenticated, service_role;

-- Sends a request for the signed-in person. Values: name, main_category (a main
-- category path), lat, lng, own_knowledge (true), and optionally address, city, state,
-- postal_code, phone, website, note.
CREATE FUNCTION public.submit_place_request(p_values jsonb)
  RETURNS bigint
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_user uuid := auth.uid();
  v_name text := NULLIF(trim(p_values->>'name'), '');
  v_state text := upper(blank_to_null(trim(p_values->>'state')));
  v_lat double precision; v_lng double precision; v_loc geography; v_main uuid; v_id bigint;
  v_limit constant integer := 25;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'sign in to request a place'; END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'a place needs a name'; END IF;
  IF length(v_name) > 200 THEN RAISE EXCEPTION 'the name is too long'; END IF;
  BEGIN
    v_lat := (p_values->>'lat')::double precision;
    v_lng := (p_values->>'lng')::double precision;
  EXCEPTION WHEN others THEN RAISE EXCEPTION 'the map pin is not a valid position';
  END;
  IF v_lat IS NULL OR v_lng IS NULL THEN RAISE EXCEPTION 'place the pin on the map'; END IF;
  -- The United States, including Alaska, Hawaii and Puerto Rico (as for places added by hand).
  IF v_lat NOT BETWEEN 17 AND 72 OR v_lng NOT BETWEEN -180 AND -64 THEN
    RAISE EXCEPTION 'the pin is outside the United States';
  END IF;
  SELECT id INTO v_main FROM categories WHERE path::text = p_values->>'main_category' AND nlevel(path) = 1;
  IF v_main IS NULL THEN RAISE EXCEPTION 'choose what kind of place it is'; END IF;
  IF (p_values->>'own_knowledge') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'confirm where the details come from';
  END IF;
  IF v_state IS NOT NULL AND v_state !~ '^[A-Z]{2}$' THEN RAISE EXCEPTION 'use the two-letter state code'; END IF;
  IF length(COALESCE(p_values->>'address', '')) > 300 OR length(COALESCE(p_values->>'city', '')) > 100
     OR length(COALESCE(p_values->>'postal_code', '')) > 10 OR length(COALESCE(p_values->>'phone', '')) > 40
     OR length(COALESCE(p_values->>'website', '')) > 500 OR length(COALESCE(p_values->>'note', '')) > 1000 THEN
    RAISE EXCEPTION 'one of the details is too long';
  END IF;

  IF (SELECT count(*) FROM place_requests WHERE requested_by = v_user AND created_at > now() - interval '1 day') >= v_limit THEN
    RAISE EXCEPTION 'you have sent % requests in the last day; please try again tomorrow', v_limit;
  END IF;

  v_loc := ST_SetSRID(ST_MakePoint(v_lng, v_lat), 4326)::geography;
  IF EXISTS (SELECT 1 FROM place_requests r
             WHERE r.requested_by = v_user AND r.status = 'pending'
               AND ST_DWithin(r.location, v_loc, 150)
               AND (match_name(r.name) = match_name(v_name) OR similarity(match_name(r.name), match_name(v_name)) >= 0.6)) THEN
    RAISE EXCEPTION 'you already asked for this place; it is waiting for review';
  END IF;

  INSERT INTO place_requests (requested_by, name, main_category_id, location, address, city, state, postal_code,
                              phone, website, note, own_knowledge)
  VALUES (v_user, v_name, v_main, v_loc, blank_to_null(trim(p_values->>'address')), blank_to_null(trim(p_values->>'city')),
          v_state, blank_to_null(trim(p_values->>'postal_code')), blank_to_null(trim(p_values->>'phone')),
          blank_to_null(trim(p_values->>'website')), blank_to_null(trim(p_values->>'note')), true)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.submit_place_request(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_place_request(jsonb) TO authenticated, service_role;

-- The signed-in person's own requests, newest first. place_id links to the place it
-- became or turned out to be (following a merge to the surviving place).
CREATE FUNCTION public.my_place_requests()
  RETURNS TABLE(id bigint, name text, main_category text, city text, state text, status text,
                place_id uuid, created_at timestamptz, decided_at timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT r.id, r.name, m.name, r.city, r.state, r.status,
         CASE WHEN e.status = 'merged' THEN e.merged_into WHEN e.status = 'removed' THEN NULL ELSE e.id END,
         r.created_at, r.decided_at
  FROM place_requests r
  JOIN categories m ON m.id = r.main_category_id
  LEFT JOIN entities e ON e.id = r.entity_id
  WHERE r.requested_by = auth.uid()
  ORDER BY r.created_at DESC, r.id DESC
  LIMIT 100;
$$;
REVOKE EXECUTE ON FUNCTION public.my_place_requests() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_place_requests() TO authenticated, service_role;

-- One request with everything the admin screens need.
CREATE FUNCTION public.admin_place_request_json(r public.place_requests)
  RETURNS jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'id', r.id, 'name', r.name, 'main_category', m.path::text, 'main_category_name', m.name,
    'address', r.address, 'city', r.city, 'state', r.state, 'postal_code', r.postal_code,
    'phone', r.phone, 'website', r.website, 'note', r.note,
    'lat', ST_Y(r.location::geometry), 'lng', ST_X(r.location::geometry),
    'status', r.status, 'entity_id', r.entity_id, 'decided_by', r.decided_by, 'decided_at', r.decided_at,
    'decision_note', r.decision_note, 'created_at', r.created_at,
    'requested_by', COALESCE(NULLIF(trim(p.display_name), ''), p.handle),
    'requested_by_handle', p.handle,
    'requests_by_this_person', (SELECT count(*) FROM place_requests o WHERE o.requested_by = r.requested_by),
    'possible_matches', (SELECT count(*) FROM admin_similar_places(ST_Y(r.location::geometry), ST_X(r.location::geometry), r.name, r.phone)))
  FROM categories m
  LEFT JOIN profiles p ON p.id = r.requested_by
  WHERE m.id = r.main_category_id;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_place_request_json(public.place_requests) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_place_request_json(public.place_requests) TO service_role;

CREATE FUNCTION public.admin_pending_place_requests()
  RETURNS SETOF jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT admin_place_request_json(r) FROM place_requests r WHERE r.status = 'pending' ORDER BY r.created_at, r.id;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_pending_place_requests() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pending_place_requests() TO service_role;

CREATE FUNCTION public.admin_get_place_request(p_id bigint)
  RETURNS jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT admin_place_request_json(r) FROM place_requests r WHERE r.id = p_id;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_get_place_request(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_place_request(bigint) TO service_role;

-- Locks a request and checks it is still waiting.
CREATE FUNCTION public.lock_pending_place_request(p_id bigint)
  RETURNS public.place_requests
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE r place_requests%ROWTYPE;
BEGIN
  SELECT * INTO r FROM place_requests WHERE id = p_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'request % does not exist', p_id; END IF;
  IF r.status <> 'pending' THEN RAISE EXCEPTION 'request % was already decided (%)', p_id, replace(r.status, '_', ' '); END IF;
  RETURN r;
END $$;
REVOKE EXECUTE ON FUNCTION public.lock_pending_place_request(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lock_pending_place_request(bigint) TO service_role;

-- Adds the requested place, with whatever the admin corrected. It becomes a place added
-- by hand (admin_add_place); its "added" ledger entry records the request it came from.
CREATE FUNCTION public.admin_approve_place_request(p_id bigint, p_values jsonb, p_decided_by text, p_note text DEFAULT NULL)
  RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE r place_requests%ROWTYPE; v_entity uuid;
BEGIN
  r := lock_pending_place_request(p_id);
  v_entity := admin_add_place(p_values, p_decided_by, COALESCE(NULLIF(trim(p_note), ''), 'from a place request'));
  UPDATE change_events SET evidence = evidence || jsonb_build_object('place_request', r.id)
  WHERE entity_id = v_entity AND event_type = 'new_candidate';
  UPDATE place_requests SET status = 'added', entity_id = v_entity, decided_by = p_decided_by, decided_at = now(),
                            decision_note = NULLIF(trim(p_note), '')
  WHERE id = r.id;
  RETURN v_entity;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_approve_place_request(bigint, jsonb, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_approve_place_request(bigint, jsonb, text, text) TO service_role;

-- We already have it. A merged place is followed to the place it was merged into.
CREATE FUNCTION public.admin_link_place_request(p_id bigint, p_entity uuid, p_decided_by text, p_note text DEFAULT NULL)
  RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE r place_requests%ROWTYPE; v_entity uuid; v_status text; v_into uuid;
BEGIN
  r := lock_pending_place_request(p_id);
  SELECT id, status, merged_into INTO v_entity, v_status, v_into FROM entities WHERE id = p_entity;
  IF v_entity IS NULL THEN RAISE EXCEPTION 'place % does not exist', p_entity; END IF;
  IF v_status = 'merged' THEN v_entity := v_into; END IF;
  IF v_status = 'removed' THEN RAISE EXCEPTION 'place % was removed', p_entity; END IF;
  UPDATE place_requests SET status = 'already_listed', entity_id = v_entity, decided_by = p_decided_by, decided_at = now(),
                            decision_note = NULLIF(trim(p_note), '')
  WHERE id = r.id;
  RETURN v_entity;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_link_place_request(bigint, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_link_place_request(bigint, uuid, text, text) TO service_role;

-- Declines waiting requests (already decided ones are left alone). Returns how many.
CREATE FUNCTION public.admin_decline_place_requests(p_ids bigint[], p_decided_by text, p_note text DEFAULT NULL)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_n integer;
BEGIN
  UPDATE place_requests SET status = 'declined', decided_by = p_decided_by, decided_at = now(),
                            decision_note = NULLIF(trim(p_note), '')
  WHERE id = ANY (p_ids) AND status = 'pending';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_decline_place_requests(bigint[], text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_decline_place_requests(bigint[], text, text) TO service_role;
