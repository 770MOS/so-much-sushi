#!/usr/bin/env python3
"""Pull Overture Places (food and drink) for a bounding box and load it into source_records.

Only the Places theme is read: the other Overture themes are ODbL and must not be ingested.
Modes:
  dry-run  read and summarise, write a CSV, touch no database (default)
  load     also create a source_runs row and upsert into source_records
"""
import argparse, csv, json, os, sys, urllib.error, urllib.request
from datetime import datetime, timezone
from collections import Counter
from pathlib import Path

import duckdb

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


def map_category(cat, cmap):
    """Return (our slug, mapped confidently?)."""
    if not cat:
        return "restaurants", False
    if cat in cmap:
        return cmap[cat], True
    for words, slug in ((("brewery", "brewpub"), "brewery"), (("bar", "pub", "lounge", "tavern"), "bar"),
                        (("coffee", "cafe", "tea"), "coffee"),
                        (("bakery", "dessert", "ice_cream", "donut", "pastry"), "bakery")):
        if any(w in cat.split("_") or w == cat for w in words):
            return slug, False
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
    out, skipped, tops = [], Counter(), Counter()
    for r in rows:
        tax = json.loads(r["taxonomy"]) if r["taxonomy"] else {}
        hierarchy = tax.get("hierarchy") or []
        tops[hierarchy[0] if hierarchy else "(none)"] += 1
        if "food_and_drink" not in json.dumps(tax):
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
        cat = tax.get("primary") or r["basic_category"]
        slug, mapped = map_category(cat, cmap)
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
    return out, skipped, tops


def summarise(records, skipped, tops, total):
    print(f"\nplaces in box: {total}; kept as food and drink: {len(records)}")
    print("top-level taxonomy of everything in the box:", dict(tops.most_common(12)))
    print("skipped:", dict(skipped))
    for label, key in (("upstream dataset", lambda r: r["upstream_dataset"]), ("licence", lambda r: r["license"]),
                       ("our category", lambda r: r["category_slug"]), ("state", lambda r: r["state"])):
        print(f"by {label}:", dict(Counter(map(key, records)).most_common(15)))
    unmapped = Counter(r["source_category"] for r in records if not r["payload"]["category_mapped"])
    print(f"not confidently mapped: {sum(unmapped.values())}; top source categories:", dict(unmapped.most_common(40)))
    print("with phone:", sum(1 for r in records if r["phone"]), "| with website:", sum(1 for r in records if r["website"]))
    print("operating_status:", dict(Counter(str(r["payload"]["operating_status"]) for r in records)))
    print("sample:", json.dumps(records[:3], indent=1)[:3000])


class Rest:
    def __init__(self):
        self.url = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1"
        self.key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

    def call(self, method, path, body, prefer=None):
        req = urllib.request.Request(self.url + path, method=method, data=json.dumps(body).encode(), headers={
            "apikey": self.key, "Authorization": f"Bearer {self.key}", "Content-Type": "application/json",
            **({"Prefer": prefer} if prefer else {})})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                text = resp.read().decode()
                return json.loads(text) if text else None
        except urllib.error.HTTPError as e:
            sys.exit(f"{method} {path} failed: {e.code} {e.read().decode()[:500]}")


def load(records, release, scope):
    rest = Rest()
    req = urllib.request.Request(rest.url + "/sources?code=eq.overture_places&select=id,is_active",
                                 headers={"apikey": rest.key, "Authorization": f"Bearer {rest.key}"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        src = json.loads(resp.read().decode())
    if not src or not src[0]["is_active"]:
        sys.exit("source overture_places is missing or inactive in the register; refusing to load")
    run = rest.call("POST", "/source_runs", {"source_id": src[0]["id"], "release": release, "scope": scope,
                                             "license": "per record (CDLA-Permissive-2.0 / Apache-2.0 / CC0-1.0)"},
                    prefer="return=representation")[0]
    done = 0
    for i in range(0, len(records), 500):
        done += rest.call("POST", "/rpc/ingest_source_records", {"p_run_id": run["id"], "p_records": records[i:i + 500]})
    rest.call("PATCH", f"/source_runs?id=eq.{run['id']}", {
        "status": "succeeded", "record_count": done, "finished_at": datetime.now(timezone.utc).isoformat(),
        "stats": {"by_license": dict(Counter(r["license"] for r in records)),
                  "by_dataset": dict(Counter(r["upstream_dataset"] for r in records))}})
    print(f"loaded {done} records as run {run['id']}")


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
    records, skipped, tops = transform(rows, cmap)
    summarise(records, skipped, tops, len(rows))
    with open(a.out, "w", newline="") as f:
        cols = [c for c in records[0] if c != "payload"] if records else []
        w = csv.DictWriter(f, fieldnames=cols + ["category_mapped"])
        w.writeheader()
        for r in records:
            w.writerow({**{c: r[c] for c in cols}, "category_mapped": r["payload"]["category_mapped"]})
    if a.mode == "load":
        load(records, a.release, f"bbox:{a.bbox}")


if __name__ == "__main__":
    main()
