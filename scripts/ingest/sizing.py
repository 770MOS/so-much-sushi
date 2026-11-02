"""Shared sizing report: places per state for one source, with a storage estimate.

Written to the workflow summary (GITHUB_STEP_SUMMARY) and to a CSV. Touches no database.
"""
import csv, os, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import STATE_NAMES  # noqa: E402

# Measured in the sandbox on 2026-10-29: about 7 KB of database space per source record,
# counting the record, its first version, the place it builds, field provenance, tags
# and ledger entries, with their indexes.
BYTES_PER_RECORD = 7_000


def report(source, release, rows, extra=None, out="sizing.csv"):
    """rows: {state code or "(unknown)": {"places": n, "with_phone": n, "with_website": n, ...}}"""
    total = sum(r["places"] for r in rows.values())
    cols = sorted({k for r in rows.values() for k in r if k != "places"})
    ordered = sorted(rows.items(), key=lambda kv: -kv[1]["places"])
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["state", "name", "places", *cols])
        for code, r in ordered:
            w.writerow([code, STATE_NAMES.get(code, ""), r["places"], *(r.get(c, 0) for c in cols)])

    gb = total * BYTES_PER_RECORD / 1e9
    lines = [f"## {source}: places per state", "",
             f"Release **{release}**. **{total:,}** food and drink places in the United States.", "",
             f"Estimated database space if loaded on its own: **{gb:.1f} GB** "
             f"(about {BYTES_PER_RECORD // 1000} KB per record, measured in the sandbox).", ""]
    for k, v in (extra or {}).items():
        lines.append(f"- {k}: {v}")
    lines += ["", "| State | Places | " + " | ".join(c.replace("_", " ") for c in cols) + " | Est. space |",
              "|---|---:|" + "---:|" * len(cols) + "---:|"]
    for code, r in ordered:
        name = f"{STATE_NAMES.get(code, code)} ({code})" if code in STATE_NAMES else code
        lines.append(f"| {name} | {r['places']:,} | " + " | ".join(f"{r.get(c, 0):,}" for c in cols)
                     + f" | {r['places'] * BYTES_PER_RECORD / 1e6:,.0f} MB |")
    text = "\n".join(lines) + "\n"
    print(text)
    # Also as one annotation: annotations can be read through the GitHub API, which the
    # run's summary page and artifacts cannot from every environment.
    if os.environ.get("GITHUB_ACTIONS"):
        compact = [f"{source} {release}: {total:,} places, est. {gb:.1f} GB"]
        compact += [f"{k}: {v}" for k, v in (extra or {}).items()]
        compact.append("state,places," + ",".join(cols))
        compact += [f"{code},{r['places']}," + ",".join(str(r.get(c, 0)) for c in cols) for code, r in ordered]
        body = "\n".join(compact)[:60000].replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::notice title=Places per state::{body}")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(text)
