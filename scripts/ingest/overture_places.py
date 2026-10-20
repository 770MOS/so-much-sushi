#!/usr/bin/env python3
"""Pull Overture Places (food and drink) for a bounding box and load it into source_records.

Only the Places theme is read: the other Overture themes are ODbL and must not be ingested.
Modes:
  dry-run  read and summarise, write a CSV, touch no database (default)
  load     also create a source_runs row and upsert into source_records
"""
import argparse, json, sys
from collections import Counter
from pathlib import Path

import duckdb

sys.path.insert(0, str(Path(__file__).parent))
from common import load, notice, summarise, write_csv  # noqa: E402

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
        if (addr.get("country") or "US") != "US":
            skipped["not US"] += 1
            continue
        websites = json.loads(r["websites"]) if r["websites"] else []
        phones = json.loads(r["phones"]) if r["phones"] else []
        slug, mapped = map_category(cat, hierarchy, cmap)
        out.append({
            "source_record_id": r["id"], "upstream_dataset": dataset, "license": license_,
            "name": r["name"], "address": addr.get("freeform"), "city": addr.get("locality"),
            "state": addr.get("region"), "postal_code": addr.get("postcode"),
            "phone": phones[0] if phones else None, "website": websites[0] if websites else None,
            "lon": r["lon"], "lat": r["lat"], "source_category": cat, "category_slug": slug,
            "source_confidence": r["confidence"],
            "payload": {"taxonomy": tax, "basic_category": r["basic_category"],
                        "operating_status": r["operating_status"], "sources": sources,
                        "websites": websites, "phones": phones, "category_mapped": mapped},
        })
    return out, skipped, tops, shopping


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--release", required=True)
    ap.add_argument("--bbox", required=True, help="xmin,ymin,xmax,ymax")
    ap.add_argument("--mode", choices=["dry-run", "load"], default="dry-run")
    ap.add_argument("--out", default="overture_places.csv")
    a = ap.parse_args()
    bbox = [float(x) for x in a.bbox.split(",")]
    cmap = {k: v for k, v in json.loads((HERE / "overture_category_map.json").read_text()).items() if not k.startswith("_")}
    rows = fetch(a.release, bbox)
    records, skipped, tops, shopping = transform(rows, cmap)
    summarise(records, skipped, {"Overture top levels": dict(tops.most_common(12)),
                                 "Shopping categories seen": dict(shopping.most_common(25)),
                                 "In box": len(rows)})
    write_csv(records, a.out)
    if a.mode == "load":
        load(records, "overture_places", a.release, f"bbox:{a.bbox}",
             "per record (CDLA-Permissive-2.0 / Apache-2.0 / CC0-1.0)")


if __name__ == "__main__":
    main()
