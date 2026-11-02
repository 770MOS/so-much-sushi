#!/usr/bin/env python3
"""Pull Overture Places (food and drink) for a bounding box and load it into source_records.

Only the Places theme is read: the other Overture themes are ODbL and must not be ingested.
Modes:
  dry-run  read and summarise, write a CSV, touch no database (default)
  load     also create a source_runs row and upsert into source_records
  size     count places per state across the whole United States (no --bbox needed)

Area: --bbox xmin,ymin,xmax,ymax, or
      --states all | VA,MD,...  (the United States is read once, then each state is loaded
                                 and reconciled as its own run; safe to run again)
"""
import argparse, json, os, sys, tempfile
from collections import Counter
from pathlib import Path

import duckdb

sys.path.insert(0, str(Path(__file__).parent))
from common import (NO_STATE, STATE_NAMES, load, load_by_state, notice, parse_states, run,  # noqa: E402
                    state_code, summarise, write_csv)
from sizing import report  # noqa: E402

HERE = Path(__file__).parent
# Licence per upstream dataset, from https://docs.overturemaps.org/attribution/ . Used only
# when a record does not carry its own licence. Unknown datasets are skipped, never guessed.
DATASET_LICENSE = {
    "meta": "CDLA-Permissive-2.0", "microsoft": "CDLA-Permissive-2.0", "msft": "CDLA-Permissive-2.0",
    "pinmeto": "CDLA-Permissive-2.0", "krick": "CDLA-Permissive-2.0", "renderseo": "CDLA-Permissive-2.0",
    "dac": "CDLA-Permissive-2.0", "brightquery": "CDLA-Permissive-2.0",
    "foursquare": "Apache-2.0", "alltheplaces": "CC0-1.0",
}
ALLOWED_LICENSES = {"cdla-permissive-2.0", "apache-2.0", "cc0-1.0"}


def norm_license(value):
    v = (value or "").strip().lower().replace(" ", "-").replace("_", "-")
    return {"cdla-permissive-2.0": "CDLA-Permissive-2.0", "apache-2.0": "Apache-2.0",
            "cc0-1.0": "CC0-1.0", "cc0": "CC0-1.0"}.get(v)


def map_category(cat, hierarchy, cmap):
    """Return (our slug, exact match?). Falls back to the nearest listed ancestor in Overture's hierarchy."""
    if cat in cmap:
        return cmap[cat], True
    for node in reversed(hierarchy or []):
        if node in cmap:
            return cmap[node], False
    return "restaurants", False


def fetch(release, bbox):
    xmin, ymin, xmax, ymax = bbox
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
    path = f"s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*"
    where = f"bbox.xmin BETWEEN {xmin} AND {xmax} AND bbox.ymin BETWEEN {ymin} AND {ymax}"
    cols = [r[0] for r in con.execute(f"DESCRIBE SELECT * FROM read_parquet('{path}', hive_partitioning=1)").fetchall()]
    print("columns:", ", ".join(cols))
    opt = lambda c: c if c in cols else f"NULL AS {c}"
    rel = con.execute(f"""
        SELECT id, names.primary AS name, {opt('basic_category')}, to_json(taxonomy) AS taxonomy,
               confidence, {opt('operating_status')}, to_json(addresses) AS addresses,
               to_json(websites) AS websites, to_json(phones) AS phones, to_json(sources) AS sources,
               bbox.xmin AS lon, bbox.ymin AS lat
        FROM read_parquet('{path}', hive_partitioning=1)
        WHERE {where}""")
    names = [d[0] for d in rel.description]
    return [dict(zip(names, row)) for row in rel.fetchall()]


# Overture gives Puerto Rico its own country code. We treat it as part of the United States.
US_COUNTRIES = ("US", "PR")

# The United States as four boxes: the lower 48, Alaska, Hawaii, and Puerto Rico.
US_BOXES = [(-125.0, 24.0, -66.5, 49.5), (-180.0, 51.0, -129.9, 71.6), (-160.6, 18.8, -154.7, 22.4), (-67.5, 17.6, -65.2, 18.6)]


def record_state(region, country):
    """Our two-letter state for an Overture address, or None."""
    if (country or "").upper() == "PR":
        return "PR"
    return state_code(region)


def state_map_sql():
    """Rows (key, code) matching what state_code() accepts: the code or the full name, upper case."""
    rows = [(c, c) for c in STATE_NAMES] + [(n.upper(), c) for c, n in STATE_NAMES.items()]
    return "SELECT * FROM (VALUES " + ", ".join(f"('{k.replace(chr(39), chr(39) * 2)}', '{c}')" for k, c in rows) + ") m(k, code)"


