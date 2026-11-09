#!/usr/bin/env python3
"""Load the place-name list behind location suggestions (public.localities).

Sources, all US Census Bureau (public domain, US government work):
  * Gazetteer, places: every city, town, village, borough and census-designated place, with
    its internal point.                     {year}_Gaz_place_national.zip
  * Gazetteer, ZIP code tabulation areas: every ZIP area with its internal point.
                                            {year}_Gaz_zcta_national.zip
  * Populations, used only to order far-away suggestions (places without one still load):
    2020 census counts from the Census API when it answers (these include census-designated
    places), otherwise the latest city and town population estimates file (incorporated
    places only).
  * 2020 ZIP-area-to-place relationship file: each ZIP area's main place (largest land
    overlap), shown as the suggestion's second line, "22201 · Arlington, VA". A ZIP area that
    overlaps no place gets the nearest place within 30 km, "near Foo, VA".
Plus a short hand-written list: New York City's five boroughs (not Census places) and
nicknames ("NYC", "Philly").

Everything is replaced in one transaction, so suggestions never see a half-loaded list.

  DATABASE_URL=postgresql://... python scripts/localities/load_census.py [--year 2024]
"""
import argparse, csv, io, json, os, re, sys, time, urllib.request, zipfile
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "ingest"))
from common import STATE_NAMES  # noqa: E402  (two-letter code -> name, incl. DC and PR)

USER_AGENT = "so-much-sushi-localities/1.0 (+https://github.com/770MOS/so-much-sushi)"
GAZ = "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/{year}_Gazetteer/{year}_Gaz_{kind}_national.zip"
POP_URL = "https://api.census.gov/data/2020/dec/pl?get=P1_001N&for=place:*&in=state:*"
POPEST_URLS = [  # newest first; the first that downloads is used
    "https://www2.census.gov/programs-surveys/popest/datasets/2020-2024/cities/totals/sub-est2024.csv",
    "https://www2.census.gov/programs-surveys/popest/datasets/2020-2023/cities/totals/sub-est2023.csv",
]
REL_URL = "https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_place20_natl.txt"

# What the Census appends to a place's name, by its legal/statistical area description code
# (LSAD). Stripped for display: "Abbeville city" -> "Abbeville", "Arlington CDP" -> "Arlington".
LSAD_SUFFIX = {
    "21": "borough", "25": "city", "35": "metro township", "37": "municipality", "43": "town",
    "44": "township", "47": "village", "53": "city and borough", "55": "comunidad", "57": "CDP",
    "62": "zona urbana", "CG": "consolidated government", "CN": "corporation",
    "MG": "metropolitan government", "MT": "metro government", "UC": "urban county",
    "UG": "unified government",
}
# For "(balance)" names and codes without a fixed suffix ("00"): any of these, longest first.
DESCRIPTORS = sorted({*LSAD_SUFFIX.values(), "city", "town", "village", "borough"}, key=len, reverse=True)
# Consolidated governments whose Census name is long; shown by the name people use.
DISPLAY_NAMES = {
    ("TN", "Nashville-Davidson"): "Nashville",
    ("KY", "Louisville/Jefferson County"): "Louisville",
    ("KY", "Lexington-Fayette"): "Lexington",
    ("HI", "Urban Honolulu"): "Honolulu",
    ("GA", "Augusta-Richmond County"): "Augusta",
    ("GA", "Athens-Clarke County"): "Athens",
    ("GA", "Macon-Bibb County"): "Macon",
    ("ID", "Boise City"): "Boise",
    ("MT", "Butte-Silver Bow"): "Butte",
    ("MT", "Anaconda-Deer Lodge County"): "Anaconda",
    ("TN", "Lynchburg, Moore County"): "Lynchburg",
    ("GA", "Cusseta-Chattahoochee County"): "Cusseta",
    ("GA", "Georgetown-Quitman County"): "Georgetown",
}
NICKNAMES = {
    ("NY", "New York"): ["NYC", "New York City"],
    ("PA", "Philadelphia"): ["Philly"],
    ("CA", "Los Angeles"): ["LA", "L.A."],
    ("CA", "San Francisco"): ["SF", "San Fran"],
    ("DC", "Washington"): ["DC", "D.C.", "Washington DC"],
    ("NV", "Las Vegas"): ["Vegas"],
    ("LA", "New Orleans"): ["NOLA"],
    ("IN", "Indianapolis"): ["Indy"],
    ("GA", "Atlanta"): ["ATL"],
}
# New York City's boroughs are counties, not Census places, but people search by them.
# Points are the boroughs' centres; populations are 2020 census counts.
BOROUGHS = [
    ("nyc-manhattan", "Manhattan", 40.7831, -73.9712, 1694251),
    ("nyc-brooklyn", "Brooklyn", 40.6782, -73.9442, 2736074),
    ("nyc-queens", "Queens", 40.7282, -73.7949, 2405464),
    ("nyc-bronx", "Bronx", 40.8448, -73.8648, 1472654),
    ("nyc-staten-island", "Staten Island", 40.5795, -74.1502, 495747),
]
# Each pair is swapped both ways to make extra names: "St. Louis" is also "Saint Louis".
SWAPS = [("Saint", "St"), ("Sainte", "Ste"), ("Fort", "Ft"), ("Mount", "Mt")]


