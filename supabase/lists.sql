-- Lists: user-created, visibility-scoped collections of entities (e.g.
-- "Date night spots"). New feature - no lists/list_items tables existed in
-- this schema before this file.
--
-- Visibility is scoped entirely within signed-in users - there is no
-- anonymous/public-internet access anywhere else in this app (starring,
-- friending, recommendations are all sign-in-gated), so "public" here means
-- "any authenticated user", not the open internet:
--   private  - only the owner
--   friends  - owner + their accepted friends
--   public   - owner + any signed-in user
--
-- Note: the owner column is `owner_id`, not `user_id` (unlike stars/
-- hidden_entities) - this file was corrected to match the live schema after
-- the table was actually created with that name. list_items also carries
-- two extra columns beyond what's used today (`note` text, `position`
-- integer) for future manual notes/ordering - present in the live schema,
-- unused by the app for now.
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

CREATE TABLE IF NOT EXISTS lists (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name text NOT NULL,
    description text,
    visibility text NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'friends', 'public')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS list_items (
    list_id uuid NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
    entity_id uuid NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    note text,
    position integer,
    added_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (list_id, entity_id)
);

GRANT SELECT, INSERT, DELETE ON TABLE lists TO authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE list_items TO authenticated;
GRANT ALL ON TABLE lists, list_items TO service_role;

ALTER TABLE lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE list_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view visible lists" ON lists;
CREATE POLICY "Users can view visible lists" ON lists
  FOR SELECT TO authenticated
  USING (
    owner_id = auth.uid()
    OR visibility = 'public'
    OR (
      visibility = 'friends'
      AND EXISTS (
        SELECT 1 FROM friendships f
        WHERE f.status = 'accepted'
          AND ((f.requester_id = auth.uid() AND f.addressee_id = lists.owner_id)
            OR (f.addressee_id = auth.uid() AND f.requester_id = lists.owner_id))
      )
    )
  );

DROP POLICY IF EXISTS "Users can create their own lists" ON lists;
CREATE POLICY "Users can create their own lists" ON lists
  FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete their own lists" ON lists;
CREATE POLICY "Users can delete their own lists" ON lists
  FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

DROP POLICY IF EXISTS "Users can view items of visible lists" ON list_items;
CREATE POLICY "Users can view items of visible lists" ON list_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM lists l
      WHERE l.id = list_items.list_id
        AND (
          l.owner_id = auth.uid()
          OR l.visibility = 'public'
          OR (
            l.visibility = 'friends'
            AND EXISTS (
              SELECT 1 FROM friendships f
              WHERE f.status = 'accepted'
                AND ((f.requester_id = auth.uid() AND f.addressee_id = l.owner_id)
                  OR (f.addressee_id = auth.uid() AND f.requester_id = l.owner_id))
            )
          )
        )
    )
  );

DROP POLICY IF EXISTS "Owners can add items to their own lists" ON list_items;
CREATE POLICY "Owners can add items to their own lists" ON list_items
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM lists l WHERE l.id = list_items.list_id AND l.owner_id = auth.uid())
  );

DROP POLICY IF EXISTS "Owners can remove items from their own lists" ON list_items;
CREATE POLICY "Owners can remove items from their own lists" ON list_items
  FOR DELETE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM lists l WHERE l.id = list_items.list_id AND l.owner_id = auth.uid())
  );

-- Two lookup functions for the list detail page (/lists/[id]). Both are
-- SECURITY DEFINER, so - like search_entities and get_my_starred_entities -
-- they bypass RLS/grants on the tables they touch and must re-implement the
-- visibility check themselves inline (mirroring the "Users can view visible
-- lists" policy above exactly). Both return zero rows (not an error) for a
-- list that doesn't exist or isn't visible to the caller, so the page can
-- render a plain "not found" state either way without leaking which case it
-- was.

DROP FUNCTION IF EXISTS public.get_list_meta(uuid);

CREATE FUNCTION public.get_list_meta(p_list_id uuid)
 RETURNS TABLE(id uuid, name text, description text, visibility text, owner_id uuid, owner_name text, is_owner boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $function$
    SELECT l.id, l.name, l.description, l.visibility, l.owner_id,
           COALESCE(p.display_name, p.handle) AS owner_name,
           (l.owner_id = auth.uid()) AS is_owner
    FROM lists l
    JOIN profiles p ON p.id = l.owner_id
    WHERE l.id = p_list_id
      AND (
        l.owner_id = auth.uid()
        OR l.visibility = 'public'
        OR (
          l.visibility = 'friends'
          AND EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'accepted'
              AND ((f.requester_id = auth.uid() AND f.addressee_id = l.owner_id)
                OR (f.addressee_id = auth.uid() AND f.requester_id = l.owner_id))
          )
        )
      );
$function$;

DROP FUNCTION IF EXISTS public.get_list_entities(uuid);

CREATE FUNCTION public.get_list_entities(p_list_id uuid)
 RETURNS TABLE(entity_id uuid, name text, address text, city text, state text, lat double precision, lng double precision, added_at timestamptz)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $function$
    SELECT e.id AS entity_id, e.name, e.address, e.city, e.state,
           ST_Y(e.location::geometry) AS lat, ST_X(e.location::geometry) AS lng,
           li.added_at
    FROM lists l
    JOIN list_items li ON li.list_id = l.id
    JOIN entities e ON e.id = li.entity_id
    WHERE l.id = p_list_id
      AND (
        l.owner_id = auth.uid()
        OR l.visibility = 'public'
        OR (
          l.visibility = 'friends'
          AND EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'accepted'
              AND ((f.requester_id = auth.uid() AND f.addressee_id = l.owner_id)
                OR (f.addressee_id = auth.uid() AND f.requester_id = l.owner_id))
          )
        )
      )
    ORDER BY li.added_at DESC;
$function$;

GRANT EXECUTE ON FUNCTION public.get_list_meta(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_list_entities(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