def fetch_us(release, cmap, path, src=None):
    """Read every food and drink place in the United States once, into a local file, with our
    state code (or NULL) in column st, so each state can be read back on its own."""
    con = duckdb.connect()
    if src is None:
        con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
        src = f"s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*"
    cols = [r[0] for r in con.execute(f"DESCRIBE SELECT * FROM read_parquet('{src}', hive_partitioning=1)").fetchall()]
    opt = lambda c: c if c in cols else f"NULL AS {c}"
    boxes = " OR ".join(f"(bbox.xmin BETWEEN {a} AND {c} AND bbox.ymin BETWEEN {b} AND {d})" for a, b, c, d in US_BOXES)
    cats = ", ".join("'" + k.replace("'", "''") + "'" for k in cmap)
    con.execute(f"""
        COPY (
          SELECT p.*, CASE WHEN upper(p.country) = 'PR' THEN 'PR' ELSE m.code END AS st
          FROM (
            SELECT id, names.primary AS name, {opt('basic_category')}, to_json(taxonomy) AS taxonomy,
                   confidence, {opt('operating_status')}, to_json(addresses) AS addresses,
                   to_json(websites) AS websites, to_json(phones) AS phones, to_json(sources) AS sources,
                   bbox.xmin AS lon, bbox.ymin AS lat,
                   addresses[1].region AS region, addresses[1].country AS country
            FROM read_parquet('{src}', hive_partitioning=1)
            WHERE ({boxes})
              AND coalesce(addresses[1].country, 'US') IN ('US', 'PR')
              AND (list_contains(taxonomy.hierarchy, 'food_and_drink') OR taxonomy.primary IN ({cats}))
          ) p
          LEFT JOIN ({state_map_sql()}) m ON m.k = upper(regexp_replace(trim(p.region), '^[Uu][Ss]-', ''))
        ) TO '{path}' (FORMAT parquet)""")
    counts = dict(con.execute(f"SELECT coalesce(st, '{NO_STATE}'), count(*) FROM read_parquet('{path}') GROUP BY 1").fetchall())
    notice("Read", f"{sum(counts.values()):,} food and drink rows in the United States from Overture {release} "
                   f"({os.path.getsize(path) / 1e9:.2f} GB on disk)")
    return counts


def rows_for_state(path, code):
    """One state's rows from the local file ('none': rows with no recognised state)."""
    con = duckdb.connect()
    where = "st IS NULL" if code == NO_STATE else f"st = '{code}'"
    rel = con.execute(f"SELECT * EXCLUDE (st) FROM read_parquet('{path}') WHERE {where}")
    names = [d[0] for d in rel.description]
    return [dict(zip(names, row)) for row in rel.fetchall()]


def size(release, cmap, path=None):
    """Count food and drink places per state in SQL, without pulling every record."""
    con = duckdb.connect()
    if path is None:
        con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
        path = f"s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*"
    boxes = " OR ".join(f"(bbox.xmin BETWEEN {a} AND {c} AND bbox.ymin BETWEEN {b} AND {d})" for a, b, c, d in US_BOXES)
    cats = ", ".join("'" + k.replace("'", "''") + "'" for k in cmap)
    rel = con.execute(f"""
        SELECT addresses[1].region AS region, addresses[1].country AS country,
               lower(coalesce(sources[1].dataset, '')) AS dataset,
               sources[1].license AS license, count(*) AS places,
               count(*) FILTER (WHERE len(phones) > 0) AS with_phone,
               count(*) FILTER (WHERE len(websites) > 0) AS with_website,
               count(*) FILTER (WHERE coalesce(operating_status, 'open') <> 'open') AS marked_closed
        FROM read_parquet('{path}', hive_partitioning=1)
        WHERE ({boxes})
          AND names.primary IS NOT NULL
          AND coalesce(addresses[1].country, 'US') IN ('US', 'PR')
          AND (list_contains(taxonomy.hierarchy, 'food_and_drink') OR taxonomy.primary IN ({cats}))
        GROUP BY ALL""")
    rows, licences, dropped = {}, Counter(), Counter()
    for region, country, dataset, lic, places, phone, web, closed in rel.fetchall():
        licence = norm_license(lic) or DATASET_LICENSE.get(dataset)
        if not licence or licence.lower() not in ALLOWED_LICENSES:
            dropped[dataset or "(no dataset)"] += places
            continue
        licences[licence] += places
        r = rows.setdefault(record_state(region, country) or "(unknown)", {"places": 0, "with_phone": 0, "with_website": 0, "marked_closed": 0})
        r["places"] += places; r["with_phone"] += phone; r["with_website"] += web; r["marked_closed"] += closed
    report("Overture Places", release, rows, {
        "By licence": ", ".join(f"{k} {v:,}" for k, v in licences.most_common()),
        "Left out (licence not recognised)": ", ".join(f"{k} {v:,}" for k, v in dropped.most_common()) or "none",
    })