def note(title, message):
    """A GitHub Actions annotation (shown on the run's page); plain output elsewhere."""
    msg = message.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::notice title={title}::{msg}" if os.environ.get("GITHUB_ACTIONS") else f"[{title}]\n{message}")


FROM_DIR = None  # --from-dir: read the files from a folder instead of downloading (offline tests)


def fetch(url, tries=4):
    if FROM_DIR:
        name = "population_2020.json" if "api.census.gov" in url else url.rsplit("/", 1)[1]
        return (Path(FROM_DIR) / name).read_bytes()
    for attempt in range(1, tries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=180) as r:
                return r.read()
        except Exception as exc:  # network hiccups: retry, then give up loudly
            if attempt == tries:
                raise RuntimeError(f"could not download {url}: {exc}") from exc
            time.sleep(5 * attempt)


def decode(data):
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("latin-1")


def read_gazetteer(year, kind):
    """Rows of a Gazetteer file as dicts with stripped keys and values."""
    url = GAZ.format(year=year, kind=kind)
    with zipfile.ZipFile(io.BytesIO(fetch(url))) as z:
        name = next(n for n in z.namelist() if n.endswith(".txt"))
        text = decode(z.read(name))
    reader = csv.reader(io.StringIO(text), delimiter="\t")
    header = [h.strip() for h in next(reader)]
    rows = [dict(zip(header, (v.strip() for v in row))) for row in reader if row]
    return url, header, rows


def clean_place_name(name, lsad):
    """The Census name without its description: "Abbeville city" -> "Abbeville". The code's
    own suffix is removed when present; any known description only for "(balance)" names and
    codes with no fixed suffix, so a name like "Carson City" keeps its "City"."""
    n = name.strip()
    balance = n.endswith(" (balance)")
    if balance:
        n = n[: -len(" (balance)")]
    suffix = LSAD_SUFFIX.get(lsad)
    if suffix and n.endswith(" " + suffix):
        return n[: -len(suffix) - 1]
    if balance or lsad not in LSAD_SUFFIX:
        for d in DESCRIPTORS:
            if n.endswith(" " + d):
                return n[: -len(d) - 1]
    return n


def swap_variants(name):
    out = set()
    for a, b in SWAPS:
        for x, y in ((a, b), (b, a)):
            pattern = rf"\b{x}\b\.?" if len(x) <= 3 else rf"\b{x}\b"
            if re.search(pattern, name):
                out.add(re.sub(pattern, y, name))
    return out


def names_for(display, official, state, aliases):
    """(name, with_state) for every string the place can be found by, alone and with its state."""
    bases = {display, official, *aliases}
    m = re.match(r"^(.*?)\s*\((.+)\)$", official)  # "San Buenaventura (Ventura)"
    if m:
        bases.update({m.group(1), m.group(2)})
    for b in list(bases):
        bases.update(swap_variants(b))
    out = set()
    for b in bases:
        b = b.strip()
        if not b:
            continue
        out.add((b, False))
        out.update({(f"{b} {state}", True), (f"{b} {STATE_NAMES[state]}", True)})
    # The same text as both a plain name and a "name + state" (e.g. 'Washington DC' as a
    # nickname) is kept once, as a plain name.
    plain = {n for n, w in out if not w}
    return {(n, w) for n, w in out if not (w and n in plain)}


