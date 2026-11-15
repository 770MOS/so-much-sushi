-- Fixing map pins by hand and from members' reports (agreed 2026-11-15).
--
-- A place's pin comes from whichever source Overture got it from (half of them Facebook
-- pages, where the business drops its own pin), so some sit beside the building or in the
-- parking lot. Pins fixed by people are kept like any hand edit: no source can move them
-- again, and the place's history says who placed them, when, and how they knew.
--
--   * Admins move a pin directly (admin page or the place panel): admin_move_pin.
--   * Members suggest a new spot: submit_pin_report. Reports wait in the review queue
--     ("Pin reports"), where an admin accepts (as sent or adjusted) or declines them.
--   * Everyone says how they know where the place is: they were there, or the business's own
--     website or sign, or something else (with a note). Not from another map or app: map
--     services' terms forbid making data from their maps, and our pins stay ours to share.
--   * How the pin was placed is kept with it: dragged on the map, or the phone's location
--     with the accuracy the phone reported.
--   * Safety net: a source that moves its own point for a hand-placed place more than 250 m
--     (the business may have moved) sends that to review instead of being ignored.
--
-- Coordinates are WGS 84 latitude and longitude, the same on every map, so pins placed
-- here show in the same spot on any map service.
--
-- For signed-in people (SECURITY DEFINER, authenticated only):
--   submit_pin_report(place, lat, lng, how, method, accuracy_m, note, agree)
--   my_pin_report(place)       their report for this place still waiting, if any
-- For the admin screens (service_role only):
--   admin_move_pin(place, lat, lng, how, method, accuracy_m, note, by)
--   admin_pending_pin_reports(), admin_get_pin_report(id),
--   admin_accept_pin_report(id, lat, lng, by, note), admin_decline_pin_reports(ids, by, note)
SET search_path = public, extensions;

CREATE TABLE public.pin_reports (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  entity_id         uuid NOT NULL REFERENCES public.entities(id),
  reported_by       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  -- The spot the member suggests, and where the pin was when they sent it.
  location          geography(Point, 4326) NOT NULL,
  previous_location geography(Point, 4326) NOT NULL,
  -- How they know: was_there, business (its own website or sign), other (see note).
  how               text NOT NULL CHECK (how IN ('was_there', 'business', 'other')),
  -- How the pin was placed: map (dragged or tapped) or gps (the phone's location).
  method            text NOT NULL CHECK (method IN ('map', 'gps')),
  accuracy_m        real CHECK (accuracy_m IS NULL OR accuracy_m >= 0),
  note              text,
  -- They agreed we may use, change and share the correction (the box on the form).
  agreed            boolean NOT NULL CHECK (agreed),
  status            text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'accepted', 'declined', 'superseded')),
  -- Where the pin was put on accepting (the suggested spot, or the admin's adjustment).
  applied_location  geography(Point, 4326),
  decided_by        text,
  decided_at        timestamptz,
  decision_note     text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pin_reports_decided_check CHECK ((status = 'pending') = (decided_at IS NULL)),
  CONSTRAINT pin_reports_applied_check CHECK ((status = 'accepted') = (applied_location IS NOT NULL)),
  CONSTRAINT pin_reports_other_note_check CHECK (how <> 'other' OR NULLIF(trim(note), '') IS NOT NULL)
);
CREATE INDEX pin_reports_pending_idx ON public.pin_reports (created_at) WHERE status = 'pending';
CREATE INDEX pin_reports_entity_idx ON public.pin_reports (entity_id) WHERE status = 'pending';
CREATE INDEX pin_reports_reported_by_idx ON public.pin_reports (reported_by, created_at);
-- One waiting report per person per place: sending again replaces it.
CREATE UNIQUE INDEX pin_reports_one_pending_idx ON public.pin_reports (entity_id, reported_by) WHERE status = 'pending';

ALTER TABLE public.pin_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pin_reports FROM anon, authenticated;
GRANT ALL ON public.pin_reports TO service_role;

-- A latitude and longitude as a point, checked to be in the United States (including Alaska,
-- Hawaii and Puerto Rico, as for places added by hand).
CREATE FUNCTION public.us_point(p_lat double precision, p_lng double precision)
  RETURNS geography
  LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
BEGIN
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RAISE EXCEPTION 'place the pin on the map';
  END IF;
  IF p_lat NOT BETWEEN 17 AND 72 OR p_lng NOT BETWEEN -180 AND -64 THEN
    RAISE EXCEPTION 'the pin is outside the United States';
  END IF;
  RETURN ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
