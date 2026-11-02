#!/usr/bin/env bash
# psql from PostgreSQL 17 (the server's version), run in Docker so the workflow does not
# depend on which client the runner image ships. Connects to $DB_URL; the repository is
# mounted at /w, so pass script paths like scripts/db/inventory.sql.
# Usage: DB_URL=... scripts/db/psql.sh -f scripts/db/inventory.sql [-v name=value ...]
set -euo pipefail
: "${DB_URL:?DB_URL is required}"
cd "$(dirname "$0")/../.."
exec docker run --rm -i -e DB_URL -v "$PWD:/w:ro" -w /w postgres:17 \
  sh -c 'exec psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 "$@"' psql "$@"