def load_populations():
    """Place GEOID -> population, and where it came from."""
    problems = []
    raw = b""
    try:
        raw = fetch(POP_URL, tries=2)
        rows = json.loads(raw)
        header = rows[0]
        i_pop, i_state, i_place = header.index("P1_001N"), header.index("state"), header.index("place")
        pops = {r[i_state] + r[i_place]: int(r[i_pop]) for r in rows[1:] if r[i_pop].isdigit()}
        if pops:
            return pops, "2020 census counts (Census API)"
    except Exception as exc:
        problems.append(f"Census API: {exc}; it answered: {raw[:200]!r}")
    for url in POPEST_URLS:
        try:
            reader = csv.DictReader(io.StringIO(decode(fetch(url, tries=2))))
            columns = [c for c in (reader.fieldnames or []) if re.fullmatch(r"POPESTIMATE\d{4}", c)]
            latest = max(columns)
            pops = {}
            for r in reader:
                # 162: incorporated place; 170: consolidated city. Counties and towns-within-
                # counties (minor civil divisions) have other levels and are skipped.
                if r.get("SUMLEV") not in ("162", "170") or not (r.get(latest) or "").isdigit():
                    continue
                geoid = r["STATE"].zfill(2) + r["PLACE"].zfill(5)
                pops[geoid] = max(pops.get(geoid, 0), int(r[latest]))
            if pops:
                note("Populations", "\n".join(problems + [f"Used {latest} from {url}"]))
                return pops, f"{latest} estimates ({url.rsplit('/', 1)[1]})"
        except Exception as exc:
            problems.append(f"{url}: {exc}")
    note("Populations not loaded", "\n".join(problems) + "\nFar-away suggestions will be ordered by name instead.")
    return {}, "none"


