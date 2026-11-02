"""Shared plumbing for source adapters.

An adapter's only job is to turn one source's data into records of this shape:

    {"source_record_id": str,        # the source's own stable id
     "upstream_dataset": str | None, # where inside the source it came from
     "license": str,                 # licence of this record
     "name", "address", "city", "state", "postal_code", "phone", "website": str | None,
     "lon", "lat": float,
     "source_category": str,         # the source's own category label
     "category_slug": str,           # our category slug
     "source_confidence": float | None,
     "payload": dict}                # everything else worth keeping; must include
                                     # "category_mapped" and, if known, "operating_status"

Everything after that (creating the run, loading, reconciling, reporting) is shared here.
"""
import csv, json, os, sys, time, traceback, urllib.error, urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

BATCH = 500        # records per call over the API
DB_BATCH = 1000    # records per call over a direct database connection
USER_AGENT = "so-much-sushi-ingest/1.0 (+https://github.com/770MOS/so-much-sushi)"

# The areas a nationwide load is split into: 50 states, DC and Puerto Rico. Records whose
# state is missing or not one of these go in one extra run, scoped 'state:none'.
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
NO_STATE = "none"


def state_code(value):
    """Two-letter code from a code, a full name or "US-VA"; None when it is not a US state."""
    v = (value or "").strip()
    if v.upper().startswith("US-"):
        v = v[3:]
    if v.upper() in STATE_NAMES:
        return v.upper()
    return _BY_NAME.get(v.lower())


def parse_states(value):
    """'all' -> every state plus 'none'; 'VA,MD' -> those, in that order."""
    if (value or "").strip().lower() == "all":
        return sorted(STATE_NAMES) + [NO_STATE]
    out = []
    for part in (value or "").split(","):
        part = part.strip()
        if not part:
            continue
        code = NO_STATE if part.lower() == NO_STATE else state_code(part)
        if not code:
            sys.exit(f"unknown state {part!r}")
        if code not in out:
            out.append(code)
    if not out:
        sys.exit("no states given")
    return out


def get_json(url, timeout=60):
    """GET a JSON document with an explicit User-Agent (some hosts refuse Python's default)."""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def run(main):
    """Run an adapter's main(); on any error, put the reason in a GitHub annotation and exit 1."""
    try:
        main()
    except SystemExit as e:
        if e.code not in (0, None):
            if os.environ.get("GITHUB_ACTIONS"):
                print(f"::error title=Ingest stopped::{str(e.code)[:3000]}")
        raise
    except Exception as e:
        traceback.print_exc()
        if os.environ.get("GITHUB_ACTIONS"):
            where = traceback.extract_tb(e.__traceback__)[-1]
            print(f"::error title=Ingest failed::{type(e).__name__}: {str(e)[:2500]} "
                  f"(at {Path(where.filename).name}:{where.lineno})")
        sys.exit(1)


def notice(title, text):
    """Also surface a line as a GitHub Actions annotation, which is readable without the full log."""
    print(f"{title}: {text}")
    if os.environ.get("GITHUB_ACTIONS"):
        print(f"::notice title={title}::{str(text)[:3500]}")


class Rest:
    def __init__(self):
        self.url = os.environ.get("SUPABASE_URL", "").rstrip("/")
        self.key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if not self.url or not self.key:
            sys.exit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required in load mode")
        self.url += "/rest/v1"

    def call(self, method, path, body=None, prefer=None):
        headers = {"apikey": self.key, "Authorization": f"Bearer {self.key}", "Content-Type": "application/json"}
        if prefer:
            headers["Prefer"] = prefer
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.url + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=600) as resp:
                text = resp.read().decode()
                return json.loads(text) if text else None
        except urllib.error.HTTPError as e:
            sys.exit(f"{method} {path} failed: {e.code} {e.read().decode()[:500]}")


def summarise(records, skipped, extra=None):
    cats = Counter(r["category_slug"] for r in records)
    lic = Counter(r["license"] for r in records)
    notice("Counts", f"kept {len(records)}; skipped {dict(skipped)}; "
                     f"phone {sum(1 for r in records if r['phone'])}; website {sum(1 for r in records if r['website'])}")
    notice("Licences", dict(lic))
    notice("Categories", dict(cats.most_common(40)))
    unmapped = Counter(r["source_category"] for r in records if not r["payload"].get("category_mapped"))
    if unmapped:
        notice("Not exactly mapped", dict(unmapped.most_common(40)))
    for title, text in (extra or {}).items():
        notice(title, text)


