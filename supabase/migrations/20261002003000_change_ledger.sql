-- The change ledger: every proposed or applied change to an entity, kept permanently.
-- pending_changes is the review queue; review_decisions is the memory that stops a
-- rejected exception from coming back every run.

CREATE TABLE public.review_decisions (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  entity_id   uuid NOT NULL REFERENCES public.entities(id) ON DELETE CASCADE,
  source_id   smallint NOT NULL REFERENCES public.sources(id),
  field       text NOT NULL,
  value_hash  text NOT NULL,
  decision    text NOT NULL CHECK (decision IN ('accept', 'reject')),
  note        text,
  decided_by  text NOT NULL,
  decided_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (entity_id, source_id, field, value_hash)
);
COMMENT ON COLUMN public.review_decisions.value_hash IS 'md5 of the proposed value as jsonb text; the same proposal from the same source matches again.';

CREATE TABLE public.change_events (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_type       text NOT NULL CHECK (event_type IN
    ('new_candidate', 'attribute_change', 'absent', 'closure_signal', 'succession', 'merge', 'unmerge', 'status_change', 'manual_edit', 'user_report')),
  entity_id        uuid REFERENCES public.entities(id) ON DELETE RESTRICT,
  source_id        smallint REFERENCES public.sources(id),
  source_record_pk bigint REFERENCES public.source_records(id) ON DELETE SET NULL,
  run_id           bigint REFERENCES public.source_runs(id),
  field            text,
  old_value        jsonb,
  new_value        jsonb,
  evidence         jsonb NOT NULL DEFAULT '{}'::jsonb,
  status           text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'auto_applied', 'approved', 'rejected', 'superseded')),
  decision_id      bigint REFERENCES public.review_decisions(id),
  decided_by       text,
  decided_at       timestamptz,
  applied_at       timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX change_events_entity_idx  ON public.change_events (entity_id, created_at DESC);
CREATE INDEX change_events_pending_idx ON public.change_events (created_at) WHERE status = 'pending';
CREATE INDEX change_events_run_idx     ON public.change_events (run_id) WHERE run_id IS NOT NULL;

CREATE VIEW public.pending_changes WITH (security_invoker = true) AS
  SELECT c.id, c.event_type, c.entity_id, e.name AS entity_name, e.city, e.state,
         s.code AS source, c.field, c.old_value, c.new_value, c.evidence, c.run_id, c.created_at
  FROM public.change_events c
  LEFT JOIN public.entities e ON e.id = c.entity_id
  LEFT JOIN public.sources  s ON s.id = c.source_id
  WHERE c.status = 'pending';

ALTER TABLE public.review_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.change_events    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.review_decisions, public.change_events, public.pending_changes FROM anon, authenticated;
GRANT ALL ON public.review_decisions, public.change_events TO service_role;
GRANT SELECT ON public.pending_changes TO service_role;

-- Merge a duplicate into a survivor. The duplicate stays as a tombstone, user data moves
-- to the survivor, and the ledger records exactly what moved so the merge can be undone.
CREATE FUNCTION public.merge_entities(p_duplicate uuid, p_survivor uuid, p_decided_by text, p_note text DEFAULT NULL)
  RETURNS bigint
  LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  v_dup entities%ROWTYPE; v_sur entities%ROWTYPE;
  v_stars jsonb; v_hidden jsonb; v_items jsonb; v_records jsonb; v_event bigint;