def load_zip_main_places():
    """ZIP code -> (place GEOID, land area shared): the place covering most of the ZIP's land."""
    try:
        text = decode(fetch(REL_URL))
    except Exception as exc:
        note("ZIP-to-place file not loaded", f"{exc}. ZIP suggestions will name the nearest place instead.")
        return {}
    reader = csv.DictReader(io.StringIO(text), delimiter="|")
    best = {}
    for row in reader:
        z, p = (row.get("GEOID_ZCTA5_20") or "").strip(), (row.get("GEOID_PLACE_20") or "").strip()
        if not z or not p:
            continue
        area = int((row.get("AREALAND_PART") or "0").strip() or 0)
        if area > best.get(z, ("", -1))[1]:
            best[z] = (p, area)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--year", default="2024", help="Gazetteer year")
    ap.add_argument("--samples", default="albany|new york, ny|nyc|albny|st louis|saint paul|arlington|"
                    "washington dc|pittsburg|brooklyn|nashville|222|10001|san juan pr|winston salem|new|"
                    "carson city|kansas city|salt lake city|oklahoma city|boise|honolulu|lexington ky|"
                    "louisville|indianapolis|juneau|anchorage|milford ct|springfield|portland|chicgo")
    ap.add_argument("--from-dir", help="read the Census files from this folder instead of downloading")
    args = ap.parse_args()
    global FROM_DIR
    FROM_DIR = args.from_dir
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        sys.exit("DATABASE_URL is required")
    source = f"census_gazetteer_{args.year}"

    place_url, place_header, place_rows = read_gazetteer(args.year, "place")
    zcta_url, zcta_header, zcta_rows = read_gazetteer(args.year, "zcta")
    pops, pop_source = load_populations()
    zip_main = load_zip_main_places()

    lsad_examples = defaultdict(list)
    places, skipped = [], Counter()
    for r in place_rows:
        state = r.get("USPS", "")
        if state not in STATE_NAMES:
            skipped["state not covered"] += 1
            continue
        try:
            lat, lng = float(r["INTPTLAT"]), float(r["INTPTLONG"])
        except (KeyError, ValueError):
            skipped["no point"] += 1
            continue
        official = clean_place_name(r["NAME"], r.get("LSAD", ""))
        display = DISPLAY_NAMES.get((state, official), official)
        display = re.sub(r"\s*\(.+\)$", "", display) or display
        if len(lsad_examples[r.get("LSAD", "")]) < 4:
            lsad_examples[r.get("LSAD", "")].append(f"{r['NAME']} -> {display}")
        places.append({
            "code": r["GEOID"], "name": display, "official": official, "state": state,
            "lat": lat, "lng": lng, "population": pops.get(r["GEOID"]),
            "aliases": NICKNAMES.get((state, display), []),
            "rank": (pops.get(r["GEOID"]) or -1, r.get("LSAD") != "57", float(r.get("ALAND") or 0)),
        })
    for code, name, lat, lng, pop in BOROUGHS:
        places.append({"code": code, "name": name, "official": name, "state": "NY", "lat": lat,
                       "lng": lng, "population": pop, "aliases": [], "rank": (pop, True, 0.0)})

    # Two places with the same name in the same state ("San Juan, TX" twice) would show as two
    # identical suggestions. Keep the bigger one: more people, then a town over a census-
    # designated place, then more land.
    best = {}
    for p in places:
        k = (p["name"], p["state"])
        if k not in best or p["rank"] > best[k]["rank"]:
            best[k] = p
    duplicates = len(places) - len(best)
    all_places = places
    places = list(best.values())

    by_geoid = {p["code"]: p for p in all_places}  # a ZIP's main place may be a dropped duplicate
    zips = []
    for r in zcta_rows:
        code = r.get("GEOID", "")
        try:
            lat, lng = float(r["INTPTLAT"]), float(r["INTPTLONG"])
        except (KeyError, ValueError):
            skipped["ZIP without point"] += 1
            continue
        main_place = by_geoid.get(zip_main.get(code, ("", 0))[0])
        zips.append({
            "code": code, "lat": lat, "lng": lng,
            "state": main_place["state"] if main_place else None,
            "city": main_place["name"] if main_place else None,
            "detail": f"{main_place['name']}, {main_place['state']}" if main_place else None,
        })

    import psycopg  # installed by the workflow
    with psycopg.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.execute("SET search_path = public, extensions")
            cur.execute("DELETE FROM localities")
            with cur.copy("COPY localities (kind, code, name, state, label, detail, city, population, location, source) "
                          "FROM STDIN") as copy:
                for p in places:
                    copy.write_row(("place", p["code"], p["name"], p["state"], f"{p['name']}, {p['state']}", None,
                                    p["name"], p["population"], f"SRID=4326;POINT({p['lng']} {p['lat']})", source))
                for z in zips:
                    copy.write_row(("zip", z["code"], z["code"], z["state"], z["code"], z["detail"], z["city"], None,
                                    f"SRID=4326;POINT({z['lng']} {z['lat']})", source))
            cur.execute("SELECT code, id FROM localities WHERE kind = 'place'")
            ids = dict(cur.fetchall())
            name_count = 0
            with cur.copy("COPY locality_names (locality_id, name, with_state) FROM STDIN") as copy:
                for p in places:
                    for n, with_state in names_for(p["name"], p["official"], p["state"], p["aliases"]):
                        copy.write_row((ids[p["code"]], n, with_state))
                        name_count += 1
            # ZIP areas that overlap no place: the nearest place within 30 km.
            cur.execute("""
                UPDATE localities z
                SET detail = 'near ' || near.label, city = near.name, state = near.state
                FROM localities zz
                CROSS JOIN LATERAL (
                  SELECT p.label, p.name, p.state, p.location FROM localities p
                  WHERE p.kind = 'place' ORDER BY p.location <-> zz.location LIMIT 1) near
                WHERE z.id = zz.id AND z.kind = 'zip' AND z.detail IS NULL
                  AND ST_DWithin(near.location, zz.location, 30000)""")
            near_count = cur.rowcount
            cur.execute("ANALYZE localities")
            cur.execute("ANALYZE locality_names")
            cur.execute("SELECT count(*) FILTER (WHERE kind = 'place'), count(*) FILTER (WHERE kind = 'zip'), "
                        "count(*) FILTER (WHERE kind = 'zip' AND detail IS NULL), "
                        "count(*) FILTER (WHERE kind = 'place' AND population IS NULL) FROM localities")
            n_places, n_zips, zip_no_detail, place_no_pop = cur.fetchone()
        conn.commit()

        note("Loaded", "\n".join([
            f"source: {source}",
            f"places: {n_places:,} (same name and state as a bigger place, left out: {duplicates:,}); "
            f"names to match on: {name_count:,}",
            f"populations: {pop_source}; places without one: {place_no_pop:,}",
            f"ZIP areas: {n_zips:,} (main place from the relationship file: {len(zip_main):,}; "
            f"nearest place within 30 km: {near_count:,}; no place named: {zip_no_detail:,})",
            f"skipped: {dict(skipped) or 'none'}",
            f"place file columns: {', '.join(place_header)}",
            f"ZIP file columns: {', '.join(zcta_header)}",
        ]))
        note("Name clean-up by LSAD code", "\n".join(
            f"{code or '(blank)'}: " + " | ".join(ex) for code, ex in sorted(lsad_examples.items())))

        # What the location box would suggest, typed from Washington, DC.
        lines = []
        with conn.cursor() as cur:
            for q in args.samples.split("|"):
                cur.execute("SELECT label, detail FROM suggest_localities(%s, 38.9, -77.04, 5)", (q,))
                got = [f"{lab}" + (f" ({det})" if det else "") for lab, det in cur.fetchall()]
                lines.append(f"{q!r}: " + ("; ".join(got) or "(none)"))
        note("Sample suggestions (typed in DC)", "\n".join(lines))
    for url in (place_url, zcta_url, POP_URL, REL_URL):
        print("source:", url)


if __name__ == "__main__":
    main()
