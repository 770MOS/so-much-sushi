#!/usr/bin/env python3
"""Pull All the Places (food and drink, United States) and load it into source_records.

All the Places scrapes store locators on brands' own websites and publishes the result
under CC0-1.0 every week. It is strong on chains and has little on independents.

Modes:
  dry-run  read and summarise, write a CSV, touch no database (default)
  load     also create a source_runs row, upsert into source_records and reconcile

Area: --bbox xmin,ymin,xmax,ymax  (fast: only the matching parts of the file are read), or
      --state VA                  (reads the whole national file, then keeps that state).
"""
import argparse, io, json, os, sys, tempfile, urllib.request, zipfile
from collections import Counter
from pathlib import Path

import duckdb

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
from sizing import report  # noqa: E402
from common import USER_AGENT, get_json, load, notice, run, summarise, write_csv  # noqa: E402

LATEST = "https://data.alltheplaces.xyz/runs/latest.json"
LICENSE = "CC0-1.0"
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
BY_NAME = {v.lower(): k for k, v in STATE_NAMES.items()}


def norm_state(value):
    v = (value or "").strip()
    if v.upper() in STATE_NAMES:
        return v.upper()
    return BY_NAME.get(v.lower())


def latest_run():
    return get_json(LATEST)


def in_area(lon, lat, props, bbox, state):
    if bbox:
        xmin, ymin, xmax, ymax = bbox
        if lon is None or lat is None or not (xmin <= lon <= xmax and ymin <= lat <= ymax):
            return False
    if state and norm_state(props.get("addr:state")) != state:
        return False
    return (props.get("addr:country") or "US") in ("US", "USA")


def fetch_parquet(parquet_url, keys, bbox=None, state=None):
    """Read only the matching rows of the weekly GeoParquet (fast, when it is published)."""
    con = duckdb.connect()
    if parquet_url.startswith("http"):
        con.execute("INSTALL httpfs; LOAD httpfs;")
        con.execute("SET http_timeout = 300; SET http_retries = 5;")
    cols = [r[0] for r in con.execute(f"DESCRIBE SELECT * FROM read_parquet('{parquet_url}')").fetchall()]
    notice("Columns", ", ".join(cols))
    tag_filter = " OR ".join(
        f"properties['{k}'] = '{v}'" for k, v in (key.split("=", 1) for key in keys))
    where = [f"({tag_filter})", "coalesce(properties['addr:country'], 'US') IN ('US', 'USA')",
             "properties['ref'] IS NOT NULL"]
    if bbox:
        xmin, ymin, xmax, ymax = bbox
        where.append(f"bbox.xmin BETWEEN {xmin} AND {xmax} AND bbox.ymin BETWEEN {ymin} AND {ymax}")
    if state:
        names = {state.lower(), STATE_NAMES[state].lower()}
        where.append("lower(trim(properties['addr:state'])) IN (" + ", ".join(f"'{n}'" for n in names) + ")")
    rel = con.execute(f"""
        SELECT id, dataset_attributes['@spider'] AS spider, to_json(properties) AS properties,
               (bbox.xmin + bbox.xmax) / 2 AS lon, (bbox.ymin + bbox.ymax) / 2 AS lat
        FROM read_parquet('{parquet_url}')
        WHERE {' AND '.join(where)}""")
    names = [d[0] for d in rel.description]
    return [dict(zip(names, row)) for row in rel.fetchall()]


def point_of(geometry):
    """A representative point: the point itself, or the middle of a shape's extent."""
    if not geometry:
        return None, None
    if geometry.get("type") == "Point":
        c = geometry.get("coordinates") or [None, None]
        return c[0], c[1]
    xs, ys = [], []

    def walk(c):
        if c and isinstance(c[0], (int, float)):
            xs.append(c[0]); ys.append(c[1])
        else:
            for x in c or []:
                walk(x)
    walk(geometry.get("coordinates"))
    return ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2) if xs else (None, None)