BEGIN
  IF p_duplicate = p_survivor THEN RAISE EXCEPTION 'cannot merge an entity into itself'; END IF;
  -- lock both rows in a fixed order
  PERFORM 1 FROM entities WHERE id IN (p_duplicate, p_survivor) ORDER BY id FOR UPDATE;
  SELECT * INTO v_dup FROM entities WHERE id = p_duplicate;
  SELECT * INTO v_sur FROM entities WHERE id = p_survivor;
  IF v_dup.id IS NULL OR v_sur.id IS NULL THEN RAISE EXCEPTION 'both entities must exist'; END IF;
  IF v_dup.status = 'merged' THEN RAISE EXCEPTION 'entity % is already merged', p_duplicate; END IF;
  IF v_sur.status IN ('merged', 'removed') THEN RAISE EXCEPTION 'survivor % is %', p_survivor, v_sur.status; END IF;

  -- Each row on the duplicate either moves to the survivor or, if the same user/list already
  -- has the survivor, is dropped as redundant. Both sets are recorded.
  WITH moved AS (
    INSERT INTO stars (user_id, entity_id, created_at)
      SELECT user_id, p_survivor, created_at FROM stars WHERE entity_id = p_duplicate
      ON CONFLICT (user_id, entity_id) DO NOTHING RETURNING user_id)
  SELECT jsonb_build_object(
           'moved',   COALESCE((SELECT jsonb_agg(user_id) FROM moved), '[]'::jsonb),
           'dropped', COALESCE((SELECT jsonb_agg(jsonb_build_object('user_id', s.user_id, 'created_at', s.created_at))
                                FROM stars s WHERE s.entity_id = p_duplicate
                                  AND s.user_id NOT IN (SELECT user_id FROM moved)), '[]'::jsonb))
    INTO v_stars;
  DELETE FROM stars WHERE entity_id = p_duplicate;

  WITH moved AS (
    INSERT INTO hidden_entities (user_id, entity_id, created_at)
      SELECT user_id, p_survivor, created_at FROM hidden_entities WHERE entity_id = p_duplicate
      ON CONFLICT (user_id, entity_id) DO NOTHING RETURNING user_id)
  SELECT jsonb_build_object(
           'moved',   COALESCE((SELECT jsonb_agg(user_id) FROM moved), '[]'::jsonb),
           'dropped', COALESCE((SELECT jsonb_agg(jsonb_build_object('user_id', h.user_id, 'created_at', h.created_at))
                                FROM hidden_entities h WHERE h.entity_id = p_duplicate
                                  AND h.user_id NOT IN (SELECT user_id FROM moved)), '[]'::jsonb))
    INTO v_hidden;
  DELETE FROM hidden_entities WHERE entity_id = p_duplicate;

  WITH moved AS (
    INSERT INTO list_items (list_id, entity_id, note, position, added_at)
      SELECT list_id, p_survivor, note, position, added_at FROM list_items WHERE entity_id = p_duplicate
      ON CONFLICT (list_id, entity_id) DO NOTHING RETURNING list_id)
  SELECT jsonb_build_object(
           'moved',   COALESCE((SELECT jsonb_agg(list_id) FROM moved), '[]'::jsonb),
           'dropped', COALESCE((SELECT jsonb_agg(jsonb_build_object('list_id', li.list_id, 'note', li.note,
                                         'position', li.position, 'added_at', li.added_at))
                                FROM list_items li WHERE li.entity_id = p_duplicate
                                  AND li.list_id NOT IN (SELECT list_id FROM moved)), '[]'::jsonb))
    INTO v_items;
  DELETE FROM list_items WHERE entity_id = p_duplicate;

  -- Source records follow the entity they describe.
  WITH moved AS (
    UPDATE source_records SET entity_id = p_survivor WHERE entity_id = p_duplicate RETURNING id)
  SELECT COALESCE(jsonb_agg(id), '[]'::jsonb) INTO v_records FROM moved;

  -- Earlier tombstones pointing at the duplicate keep working through resolve_entity().
  UPDATE entities SET status = 'merged', merged_into = p_survivor WHERE id = p_duplicate;

  INSERT INTO change_events (event_type, entity_id, old_value, new_value, evidence, status, decided_by, decided_at, applied_at)
  VALUES ('merge', p_survivor,
          jsonb_build_object('duplicate', p_duplicate, 'duplicate_status', v_dup.status),
          jsonb_build_object('survivor', p_survivor),
          jsonb_build_object('note', p_note, 'stars', v_stars, 'hidden', v_hidden,
                             'list_items', v_items, 'source_records', v_records),
          'approved', p_decided_by, now(), now())
  RETURNING id INTO v_event;
  RETURN v_event;
END $$;
REVOKE EXECUTE ON FUNCTION public.merge_entities(uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merge_entities(uuid, uuid, text, text) TO service_role;
