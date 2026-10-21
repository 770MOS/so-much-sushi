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
import csv, json, os, sys, traceback, urllib.error, urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

BATCH = 500
USER_AGENT = "so-much-sushi-ingest/1.0 (+https://github.com/770MOS/so-much-sushi)"


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


def load(records, source_code, release, scope, run_license):
    """Create a run, upsert the records, mark the run succeeded, then reconcile it."""
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
