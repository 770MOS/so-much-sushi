#!/usr/bin/env bash
# Turn inventory output ("key|value" lines on stdin) into a table on the run's summary page
# and one annotation (annotations can be read through the GitHub API).
# Usage: scripts/db/psql.sh -f scripts/db/inventory.sql | scripts/db/report.sh "Before"
set -euo pipefail
title="$1"
lines=$(grep '|' || true)
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### $title"; echo; echo "| | |"; echo "|---|---|"
    echo "$lines" | sed -E 's/^([^|]*)\|(.*)$/| \1 | \2 |/'; echo; } >> "$GITHUB_STEP_SUMMARY"
fi
echo "$lines"
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  body=$(echo "$lines" | sed 's/|/: /' | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')
  echo "::notice title=$title::$body"
fi
