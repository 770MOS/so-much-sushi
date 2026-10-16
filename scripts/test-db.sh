#!/usr/bin/env bash
# Replays every migration on a fresh database and runs each scenario file in supabase/tests.
# Needs a PostGIS 17 server; connection settings come from the usual PG* variables.
# Usage: scripts/test-db.sh            (all test files)
#        scripts/test-db.sh admin      (one file, without .sql)
set -euo pipefail
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
cd "$(dirname "$0")/.."
tests=("$@")
if [ ${#tests[@]} -eq 0 ]; then
  for f in supabase/tests/*.sql; do n=$(basename "$f" .sql); [ "$n" = shim ] || tests+=("$n"); done
fi
# PostgreSQL 16 has no MAINTAIN privilege; drop it from grants when testing on 16.
filter=cat
if [ "$(psql -qXtA -d postgres -c 'show server_version_num')" -lt 170000 ]; then filter="sed s/,MAINTAIN//g"; fi
failed=0
for t in "${tests[@]}"; do
  db="test_${t}_$$"
  psql -qX -d postgres -c "drop database if exists $db" -c "create database $db" >/dev/null
  out=$( { cat supabase/tests/shim.sql supabase/migrations/*.sql "supabase/tests/$t.sql" | $filter; } \
         | psql -qXt -v ON_ERROR_STOP=1 -d "$db" 2>&1 ) || { echo "$out" | tail -20; echo "ERROR in $t"; failed=1; }
  passes=$(echo "$out" | grep -c '^ *PASS' || true)
  fails=$(echo "$out" | grep '^ *FAIL' || true)
  if [ -n "$fails" ]; then echo "$fails"; failed=1; fi
  echo "$t: $passes passed${fails:+, some failed}"
  psql -qX -d postgres -c "drop database if exists $db" >/dev/null
done
exit $failed