def transform(rows, cmap):
    out, skipped, tops, shopping = [], Counter(), Counter(), Counter()
    for r in rows:
        tax = json.loads(r["taxonomy"]) if r["taxonomy"] else {}
        hierarchy = tax.get("hierarchy") or []
        tops[hierarchy[0] if hierarchy else "(none)"] += 1
        cat = tax.get("primary") or r["basic_category"]
        if hierarchy and hierarchy[0] == "shopping":
            shopping[cat] += 1
        if "food_and_drink" not in hierarchy and cat not in cmap:
            skipped["not food and drink"] += 1
            continue
        if not r["name"]:
            skipped["no name"] += 1
            continue
        sources = json.loads(r["sources"]) if r["sources"] else []
        src = sources[0] if sources else {}
        dataset = (src.get("dataset") or "").strip()
        license_ = norm_license(src.get("license")) or DATASET_LICENSE.get(dataset.lower())
        if not license_ or license_.lower() not in ALLOWED_LICENSES:
            skipped[f"licence not recognised ({dataset or 'no dataset'})"] += 1
            continue
        addr = (json.loads(r["addresses"]) or [{}])[0] if r["addresses"] else {}
        if (addr.get("country") or "US") not in US_COUNTRIES:
            skipped["not US"] += 1
            continue
        websites = json.loads(r["websites"]) if r["websites"] else []
        phones = json.loads(r["phones"]) if r["phones"] else []
        slug, mapped = map_category(cat, hierarchy, cmap)
        out.append({
            "source_record_id": r["id"], "upstream_dataset": dataset, "license": license_,
            "name": r["name"], "address": addr.get("freeform"), "city": addr.get("locality"),
            "state": record_state(addr.get("region"), addr.get("country")) or addr.get("region"),
            "postal_code": addr.get("postcode"),
            "phone": phones[0] if phones else None, "website": websites[0] if websites else None,
            "lon": r["lon"], "lat": r["lat"], "source_category": cat, "category_slug": slug,
            "source_confidence": r["confidence"],
            "payload": {"taxonomy": tax, "basic_category": r["basic_category"], "address": addr,
                        "operating_status": r["operating_status"], "sources": sources,
                        "websites": websites, "phones": phones, "category_mapped": mapped},
        })
    return out, skipped, tops, shopping


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--release", required=True)
    ap.add_argument("--bbox", help="xmin,ymin,xmax,ymax")
    ap.add_argument("--states", help="'all', or two-letter codes like VA,MD (and 'none' for records with no state)")
    ap.add_argument("--mode", choices=["dry-run", "load", "size"], default="dry-run")
    ap.add_argument("--out", default="overture_places.csv")
    a = ap.parse_args()
    cmap = {k: v for k, v in json.loads((HERE / "overture_category_map.json").read_text()).items() if not k.startswith("_")}
    if a.mode == "size":
        size(a.release, cmap)
        return
    if a.states:
        load_states(a, cmap)
        return
    if not a.bbox:
        sys.exit("--bbox or --states is required unless --mode size")
    bbox = [float(x) for x in a.bbox.split(",")]
    rows = fetch(a.release, bbox)
    records, skipped, tops, shopping = transform(rows, cmap)
    summarise(records, skipped, {"Overture top levels": dict(tops.most_common(12)),
                                 "Shopping categories seen": dict(shopping.most_common(25)),
                                 "In box": len(rows)})
    write_csv(records, a.out)
    if a.mode == "load":
        load(records, "overture_places", a.release, f"bbox:{a.bbox}",
             "per record (CDLA-Permissive-2.0 / Apache-2.0 / CC0-1.0)")


def load_states(a, cmap):
    """Read the country once, then load and reconcile one state at a time."""
    states = parse_states(a.states)
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "us.parquet")
        counts = fetch_us(a.release, cmap, path)
        notice("Rows per state", ", ".join(f"{c} {counts.get(c, 0):,}" for c in states))
        skipped_all = Counter()

        def records_for(code):
            records, skipped, _, _ = transform(rows_for_state(path, code), cmap)
            skipped_all.update(skipped)
            return records

        if a.mode == "load":
            load_by_state(records_for, "overture_places", a.release,
                          "per record (CDLA-Permissive-2.0 / Apache-2.0 / CC0-1.0)", states)
        else:
            kept = {c: len(records_for(c)) for c in states}
            notice("Would load", ", ".join(f"{c} {n:,}" for c, n in kept.items()) + f" (total {sum(kept.values()):,})")
        notice("Left out", dict(skipped_all) or "none")


if __name__ == "__main__":
    run(main)
