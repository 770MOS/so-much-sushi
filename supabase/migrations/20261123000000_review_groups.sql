-- Review queue at national scale: groups of proposals decided together or one by one.
--
-- On production 2026-11-20: 23,070 possible duplicates and 9,500 suggested changes waiting,
-- all from the national load, and the queue loaded every one of them on each visit (about
-- 1.7 s in the database before the page drew 32,000 rows). Most fall into a few kinds:
-- All the Places' Qdoba feed lists each store once per page of its website (5,677 places for
-- 891 addresses), same-name places from two sources, store pages for websites, addresses that
-- differ only in spelling, states wrong at state lines.
--
-- Decided 2026-11-20 (Johnny): no new automatic rule; the queue sorts proposals into groups
-- with a count, a recommendation and examples; each group can be accepted or declined as a
-- whole or item by item (the one-pair screen stays for any duplicate).
--
--   * change_events.review_group, set by classify_review_items() for pending merges and
--     source changes (tag suggestions keep their own tab). Groups:
--       dup_feed_same      both places from the same All the Places feed, same name and address
--       dup_feed_variant   the same feed, name or address differs
--       dup_name_near      same name, within 25 m
--       dup_name_far       same name, 25-75 m apart
--       dup_variant        names differ (brand variants, branch names)
--       chg_website        websites
--       chg_address_same   addresses with the same house number
--       chg_address_other  other addresses
--       chg_state_theirs   states: the town is a Census place in the proposed state, not ours
--       chg_state_ours     states: the town is a Census place in our state, not the proposed one
--       chg_state_unclear  states: the town list can't tell
--       chg_name           names
--       chg_other          phones, ZIP codes, towns, pins
--       chg_status         closures, reopenings and places missing from loads
--   * admin_review_groups(): counts and three examples per group (classifies new proposals
--     first). admin_review_duplicates / admin_review_changes: one group, a page at a time.
--     admin_get_merge_proposal: one duplicate pair. admin_decide_review_group: the next batch
--     of a group (the page repeats it with a progress count until the group is done).
SET search_path = public, extensions;

ALTER TABLE public.change_events ADD COLUMN review_group text;
CREATE INDEX change_events_review_group_idx ON public.change_events (review_group, id) WHERE status = 'pending';

-- ---------------------------------------------------------------- sorting into groups
CREATE FUNCTION public.classify_review_items()
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_atp smallint; v_n integer; v_m integer;
BEGIN
  SELECT id INTO v_atp FROM sources WHERE code = 'alltheplaces';

  WITH m AS (
    SELECT c.id, a.name AS a_name, b.name AS b_name, a.address AS a_addr, b.address AS b_addr,
           (c.evidence->>'name_similarity')::numeric AS sim, (c.evidence->>'distance_m')::numeric AS dist,
           EXISTS (SELECT 1 FROM source_records ra
                   JOIN source_records rb ON rb.source_id = ra.source_id AND rb.upstream_dataset = ra.upstream_dataset
                   WHERE ra.entity_id = a.id AND rb.entity_id = b.id AND ra.source_id = v_atp) AS same_feed
    FROM change_events c
    JOIN entities a ON a.id = c.entity_id
    JOIN entities b ON b.id = (c.old_value->>'duplicate')::uuid
    WHERE c.status = 'pending' AND c.event_type = 'merge' AND c.review_group IS NULL)
  UPDATE change_events c SET review_group = CASE
      WHEN m.same_feed THEN
        CASE WHEN m.sim >= 1
                  AND regexp_replace(lower(COALESCE(m.a_addr, '')), '[^a-z0-9]', '', 'g')
                    = regexp_replace(lower(COALESCE(m.b_addr, '')), '[^a-z0-9]', '', 'g')
             THEN 'dup_feed_same' ELSE 'dup_feed_variant' END
      WHEN m.sim >= 1 AND m.dist <= 25 THEN 'dup_name_near'
      WHEN m.sim >= 1 THEN 'dup_name_far'
      ELSE 'dup_variant' END
  FROM m WHERE c.id = m.id;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  WITH s AS (
    SELECT c.id, c.event_type, c.field, e.address, e.city, e.state, c.new_value #>> '{}' AS proposed
    FROM change_events c JOIN entities e ON e.id = c.entity_id
    WHERE c.status = 'pending' AND c.review_group IS NULL
      AND (c.event_type IN ('closure_signal', 'status_change', 'absent')
           OR (c.event_type = 'attribute_change' AND c.field IS DISTINCT FROM 'categories')))
  UPDATE change_events c SET review_group = CASE
      WHEN s.event_type <> 'attribute_change' THEN 'chg_status'
      WHEN s.field = 'website' THEN 'chg_website'
      WHEN s.field = 'address' THEN
        CASE WHEN substring(s.address FROM '^\s*(\d+)') = substring(s.proposed FROM '^\s*(\d+)')
             THEN 'chg_address_same' ELSE 'chg_address_other' END
      WHEN s.field = 'state' THEN (
        SELECT CASE WHEN bool_or(l.state = s.proposed) AND NOT bool_or(l.state = s.state) THEN 'chg_state_theirs'
                    WHEN bool_or(l.state = s.state) AND NOT bool_or(l.state = s.proposed) THEN 'chg_state_ours'
                    ELSE 'chg_state_unclear' END
        FROM locality_names n JOIN localities l ON l.id = n.locality_id
        WHERE l.kind = 'place' AND n.name_norm = locality_normalize(s.city) AND l.state IN (s.state, s.proposed))
      WHEN s.field = 'name' THEN 'chg_name'
      ELSE 'chg_other' END
  FROM s WHERE c.id = s.id;
  GET DIAGNOSTICS v_m = ROW_COUNT;
  RETURN v_n + v_m;