END $$;
REVOKE EXECUTE ON FUNCTION public.us_point(double precision, double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.us_point(double precision, double precision) TO service_role;

-- Checks how someone knows and how the pin was placed, as the forms send them.
CREATE FUNCTION public.check_pin_details(p_how text, p_method text, p_accuracy real, p_note text)
  RETURNS void
  LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
BEGIN
  IF p_how IS NULL OR p_how NOT IN ('was_there', 'business', 'other') THEN
    RAISE EXCEPTION 'say how you know where the place is';
  END IF;
  IF p_how = 'other' AND NULLIF(trim(p_note), '') IS NULL THEN
    RAISE EXCEPTION 'add a note saying how you know where the place is';
  END IF;
  IF p_method IS NULL OR p_method NOT IN ('map', 'gps') THEN RAISE EXCEPTION 'unknown way of placing the pin'; END IF;
  IF p_method = 'map' AND p_accuracy IS NOT NULL THEN RAISE EXCEPTION 'accuracy is only kept for a phone location'; END IF;
  IF p_accuracy IS NOT NULL AND (p_accuracy < 0 OR p_accuracy > 10000) THEN RAISE EXCEPTION 'the accuracy is not valid'; END IF;
  IF length(COALESCE(p_note, '')) > 500 THEN RAISE EXCEPTION 'the note is too long'; END IF;
END $$;
REVOKE EXECUTE ON FUNCTION public.check_pin_details(text, text, real, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_pin_details(text, text, real, text) TO service_role;

CREATE FUNCTION public.point_json(p_loc geography)
  RETURNS jsonb
  LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
  SELECT CASE WHEN p_loc IS NULL THEN NULL
              ELSE jsonb_build_object('lat', ST_Y(p_loc::geometry), 'lng', ST_X(p_loc::geometry)) END;
$$;
REVOKE EXECUTE ON FUNCTION public.point_json(geography) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.point_json(geography) TO service_role;

-- Puts a place's pin where a person placed it, for good: the location now comes from
-- p_source_code with p_method ('manual' or 'user_report'), so no source can move it, and
-- pending source proposals to move it are closed. One ledger entry records the move with
-- p_evidence. Returns how far the pin moved, in meters.
CREATE FUNCTION public.set_hand_pin(p_entity uuid, p_loc geography, p_source_code text, p_method text,
                                    p_event_type text, p_evidence jsonb, p_decided_by text)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v entities%ROWTYPE; v_src smallint; v_lic text; v_dist double precision;
BEGIN
  SELECT * INTO v FROM entities WHERE id = p_entity FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'place % not found', p_entity; END IF;
  IF v.status = 'merged' THEN RAISE EXCEPTION 'this place was merged into another; move the pin on that one'; END IF;
  SELECT id, license INTO v_src, v_lic FROM sources WHERE code = p_source_code;
  IF v_src IS NULL THEN RAISE EXCEPTION 'source % is missing', p_source_code; END IF;
  v_dist := ST_Distance(v.location, p_loc);
  IF v_dist < 0.5 THEN RAISE EXCEPTION 'the pin is already there'; END IF;

  UPDATE entities SET location = p_loc WHERE id = p_entity;
  INSERT INTO entity_field_provenance (entity_id, field, source_id, source_record_pk, license, method, set_at)
  VALUES (p_entity, 'location', v_src, NULL, v_lic, p_method, now())
  ON CONFLICT (entity_id, field) DO UPDATE
    SET source_id = EXCLUDED.source_id, source_record_pk = NULL, license = EXCLUDED.license,
        method = EXCLUDED.method, set_at = now();

  INSERT INTO change_events (event_type, entity_id, source_id, field, old_value, new_value, evidence,
                             status, decided_by, decided_at, applied_at)
  VALUES (p_event_type, p_entity, v_src, 'location', point_json(v.location), point_json(p_loc),
          jsonb_strip_nulls(p_evidence || jsonb_build_object('distance_m', round(v_dist))),
          'approved', p_decided_by, now(), now());

  UPDATE change_events SET status = 'superseded', decided_by = p_decided_by, decided_at = now()
  WHERE entity_id = p_entity AND status = 'pending' AND event_type = 'attribute_change' AND field = 'location';
  RETURN round(v_dist);
END $$;
REVOKE EXECUTE ON FUNCTION public.set_hand_pin(uuid, geography, text, text, text, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_hand_pin(uuid, geography, text, text, text, jsonb, text) TO service_role;

-- An admin moves a pin (place page or place panel). It counts as an edit by hand, and so as
-- checking the place. Returns how far the pin moved, in meters.
CREATE FUNCTION public.admin_move_pin(p_id uuid, p_lat double precision, p_lng double precision, p_how text,
                                      p_method text, p_accuracy real, p_note text, p_decided_by text)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_loc geography;
BEGIN
  v_loc := us_point(p_lat, p_lng);
  PERFORM check_pin_details(p_how, p_method, p_accuracy, p_note);
  RETURN set_hand_pin(p_id, v_loc, 'manual_research', 'manual', 'manual_edit',
    jsonb_build_object('how', p_how, 'method', p_method, 'accuracy_m', round(p_accuracy::numeric),
                       'note', NULLIF(trim(p_note), '')),
    p_decided_by);
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_move_pin(uuid, double precision, double precision, text, text, real, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_move_pin(uuid, double precision, double precision, text, text, real, text, text) TO service_role;

-- A member suggests a new spot for a place's pin. Sending again for the same place replaces
-- their waiting report. Returns the report's id.
CREATE FUNCTION public.submit_pin_report(p_place uuid, p_lat double precision, p_lng double precision, p_how text,
                                         p_method text, p_accuracy real, p_note text, p_agree boolean)
  RETURNS bigint
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_user uuid := auth.uid();
  v_loc geography; v_cur geography; v_status text; v_dist double precision; v_id bigint;
  v_limit constant integer := 50;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'sign in to suggest a new spot'; END IF;
  SELECT location, status INTO v_cur, v_status FROM entities WHERE id = p_place;
  IF v_cur IS NULL OR v_status IN ('merged', 'removed') THEN RAISE EXCEPTION 'this place is no longer listed'; END IF;
  v_loc := us_point(p_lat, p_lng);
  PERFORM check_pin_details(p_how, p_method, p_accuracy, p_note);
  IF p_agree IS DISTINCT FROM true THEN RAISE EXCEPTION 'tick the box to let us use your correction'; END IF;

  v_dist := ST_Distance(v_cur, v_loc);
  IF v_dist < 3 THEN RAISE EXCEPTION 'that is where the pin already is'; END IF;
  IF v_dist > 2000 THEN
    RAISE EXCEPTION 'that is more than 2 km from where we show it; if the place has moved, request it as a new place';
  END IF;

  SELECT id INTO v_id FROM pin_reports WHERE entity_id = p_place AND reported_by = v_user AND status = 'pending' FOR UPDATE;
  IF v_id IS NULL AND (SELECT count(*) FROM pin_reports WHERE reported_by = v_user AND created_at > now() - interval '1 day') >= v_limit THEN
    RAISE EXCEPTION 'you have sent % pin corrections in the last day; please try again tomorrow', v_limit;
  END IF;

  IF v_id IS NOT NULL THEN
    UPDATE pin_reports SET location = v_loc, previous_location = v_cur, how = p_how, method = p_method,
                           accuracy_m = p_accuracy, note = NULLIF(trim(p_note), ''), agreed = true, created_at = now()
    WHERE id = v_id;
  ELSE
    INSERT INTO pin_reports (entity_id, reported_by, location, previous_location, how, method, accuracy_m, note, agreed)
    VALUES (p_place, v_user, v_loc, v_cur, p_how, p_method, p_accuracy, NULLIF(trim(p_note), ''), true)
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.submit_pin_report(uuid, double precision, double precision, text, text, real, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_pin_report(uuid, double precision, double precision, text, text, real, text, boolean) TO authenticated, service_role;

-- The signed-in person's report for this place that is still waiting, or null.
CREATE FUNCTION public.my_pin_report(p_place uuid)
  RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT jsonb_build_object('id', r.id, 'lat', ST_Y(r.location::geometry), 'lng', ST_X(r.location::geometry),
                            'created_at', r.created_at)
  FROM pin_reports r
  WHERE r.entity_id = p_place AND r.reported_by = auth.uid() AND r.status = 'pending';
$$;
REVOKE EXECUTE ON FUNCTION public.my_pin_report(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_pin_report(uuid) TO authenticated, service_role;

-- One report with everything the admin screens need: the place as it is now (following a
-- merge), where its pin came from, who sent the report and their record, and the other
-- reports waiting for the same place (several people agreeing is a good sign).
CREATE FUNCTION public.admin_pin_report_json(r public.pin_reports)
  RETURNS jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'id', r.id, 'status', r.status, 'how', r.how, 'method', r.method, 'accuracy_m', r.accuracy_m, 'note', r.note,
    'lat', ST_Y(r.location::geometry), 'lng', ST_X(r.location::geometry),
    'previous', point_json(r.previous_location), 'applied', point_json(r.applied_location),
    'distance_m', round(ST_Distance(e.location, r.location)),
    'created_at', r.created_at, 'decided_by', r.decided_by, 'decided_at', r.decided_at, 'decision_note', r.decision_note,
    'place', jsonb_build_object(
      'id', e.id, 'name', e.name, 'address', e.address, 'city', e.city, 'state', e.state, 'status', e.status,
      'lat', ST_Y(e.location::geometry), 'lng', ST_X(e.location::geometry),
      'pin_method', lp.method, 'pin_source', ls.name,
      'pin_contributor', (SELECT sr.upstream_dataset FROM source_records sr WHERE sr.id = lp.source_record_pk)),
    'reported_by', COALESCE(NULLIF(trim(p.display_name), ''), p.handle),
    'reported_by_handle', p.handle,
    'reports_by_this_person', (SELECT count(*) FROM pin_reports o WHERE o.reported_by = r.reported_by),
    'accepted_from_this_person', (SELECT count(*) FROM pin_reports o WHERE o.reported_by = r.reported_by AND o.status = 'accepted'),
    'others', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'lat', ST_Y(o.location::geometry), 'lng', ST_X(o.location::geometry),
                                                            'meters_from_this', round(ST_Distance(o.location, r.location)))
                                         ORDER BY o.created_at)
                        FROM pin_reports o
                        WHERE o.status = 'pending' AND o.id <> r.id AND resolve_entity(o.entity_id) = e.id), '[]'::jsonb))
  FROM entities e
  LEFT JOIN entity_field_provenance lp ON lp.entity_id = e.id AND lp.field = 'location'
  LEFT JOIN sources ls ON ls.id = lp.source_id
  LEFT JOIN profiles p ON p.id = r.reported_by
  WHERE e.id = resolve_entity(r.entity_id);
$$;
REVOKE EXECUTE ON FUNCTION public.admin_pin_report_json(public.pin_reports) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pin_report_json(public.pin_reports) TO service_role;

CREATE FUNCTION public.admin_pending_pin_reports()
  RETURNS SETOF jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT admin_pin_report_json(r) FROM pin_reports r WHERE r.status = 'pending' ORDER BY r.created_at, r.id;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_pending_pin_reports() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pending_pin_reports() TO service_role;

CREATE FUNCTION public.admin_get_pin_report(p_id bigint)
  RETURNS jsonb
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT admin_pin_report_json(r) FROM pin_reports r WHERE r.id = p_id;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_get_pin_report(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pin_report(bigint) TO service_role;

-- Accepts a report: the pin goes to the suggested spot, or to p_lat/p_lng if the admin
-- adjusted it. As sent, the location is credited to the member's report; adjusted, to our
-- own placement. Other reports waiting for the same place are closed with it. Returns how
-- far the pin moved, in meters.
CREATE FUNCTION public.admin_accept_pin_report(p_id bigint, p_lat double precision, p_lng double precision,
                                               p_decided_by text, p_note text DEFAULT NULL)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE r pin_reports%ROWTYPE; v_entity uuid; v_loc geography; v_adjusted boolean; v_moved integer;
BEGIN
  SELECT * INTO r FROM pin_reports WHERE id = p_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'pin report % does not exist', p_id; END IF;
  IF r.status <> 'pending' THEN RAISE EXCEPTION 'pin report % was already decided (%)', p_id, r.status; END IF;
  v_entity := resolve_entity(r.entity_id);
  IF (SELECT status FROM entities WHERE id = v_entity) = 'removed' THEN RAISE EXCEPTION 'this place was removed'; END IF;
  v_loc := CASE WHEN p_lat IS NULL AND p_lng IS NULL THEN r.location ELSE us_point(p_lat, p_lng) END;
  v_adjusted := ST_Distance(v_loc, r.location) >= 0.5;

  v_moved := set_hand_pin(v_entity, v_loc,
    CASE WHEN v_adjusted THEN 'manual_research' ELSE 'user_report' END,
    CASE WHEN v_adjusted THEN 'manual' ELSE 'user_report' END,
    'user_report',
    jsonb_build_object('pin_report', r.id, 'how', r.how, 'method', r.method, 'accuracy_m', round(r.accuracy_m::numeric),
                       'adjusted', v_adjusted, 'note', NULLIF(trim(p_note), '')),
    p_decided_by);

  UPDATE pin_reports SET status = 'accepted', applied_location = v_loc, decided_by = p_decided_by, decided_at = now(),
                         decision_note = NULLIF(trim(p_note), '')
  WHERE id = r.id;
  UPDATE pin_reports SET status = 'superseded', decided_by = p_decided_by, decided_at = now(),
                         decision_note = 'pin set from report ' || r.id
  WHERE status = 'pending' AND id <> r.id AND resolve_entity(entity_id) = v_entity;
  RETURN v_moved;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_accept_pin_report(bigint, double precision, double precision, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_accept_pin_report(bigint, double precision, double precision, text, text) TO service_role;

-- Declines waiting reports (already decided ones are left alone). Returns how many.
CREATE FUNCTION public.admin_decline_pin_reports(p_ids bigint[], p_decided_by text, p_note text DEFAULT NULL)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_n integer;
BEGIN
  UPDATE pin_reports SET status = 'declined', decided_by = p_decided_by, decided_at = now(),
                         decision_note = NULLIF(trim(p_note), '')
  WHERE id = ANY (p_ids) AND status = 'pending';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_decline_pin_reports(bigint[], text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_decline_pin_reports(bigint[], text, text) TO service_role;

-- The safety net, in the source loads (reconcile_run as in 20261022000000, with one addition
-- in part a): a pin placed by hand or from a report never follows a source, but when a source
-- moves its own point for that place more than 250 m, the move is proposed for review.
CREATE OR REPLACE FUNCTION public.reconcile_run(p_run_id bigint, p_decided_by text)
  RETURNS jsonb
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE
  v_run source_runs%ROWTYPE; v_code text; v_class text; v_verify boolean;
  v_started timestamptz := now();  -- transaction start: places built in this call carry this created_at
  r record; f text; v_res text; v_dist double precision; v_attached integer := 0; v_build jsonb; v_n integer;
  s_auto integer := 0; s_proposed integer := 0; s_closures integer := 0; s_absent integer := 0; s_dupes integer := 0;
BEGIN
  SELECT * INTO v_run FROM source_runs WHERE id = p_run_id;
  IF v_run.id IS NULL OR v_run.status <> 'succeeded' THEN
    RAISE EXCEPTION 'run % does not exist or has not succeeded', p_run_id;
  END IF;
  PERFORM record_in_scope(v_run.scope, NULL, NULL);  -- rejects an unknown scope early
  SELECT code, license_class INTO v_code, v_class FROM sources WHERE id = v_run.source_id;
  v_verify := v_class = 'verify_only';
  IF v_class = 'share_alike' THEN RAISE EXCEPTION 'source % is share-alike and must not be reconciled', v_code; END IF;

  -- a. Records on a place whose values changed in this load.
  FOR r IN
    SELECT sr.id, sr.entity_id, sr.prev_values AS old, sr.location,
           source_record_values(sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website,
                                sr.location, sr.category_id, sr.payload) AS new,
           e.status AS entity_status,
           EXISTS (SELECT 1 FROM entity_field_provenance lp WHERE lp.entity_id = sr.entity_id
                     AND lp.field = 'location' AND lp.source_record_pk = sr.id) AS is_location_record,
           (SELECT lp.method FROM entity_field_provenance lp WHERE lp.entity_id = sr.entity_id
              AND lp.field = 'location') AS location_method
    FROM source_records sr JOIN entities e ON e.id = sr.entity_id
    WHERE sr.source_id = v_run.source_id AND sr.changed_run = p_run_id AND sr.prev_values IS NOT NULL
      AND e.status NOT IN ('merged', 'removed')
  LOOP
    IF NOT v_verify THEN
      FOREACH f IN ARRAY ARRAY['name', 'address', 'city', 'state', 'postal_code', 'phone', 'website'] LOOP
        CONTINUE WHEN (r.old->>f) IS NOT DISTINCT FROM (r.new->>f);
        v_res := reconcile_field(r.entity_id, r.id, p_run_id, f, r.old->>f, r.new->>f, false, p_decided_by);
        IF v_res = 'auto' THEN s_auto := s_auto + 1; ELSIF v_res = 'proposed' THEN s_proposed := s_proposed + 1; END IF;
      END LOOP;

      -- Only the record the location came from can move the place.
      IF r.is_location_record AND r.location IS NOT NULL
         AND (r.old->>'lat', r.old->>'lng') IS DISTINCT FROM (r.new->>'lat', r.new->>'lng') THEN
        SELECT ST_Distance(e.location, r.location) INTO v_dist FROM entities e WHERE e.id = r.entity_id;
        IF v_dist > 0 AND v_dist <= 250 THEN
          UPDATE entities SET location = r.location WHERE id = r.entity_id;
          INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, run_id, field, old_value, new_value,
                                     evidence, status, decided_by, decided_at, applied_at)
          VALUES ('attribute_change', r.entity_id, v_run.source_id, r.id, p_run_id, 'location',
                  jsonb_build_object('lat', r.old->'lat', 'lng', r.old->'lng'),
                  jsonb_build_object('lat', r.new->'lat', 'lng', r.new->'lng'),
                  jsonb_build_object('reason', 'source moved the point', 'distance_m', round(v_dist)),
                  'auto_applied', p_decided_by, now(), now());
          s_auto := s_auto + 1;
        ELSIF v_dist > 250 THEN
          PERFORM propose_change('attribute_change', r.entity_id, v_run.source_id, r.id, p_run_id, 'location',
            jsonb_build_object('lat', r.old->'lat', 'lng', r.old->'lng'),
            jsonb_build_object('lat', r.new->'lat', 'lng', r.new->'lng'),
            jsonb_build_object('reason', 'the source moved this place more than 250 m', 'distance_m', round(v_dist)));
          s_proposed := s_proposed + 1;
        END IF;
      END IF;

      -- A pin placed by hand or from a member's report never follows a source, but a source
      -- moving its own point more than 250 m may mean the business moved: that goes to review.
      IF r.location_method IN ('manual', 'user_report') AND r.location IS NOT NULL
         AND (r.old->>'lat') IS NOT NULL AND (r.old->>'lng') IS NOT NULL THEN
        v_dist := ST_Distance(ST_SetSRID(ST_MakePoint((r.old->>'lng')::double precision,
                                                      (r.old->>'lat')::double precision), 4326)::geography, r.location);
        IF v_dist > 250 THEN
          PERFORM propose_change('attribute_change', r.entity_id, v_run.source_id, r.id, p_run_id, 'location',
            (SELECT point_json(e.location) FROM entities e WHERE e.id = r.entity_id),
            jsonb_build_object('lat', r.new->'lat', 'lng', r.new->'lng'),
            jsonb_build_object('reason', 'the pin was placed by hand, and the source moved this place more than 250 m',
                               'distance_m', round(v_dist)));
          s_proposed := s_proposed + 1;
        END IF;
      END IF;
    END IF;

    -- Opening status: always proposed, from any source trusted for it (verify-only included).
    IF (r.old->>'operating_status') IS DISTINCT FROM (r.new->>'operating_status')
       AND (v_verify OR source_trust(v_run.source_id, 'status') > 0) THEN
      IF r.new->>'operating_status' IN ('permanently_closed', 'temporarily_closed') AND r.entity_status = 'active' THEN
        PERFORM propose_change('closure_signal', r.entity_id, v_run.source_id, r.id, p_run_id, 'status',
          to_jsonb(r.entity_status), to_jsonb(r.new->>'operating_status'),
          jsonb_build_object('reason', v_code || ' now marks this place ' || replace(r.new->>'operating_status', '_', ' ')));
        s_closures := s_closures + 1;
      ELSIF COALESCE(r.new->>'operating_status', 'open') = 'open' AND r.entity_status IN ('permanently_closed', 'temporarily_closed') THEN
        PERFORM propose_change('status_change', r.entity_id, v_run.source_id, r.id, p_run_id, 'status',
          to_jsonb(r.entity_status), to_jsonb('active'::text),
          jsonb_build_object('reason', v_code || ' now marks this place open'));
        s_closures := s_closures + 1;
      END IF;
    END IF;
  END LOOP;

  -- b. Records missing from the last 2 runs of this source over the same area.
  FOR r IN
    SELECT sr.id, sr.entity_id, sr.last_seen_run, e.status AS entity_status, lr.release AS last_release,
           (SELECT count(*) FROM source_runs x
            WHERE x.source_id = v_run.source_id AND x.scope = v_run.scope AND x.status = 'succeeded'
              AND x.id > sr.last_seen_run AND x.id <= p_run_id) AS missed
    FROM source_records sr
    JOIN entities e ON e.id = sr.entity_id
    LEFT JOIN source_runs lr ON lr.id = sr.last_seen_run
    WHERE sr.source_id = v_run.source_id AND sr.last_seen_run < p_run_id
      AND e.status IN ('active', 'temporarily_closed')
      AND record_in_scope(v_run.scope, sr.location, sr.state)
  LOOP
    CONTINUE WHEN r.missed < 2;
    -- Any record of this place, from any source, seen recently keeps it listed.
    CONTINUE WHEN EXISTS (SELECT 1 FROM source_records o JOIN source_runs orun ON orun.id = o.last_seen_run
                          WHERE o.entity_id = r.entity_id AND o.id <> r.id AND orun.status = 'succeeded'
                            AND COALESCE(orun.finished_at, orun.started_at) >= now() - interval '45 days');
    CONTINUE WHEN EXISTS (SELECT 1 FROM change_events c WHERE c.entity_id = r.entity_id AND c.event_type = 'absent'
                            AND (c.status = 'pending' OR (c.status = 'rejected' AND c.source_record_pk = r.id
                                 AND (c.evidence->>'last_seen_run')::bigint = r.last_seen_run)));
    INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, run_id, field, old_value, new_value, evidence)
    VALUES ('absent', r.entity_id, v_run.source_id, r.id, p_run_id, 'status', to_jsonb(r.entity_status),
            to_jsonb('permanently_closed'::text),
            jsonb_build_object('reason', 'missing from the last ' || r.missed || ' loads of ' || v_code || ' for this area',
                               'missed_runs', r.missed, 'last_seen_release', r.last_release, 'last_seen_run', r.last_seen_run));
    s_absent := s_absent + 1;
  END LOOP;

  -- c. New records: attach to a place we already have on strong evidence.
  --    Rule 1: matching name (similar, or the chain's brand) within 75 m, plus the same phone,
  --            or the same website page with no conflicting phone.
  --    Rule 2: the identical name within 25 m, where neither phone nor website conflicts,
  --            only one place nearby has that name, and the place has no record from this
  --            source yet (two records of one chain at one spot are two locations).
  FOR r IN
    SELECT DISTINCT ON (sr.id) sr.id, e.id AS entity_id, m.rule,
           source_record_values(sr.name, sr.address, sr.city, sr.state, sr.postal_code, sr.phone, sr.website,
                                sr.location, sr.category_id, sr.payload) AS new
    FROM source_records sr
    JOIN entities e ON ST_DWithin(e.location, sr.location, 75)
    CROSS JOIN LATERAL (SELECT CASE
        WHEN names_match(sr.name, sr.payload->>'brand', e.name)
             AND (match_phone(sr.phone) = match_phone(e.phone)
                  OR (match_url(sr.website) = match_url(e.website)
                      AND NOT COALESCE(match_phone(sr.phone) <> match_phone(e.phone), false)))
          THEN 1
        WHEN same_name_same_spot(sr.name, sr.phone, sr.website, sr.location, e.name, e.phone, e.website, e.location)
             AND NOT EXISTS (SELECT 1 FROM source_records o WHERE o.entity_id = e.id AND o.source_id = v_run.source_id)
             AND NOT EXISTS (SELECT 1 FROM entities e2 WHERE e2.id <> e.id AND e2.status NOT IN ('merged', 'removed')
                               AND e2.created_at < v_started AND ST_DWithin(e2.location, sr.location, 25)
                               AND match_name(e2.name) = match_name(sr.name))
          THEN 2 END AS rule) m
    WHERE sr.source_id = v_run.source_id AND sr.first_seen_run = p_run_id AND sr.match_status = 'unmatched'
      AND sr.location IS NOT NULL AND NOT is_legal_entity_name(sr.name)
      AND e.status NOT IN ('merged', 'removed') AND e.created_at < v_started
      AND m.rule IS NOT NULL
    ORDER BY sr.id, m.rule, ST_Distance(e.location, sr.location)
  LOOP
    -- Rule 2 is checked again here: an earlier record in this same load may have just
    -- taken the place.
    CONTINUE WHEN r.rule = 2 AND EXISTS (SELECT 1 FROM source_records o
                                         WHERE o.entity_id = r.entity_id AND o.source_id = v_run.source_id);
    UPDATE source_records SET entity_id = r.entity_id, match_status = 'auto', matched_at = now(),
                              match_method = CASE r.rule WHEN 1 THEN 'auto: matched existing place'
                                                         ELSE 'auto: same name, same spot' END
    WHERE id = r.id;
    v_attached := v_attached + 1;
    -- A second source fills gaps and, where it ranks higher and disagrees, proposes.
    IF NOT v_verify THEN
      FOREACH f IN ARRAY ARRAY['name', 'address', 'city', 'state', 'postal_code', 'phone', 'website'] LOOP
        v_res := reconcile_field(r.entity_id, r.id, p_run_id, f, NULL, r.new->>f, true, p_decided_by);
        IF v_res = 'auto' THEN s_auto := s_auto + 1; ELSIF v_res = 'proposed' THEN s_proposed := s_proposed + 1; END IF;
      END LOOP;
    END IF;
  END LOOP;

  -- New places from what is left. Verify-only sources never create places.
  IF NOT v_verify AND EXISTS (SELECT 1 FROM source_records WHERE source_id = v_run.source_id
        AND (match_status = 'unmatched' OR (match_status = 'needs_review' AND match_method = 'legal entity name'))) THEN
    v_build := build_entities_from_source(v_code, p_decided_by);
  END IF;

  -- New places that look like an existing one become possible-duplicate proposals.
  INSERT INTO change_events (event_type, entity_id, source_id, source_record_pk, run_id, old_value, new_value, evidence)
  SELECT DISTINCT ON (n.id) 'merge', old.id, v_run.source_id, sr.id, p_run_id,
         jsonb_build_object('duplicate', n.id), jsonb_build_object('survivor', old.id),
         jsonb_build_object('proposed_by', p_decided_by, 'distance_m', round(ST_Distance(old.location, n.location)),
                            'name_similarity', round(similarity(match_name(n.name), match_name(old.name))::numeric, 2),
                            'same_phone', match_phone(n.phone) = match_phone(old.phone),
                            'phone_conflict', match_phone(n.phone) <> match_phone(old.phone),
                            'same_website', match_url(n.website) = match_url(old.website),
                            'website_conflict', match_host(n.website) <> match_host(old.website),
                            'name_a', old.name, 'name_b', n.name, 'reason', 'new in this load, near a very similar existing place')
  FROM source_records sr
  JOIN entities n ON n.id = sr.entity_id AND n.created_at >= v_started
  JOIN entities old ON ST_DWithin(old.location, n.location, 75) AND old.created_at < v_started
                   AND old.status NOT IN ('merged', 'removed')
                   AND names_match(n.name, sr.payload->>'brand', old.name)
  WHERE sr.source_id = v_run.source_id AND sr.first_seen_run = p_run_id
    AND NOT EXISTS (SELECT 1 FROM change_events c WHERE c.event_type = 'merge' AND c.status = 'pending'
                      AND c.entity_id = old.id AND c.old_value->>'duplicate' = n.id::text)
  ORDER BY n.id, ST_Distance(old.location, n.location);
  GET DIAGNOSTICS s_dupes = ROW_COUNT;

  v_n := (SELECT count(*) FROM source_records WHERE source_id = v_run.source_id AND first_seen_run = p_run_id);
  UPDATE source_runs SET stats = stats || jsonb_build_object('reconcile', jsonb_build_object(
      'source', v_code, 'verify_only', v_verify,
      'new_records', v_n, 'attached_to_existing_places', v_attached, 'build', v_build,
      'unmatched_records', (SELECT count(*) FROM source_records WHERE source_id = v_run.source_id AND match_status = 'unmatched'),
      'possible_duplicates_of_existing', s_dupes, 'values_updated_automatically', s_auto,
      'value_changes_for_review', s_proposed, 'status_changes_for_review', s_closures,
      'missing_for_review', s_absent, 'finished_at', now()))
  WHERE id = p_run_id;
  RETURN (SELECT stats->'reconcile' FROM source_runs WHERE id = p_run_id);
END $$;