def features_of(member, tokens=()):
    """Yield features from one spider file, whether written one feature per line or as one document."""
    head = member.read(4096)
    rest = member.read()
    text = (head + rest).decode("utf-8", errors="replace")
    lines = text.splitlines()
    if len(lines) > 2:
        for line in lines:
            line = line.strip().rstrip(",")
            if tokens and not any(t in line for t in tokens):
                continue  # cheap pre-filter: no food-and-drink tag value on this line
            if line.startswith("{") and '"Feature"' in line and '"FeatureCollection"' not in line:
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    pass
        return
    try:
        doc = json.loads(text)
    except json.JSONDecodeError:
        return
    yield from (doc.get("features") or [])


def fetch_zip(output_url, keys, bbox=None, state=None):
    """Stream the weekly zip of every spider's output without unpacking it to disk."""
    wanted = {v for v in (key.split("=", 1)[1] for key in keys)}
    tokens = [f'"{v}"' for v in wanted]
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "output.zip")
        req = urllib.request.Request(output_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=600) as resp, open(path, "wb") as out:
            while chunk := resp.read(8 << 20):
                out.write(chunk)
        notice("Downloaded", f"{os.path.getsize(path) / 1e9:.2f} GB")
        rows, files = [], 0
        with zipfile.ZipFile(path) as zf:
            for info in zf.infolist():
                if info.is_dir() or not info.filename.endswith(("geojson", "json")):
                    continue
                files += 1
                spider = Path(info.filename).name.split(".")[0]
                with zf.open(info) as member:
                    for f in features_of(io.BufferedReader(member, 1 << 20), tokens):
                        props = f.get("properties") or {}
                        if not any(props.get(k) == v for k, v in (key.split("=", 1) for key in keys)):
                            continue
                        if not props.get("ref"):
                            continue
                        lon, lat = point_of(f.get("geometry"))
                        if not in_area(lon, lat, props, bbox, state):
                            continue
                        rows.append({"id": f.get("id"), "spider": props.get("@spider") or spider,
                                     "properties": props, "lon": lon, "lat": lat})
        notice("Read", f"{files} spider files")
        return rows


def fetch(info, keys, bbox=None, state=None):
    """Use the GeoParquet when it exists; otherwise fall back to the zip."""
    if info.get("parquet_url"):
        try:
            return fetch_parquet(info["parquet_url"], keys, bbox, state)
        except Exception as e:  # noqa: BLE001
            notice("Parquet unavailable", f"{type(e).__name__}: {str(e)[:300]} - using the zip instead")
    return fetch_zip(info["output_url"], keys, bbox, state)


def address(p):
    if p.get("addr:street_address"):
        return p["addr:street_address"]
    street = " ".join(x for x in (p.get("addr:housenumber"), p.get("addr:street")) if x)
    if street:
        return street + (f" {p['addr:unit']}" if p.get("addr:unit") else "")
    return p.get("addr:full")


def categorise(p, cmap):
    """Return (our slug, source label, exact?) or None when the place is not food and drink."""
    for key, slug in cmap["primary"].items():
        k, v = key.split("=", 1)
        if p.get(k) == v:
            if key in cmap["refine"]:
                for c in (p.get("cuisine") or "").split(";"):
                    c = c.strip().lower()
                    if c in cmap["cuisine"]:
                        return cmap["cuisine"][c], f"{key};cuisine={c}", True
            # Exact when the tag alone says enough; a plain restaurant without a known cuisine is not.
            return slug, key, key not in ("amenity=restaurant", "amenity=food_court")
    return None