def write_csv(records, path):
    with open(path, "w", newline="") as f:
        cols = [c for c in records[0] if c != "payload"] if records else []
        w = csv.DictWriter(f, fieldnames=cols + ["category_mapped"])
        w.writeheader()
        for r in records:
            w.writerow({**{c: r[c] for c in cols}, "category_mapped": r["payload"].get("category_mapped")})


def reconcile(rest, run_id, decided_by):
    """Reconcile a run. Over a direct database connection when DATABASE_URL is set, because the
    API stops any statement after a few seconds and a large load takes longer than that."""
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        return rest.call("POST", "/rpc/reconcile_run", {"p_run_id": run_id, "p_decided_by": decided_by})
    import psycopg  # installed by the workflow
    with psycopg.connect(db_url, autocommit=True) as conn:
        conn.execute("SET statement_timeout = '30min'")
        row = conn.execute("SELECT public.reconcile_run(%s, %s)", (run_id, decided_by)).fetchone()
        return row[0]


class Db:
    """A direct database connection for loads (DATABASE_URL): no API time limits, and one
    connection for a whole nationwide load."""

    def __init__(self, url=None):
        import psycopg  # installed by the workflow
        from psycopg.types.json import Jsonb
        self.Jsonb = Jsonb
        url = url or os.environ.get("DATABASE_URL")
        if not url:
            sys.exit("DATABASE_URL is required")
        self.conn = psycopg.connect(url, autocommit=True)
        # A big state's reconcile can run for a long time; nothing here should be cut off.
        self.conn.execute("SET statement_timeout = '4h'")

    def one(self, sql, args=()):
        return self.conn.execute(sql, args).fetchone()

    def source(self, code):
        row = self.one("SELECT id, is_active, license_class FROM public.sources WHERE code = %s", (code,))
        if not row or not row[1]:
            sys.exit(f"source {code} is missing or inactive in the register; refusing to load")
        if row[2] == "share_alike":
            sys.exit(f"source {code} is share-alike and must not be loaded")
        return row[0]

    def state_of_scope(self, source_id, release, scope):
        """('done', id) reconciled; ('loaded', id) loaded but not reconciled; (None, None) to do.
        Runs this job started and never finished are closed as failed, so they never count
        as a load of the area."""
        self.conn.execute(
            "UPDATE public.source_runs SET status = 'failed', finished_at = now(), "
            "error = 'stopped before the load finished; loaded again by a later run' "
            "WHERE source_id = %s AND release IS NOT DISTINCT FROM %s AND scope = %s AND status = 'running'",
            (source_id, release, scope))
        row = self.one(
            "SELECT id, stats ? 'reconcile' FROM public.source_runs WHERE source_id = %s "
            "AND release IS NOT DISTINCT FROM %s AND scope = %s AND status = 'succeeded' ORDER BY id DESC LIMIT 1",
            (source_id, release, scope))
        if not row:
            return None, None
        return ("done" if row[1] else "loaded"), row[0]

    def start_run(self, source_id, release, scope, run_license):
        return self.one("INSERT INTO public.source_runs (source_id, release, scope, license) "
                        "VALUES (%s, %s, %s, %s) RETURNING id", (source_id, release, scope, run_license))[0]

    def ingest(self, run_id, records):
        done = 0
        for i in range(0, len(records), DB_BATCH):
            done += self.one("SELECT public.ingest_source_records(%s, %s)",
                             (run_id, self.Jsonb(records[i:i + DB_BATCH])))[0]
        return done

    def finish_run(self, run_id, count, records):
        self.conn.execute(
            "UPDATE public.source_runs SET status = 'succeeded', record_count = %s, finished_at = now(), "
            "stats = stats || %s WHERE id = %s",
            (count, self.Jsonb({"by_license": dict(Counter(r["license"] for r in records)),
                                "by_dataset": dict(Counter(r["upstream_dataset"] for r in records))}), run_id))

    def analyze(self):
        """Refresh the planner's row counts. On a database that starts empty, the first big load
        otherwise leaves it planning for empty tables, and reconcile slows down badly."""
        self.conn.execute("ANALYZE public.source_records, public.source_record_versions, public.entities, "
                          "public.entity_field_provenance, public.entity_categories, public.change_events")

    def reconcile(self, run_id, decided_by):
        return self.one("SELECT public.reconcile_run(%s, %s)", (run_id, decided_by))[0]


