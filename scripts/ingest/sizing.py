"""Shared sizing report: places per state for one source, with a storage estimate.

Written to the workflow summary (GITHUB_STEP_SUMMARY) and to a CSV. Touches no database.
"""
import csv, os

# Measured in the sandbox on 2026-10-29: about 7 KB of database space per source record,
# counting the record, its first version, the place it builds, field provenance, tags
# and ledger entries, with their indexes.
BYTES_PER_RECORD = 7_000

STATE_NAMES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
    "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia",
    "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
    "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts",
    "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
    "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
    "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
    "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
    "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming", "PR": "Puerto Rico",
}
_BY_NAME = {v.lower(): k for k, v in STATE_NAMES.items()}


def state_code(value):
    """Two-letter code from a code, a full name or "US-VA"; None when it is not a US state."""
    v = (value or "").strip()
    if v.upper().startswith("US-"):
        v = v[3:]
    if v.upper() in STATE_NAMES:
        return v.upper()
    return _BY_NAME.get(v.lower())


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
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(text)