def transform(rows, cmap):
    out, skipped, spiders = [], Counter(), Counter()
    for r in rows:
        p = r["properties"] if isinstance(r["properties"], dict) else json.loads(r["properties"] or "{}")
        cat = categorise(p, cmap)
        if not cat:
            skipped["not food and drink"] += 1
            continue
        name = p.get("name") or p.get("brand")
        if not name:
            skipped["no name"] += 1
            continue
        if r["lon"] is None or r["lat"] is None:
            skipped["no location"] += 1
            continue
        slug, label, exact = cat
        spiders[r["spider"]] += 1
        out.append({
            "source_record_id": r["id"], "upstream_dataset": r["spider"], "license": LICENSE,
            "name": name, "address": address(p), "city": p.get("addr:city"),
            "state": norm_state(p.get("addr:state")) or p.get("addr:state"), "postal_code": p.get("addr:postcode"),
            "phone": (p.get("phone") or "").split(";")[0].strip() or None,
            "website": (p.get("website") or "").split(";")[0].strip() or None,
            "lon": r["lon"], "lat": r["lat"], "source_category": label, "category_slug": slug,
            "source_confidence": None,
            "payload": {"category_mapped": exact, "brand": p.get("brand"), "brand_wikidata": p.get("brand:wikidata"),
                        "branch": p.get("branch"), "opening_hours": p.get("opening_hours"), "ref": p.get("ref"),
                        "operating_status": "open"},
        })
    return out, skipped, spiders


def size():
    """Count food and drink places per state across the whole United States."""
    info = latest_run()
    cmap = {k: v for k, v in json.loads((HERE / "alltheplaces_category_map.json").read_text()).items() if not k.startswith("_")}
    records, skipped, spiders = transform(fetch(info, list(cmap["primary"].keys())), cmap)
    rows = {}
    for r in records:
        s = rows.setdefault(norm_state(r["state"]) or "(unknown)", {"places": 0, "with_phone": 0, "with_website": 0})
        s["places"] += 1
        s["with_phone"] += bool(r["phone"])
        s["with_website"] += bool(r["website"])
    report("All the Places", info["run_id"], rows, {
        "Chains (spiders) with food and drink places": f"{len(spiders):,}",
        "Biggest chains": ", ".join(f"{k} {v:,}" for k, v in spiders.most_common(15)),
        "Left out": ", ".join(f"{k} {v:,}" for k, v in skipped.most_common()) or "none",
    })


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", default="latest", help="All the Places run id, or 'latest'")
    ap.add_argument("--bbox", help="xmin,ymin,xmax,ymax")
    ap.add_argument("--state", help="two-letter state code, e.g. VA")
    ap.add_argument("--mode", choices=["dry-run", "load", "size"], default="dry-run")
    ap.add_argument("--out", default="alltheplaces.csv")
    a = ap.parse_args()
    if a.mode == "size":
        size()
        return
    if bool(a.bbox) == bool(a.state):
        sys.exit("give exactly one of --bbox or --state")
    state = norm_state(a.state) if a.state else None
    if a.state and not state:
        sys.exit(f"unknown state {a.state}")
    bbox = [float(x) for x in a.bbox.split(",")] if a.bbox else None

    info = latest_run()
    if a.run != "latest" and a.run != info["run_id"]:
        sys.exit(f"only the latest run ({info['run_id']}) is published as one file; asked for {a.run}")
    notice("Release", f"All the Places run {info['run_id']} ({info.get('spiders')} spiders)")

    cmap = {k: v for k, v in json.loads((HERE / "alltheplaces_category_map.json").read_text()).items() if not k.startswith("_")}
    rows = fetch(info, list(cmap["primary"].keys()), bbox, state)
    records, skipped, spiders = transform(rows, cmap)
    summarise(records, skipped, {"Matched rows": len(rows), "Top spiders": dict(spiders.most_common(30))})
    write_csv(records, a.out)
    if a.mode == "load":
        scope = f"state:{state}" if state else f"bbox:{a.bbox}"
        load(records, "alltheplaces", info["run_id"], scope, LICENSE)


if __name__ == "__main__":
    run(main)