def load_by_state(records_for, source_code, release, run_license, states):
    """Load one run per state, in order, each reconciled before the next starts.

    records_for(code) returns that state's records ('none': no recognised state), so only
    one state is held in memory at a time. Safe to run again: states already loaded and
    reconciled for this release are skipped, and a state whose load finished but whose
    reconcile did not is only reconciled.

    Results go out as one annotation per 10 states (GitHub shows only about 10 per step)
    and as a table on the run's summary page."""
    db = Db()
    source_id = db.source(source_code)
    totals, pending, done_lines = Counter(), [], []

    def flush():
        if pending:
            notice(f"{source_code}: states {pending[0].split(' ')[0]} to {pending[-1].split(' ')[0]}", "%0A".join(pending))
            pending.clear()

    for code in states:
        scope = f"state:{code}"
        status, run_id = db.state_of_scope(source_id, release, scope)
        if status == "done":
            print(f"{code}: already loaded as run {run_id}; skipped")
            totals["skipped"] += 1
            continue
        t0 = time.time()
        records = records_for(code) if status != "loaded" else []
        if status != "loaded":
            if not records:
                print(f"{code}: {source_code} has no records here")
                continue
            run_id = db.start_run(source_id, release, scope, run_license)
            count = db.ingest(run_id, records)
            db.finish_run(run_id, count, records)
            totals["records"] += count
        db.analyze()
        t1 = time.time()
        result = db.reconcile(run_id, f"ingest:{source_code}") or {}
        totals["states"] += 1
        build = result.get("build") or {}
        review = sum(result.get(k, 0) for k in ("value_changes_for_review", "status_changes_for_review", "missing_for_review"))
        line = (f"{code} run {run_id}: {len(records):,} records, load {t1 - t0:,.0f}s, reconcile {time.time() - t1:,.0f}s, "
                f"new places {build.get('entities_created', 0):,}, joined {result.get('attached_to_existing_places', 0):,}, "
                f"possible duplicates {result.get('possible_duplicates_of_existing', 0):,}, for review {review:,}")
        print(line, flush=True)
        pending.append(line)
        done_lines.append(line)
        if len(pending) == 10:
            flush()
    flush()
    notice("Done", f"{source_code} {release}: {totals['states']} areas loaded, {totals['records']:,} records, "
                   f"{totals['skipped']} already done")
    if os.environ.get("GITHUB_STEP_SUMMARY") and done_lines:
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(f"### {source_code} {release}\n\n" + "\n".join(f"- {x}" for x in done_lines) + "\n\n")


def load(records, source_code, release, scope, run_license):
    """Create a run, upsert the records, mark the run succeeded, then reconcile it."""
    if os.environ.get("DATABASE_URL"):
        db = Db()
        run_id = db.start_run(db.source(source_code), release, scope, run_license)
        count = db.ingest(run_id, records)
        db.finish_run(run_id, count, records)
        notice("Loaded", f"{count} records as run {run_id} ({source_code}, {release}, {scope})")
        result = db.reconcile(run_id, f"ingest:{source_code}")
        print("reconcile:", json.dumps(result, indent=2))
        notice("Reconcile", "%0A".join(f"{k.replace('_', ' ')}: {v}" for k, v in (result or {}).items()
                                        if k not in ("build", "finished_at")))
        return
    rest = Rest()
    src = rest.call("GET", f"/sources?code=eq.{source_code}&select=id,is_active,license_class")
    if not src or not src[0]["is_active"]:
        sys.exit(f"source {source_code} is missing or inactive in the register; refusing to load")
    if src[0]["license_class"] == "share_alike":
        sys.exit(f"source {source_code} is share-alike and must not be loaded")
    run = rest.call("POST", "/source_runs", {"source_id": src[0]["id"], "release": release, "scope": scope,
                                             "license": run_license}, prefer="return=representation")[0]
    done = 0
    for i in range(0, len(records), BATCH):
        done += rest.call("POST", "/rpc/ingest_source_records", {"p_run_id": run["id"], "p_records": records[i:i + BATCH]})
    rest.call("PATCH", f"/source_runs?id=eq.{run['id']}", {
        "status": "succeeded", "record_count": done, "finished_at": datetime.now(timezone.utc).isoformat(),
        "stats": {"by_license": dict(Counter(r["license"] for r in records)),
                  "by_dataset": dict(Counter(r["upstream_dataset"] for r in records))}})
    notice("Loaded", f"{done} records as run {run['id']} ({source_code}, {release}, {scope})")
    result = reconcile(rest, run["id"], f"ingest:{source_code}")
    print("reconcile:", json.dumps(result, indent=2))
    notice("Reconcile", "%0A".join(f"{k.replace('_', ' ')}: {v}" for k, v in (result or {}).items()
                                    if k not in ("build", "finished_at")))
