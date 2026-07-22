-- Adds is_default_list to lists: marks a single list per owner as their
-- "quick save" target (used by the venue page's "Want to Go" button - see
-- src/components/WantToGoButton.tsx). Not exposed as a user-facing concept
-- elsewhere - a default list is still a completely normal list, editable/
-- deletable/renameable like any other from /lists, it's just the one the
-- quick-save button reads and writes to without asking which list to use.
--
-- The partial unique index (not a table-level UNIQUE constraint) is what
-- actually enforces "at most one default list per owner" - a plain UNIQUE
-- on (owner_id, is_default_list) would also forbid two *non*-default lists
-- for the same owner, since both would tie on is_default_list = false.
-- Indexing only WHERE is_default_list restricts the constraint to just the
-- true rows.
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

ALTER TABLE lists ADD COLUMN IF NOT EXISTS is_default_list boolean NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS lists_one_default_per_owner
  ON lists (owner_id)
  WHERE is_default_list;

NOTIFY pgrst, 'reload schema';