END $$;

-- ---------------------------------------------------------------- the group list
CREATE FUNCTION public.admin_review_groups()
  RETURNS TABLE(review_group text, kind text, items bigint, examples jsonb)
  LANGUAGE plpgsql VOLATILE SET search_path = public, extensions AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM change_events c WHERE c.status = 'pending' AND c.review_group IS NULL
               AND (c.event_type IN ('merge', 'closure_signal', 'status_change', 'absent')
                    OR (c.event_type = 'attribute_change' AND c.field IS DISTINCT FROM 'categories'))) THEN
    PERFORM classify_review_items();
  END IF;
  RETURN QUERY
  SELECT g.review_group, CASE WHEN g.review_group LIKE 'dup\_%' THEN 'duplicates' ELSE 'changes' END, g.n,
         (SELECT COALESCE(jsonb_agg(x.t), '[]') FROM (
            SELECT CASE WHEN c.event_type = 'merge'
                        THEN a.name || ' / ' || b.name || ' · ' || COALESCE(c.evidence->>'distance_m', '?') || ' m · ' || COALESCE(a.city || ', ' || a.state, a.state, '')
                        WHEN c.event_type = 'attribute_change'
                        THEN a.name || ' · ' || COALESCE(to_jsonb(a) ->> c.field, '(none)') || ' → ' || COALESCE(c.new_value #>> '{}', '(none)')
                        ELSE a.name || ' · ' || replace(c.event_type, '_', ' ') END AS t
            FROM change_events c
            JOIN entities a ON a.id = c.entity_id
            LEFT JOIN entities b ON b.id = (c.old_value->>'duplicate')::uuid
            WHERE c.status = 'pending' AND c.review_group = g.review_group
            ORDER BY c.id LIMIT 3) x)
  FROM (SELECT c.review_group, count(*) AS n FROM change_events c
        WHERE c.status = 'pending' AND c.review_group IS NOT NULL GROUP BY 1) g;
END $$;

-- ---------------------------------------------------------------- one group, a page at a time
CREATE FUNCTION public.admin_review_duplicates(p_group text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
  RETURNS TABLE(event_id bigint, created_at timestamptz,
                a_id uuid, a_name text, a_address text, a_city text, a_state text, a_phone text, a_website text, a_status text,
                b_id uuid, b_name text, b_address text, b_city text, b_state text, b_phone text, b_website text, b_status text,
                distance_m integer, name_similarity numeric, same_phone boolean, same_website boolean, total bigint)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT c.id, c.created_at,
         a.id, a.name, a.address, a.city, a.state, a.phone, a.website, a.status,
         b.id, b.name, b.address, b.city, b.state, b.phone, b.website, b.status,
         (c.evidence->>'distance_m')::integer, (c.evidence->>'name_similarity')::numeric,
         (c.evidence->>'same_phone')::boolean, (c.evidence->>'same_website')::boolean,
         count(*) OVER ()
  FROM change_events c
  JOIN entities a ON a.id = c.entity_id
  JOIN entities b ON b.id = (c.old_value->>'duplicate')::uuid
  WHERE c.status = 'pending' AND c.event_type = 'merge' AND c.review_group = p_group
  ORDER BY a.name, a.state, a.city, c.id
  LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0);
$$;

CREATE FUNCTION public.admin_review_changes(p_group text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
  RETURNS TABLE(event_id bigint, event_type text, entity_id uuid, name text, city text, state text,
                field text, current_value text, proposed_value text, reason text, release text, created_at timestamptz,
                total bigint)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT c.id, c.event_type, e.id, e.name, e.city, e.state, c.field,
         CASE WHEN c.field = 'location' THEN round(ST_Y(e.location::geometry)::numeric, 5) || ', ' || round(ST_X(e.location::geometry)::numeric, 5)
              ELSE to_jsonb(e) ->> COALESCE(c.field, 'status') END,
         CASE WHEN c.field = 'location' THEN (c.new_value->>'lat') || ', ' || (c.new_value->>'lng')
              ELSE c.new_value #>> '{}' END,
         c.evidence->>'reason', r.release, c.created_at,
         count(*) OVER ()
  FROM change_events c
  JOIN entities e ON e.id = c.entity_id
  LEFT JOIN source_runs r ON r.id = c.run_id
  WHERE c.status = 'pending' AND c.review_group = p_group AND c.event_type <> 'merge'
  ORDER BY e.name, e.state, e.city, c.id
  LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0);
$$;

-- One duplicate pair, for the one-at-a-time screen: with its place in its group (in the
-- group's list order) and the next pair after it.
CREATE FUNCTION public.admin_get_merge_proposal(p_event bigint)
  RETURNS TABLE(event_id bigint, created_at timestamptz,
                a_id uuid, a_name text, a_address text, a_city text, a_state text, a_phone text, a_website text, a_status text,
                b_id uuid, b_name text, b_address text, b_city text, b_state text, b_phone text, b_website text, b_status text,
                distance_m integer, name_similarity numeric, same_phone boolean, same_website boolean,
                review_group text, group_position bigint, group_total bigint, next_event_id bigint)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  WITH g AS (
    SELECT c.id, row_number() OVER (ORDER BY a.name, a.state, a.city, c.id) AS pos, count(*) OVER () AS n
    FROM change_events c JOIN entities a ON a.id = c.entity_id
    WHERE c.status = 'pending' AND c.event_type = 'merge'
      AND c.review_group = (SELECT x.review_group FROM change_events x WHERE x.id = p_event))
  SELECT c.id, c.created_at,
         a.id, a.name, a.address, a.city, a.state, a.phone, a.website, a.status,
         b.id, b.name, b.address, b.city, b.state, b.phone, b.website, b.status,
         (c.evidence->>'distance_m')::integer, (c.evidence->>'name_similarity')::numeric,
         (c.evidence->>'same_phone')::boolean, (c.evidence->>'same_website')::boolean, c.review_group,
         me.pos, me.n, (SELECT nx.id FROM g nx WHERE nx.pos = me.pos + 1)
  FROM change_events c
  JOIN entities a ON a.id = c.entity_id
  JOIN entities b ON b.id = (c.old_value->>'duplicate')::uuid
  LEFT JOIN g me ON me.id = c.id
  WHERE c.id = p_event AND c.status = 'pending' AND c.event_type = 'merge';
$$;

-- ---------------------------------------------------------------- deciding a whole group
-- The next p_limit items of a group, accepted or declined; returns how many were decided and
-- how many are left. Merges go oldest first, so chains of copies end up in one place.
CREATE FUNCTION public.admin_decide_review_group(p_group text, p_accept boolean, p_decided_by text, p_limit integer DEFAULT 200)
  RETURNS jsonb
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_ids bigint[]; v_n integer := 0;
BEGIN
  IF p_group IS NULL OR p_group NOT LIKE 'dup\_%' AND p_group NOT LIKE 'chg\_%' THEN
    RAISE EXCEPTION 'unknown review group %', p_group;
  END IF;
  v_ids := ARRAY(SELECT c.id FROM change_events c WHERE c.status = 'pending' AND c.review_group = p_group
                 ORDER BY c.id LIMIT LEAST(GREATEST(p_limit, 1), 500));
  IF cardinality(v_ids) > 0 THEN
    IF p_group LIKE 'dup\_%' THEN
      v_n := decide_merge_proposals(v_ids, p_accept, p_decided_by);
    ELSE
      v_n := decide_source_changes(v_ids, p_accept, p_decided_by);
    END IF;
  END IF;
  RETURN jsonb_build_object('decided', v_n,
    'left', (SELECT count(*) FROM change_events c WHERE c.status = 'pending' AND c.review_group = p_group));
END $$;

REVOKE EXECUTE ON FUNCTION public.classify_review_items(), public.admin_review_groups(),
  public.admin_review_duplicates(text, integer, integer), public.admin_review_changes(text, integer, integer),
  public.admin_get_merge_proposal(bigint), public.admin_decide_review_group(text, boolean, text, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.classify_review_items(), public.admin_review_groups(),
  public.admin_review_duplicates(text, integer, integer), public.admin_review_changes(text, integer, integer),
  public.admin_get_merge_proposal(bigint), public.admin_decide_review_group(text, boolean, text, integer)
  TO service_role;

SELECT public.classify_review_items();
