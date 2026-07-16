// Backfills entities.osm_id by matching every entity against a fresh
// Overpass pull for Arlington, VA (same area/tags query as
// scripts/bulk-import-overpass.mjs) using the same fuzzy
// distance+name-similarity approach that script already uses for
// duplicate detection - just pointed the other direction: instead of
// "is this new element a duplicate of something we have," it's "which
// existing entity does this element actually correspond to."
//
// On a confident match: sets both osm_id and source_code = 'osm' (even if
// the entity's source_code was already 'osm' or was 'manual' - a manually
// entered restaurant that also happens to exist in OSM still gets tied to
// it). Entities with no confident match are left completely untouched,
// including source_code - whatever they already had (from the
// entities.source_code backfill migration) stays as-is.
//
// Usage:
//   node scripts/backfill-osm-id.mjs             # dry run, no writes
//   node scripts/backfill-osm-id.mjs --confirm    # actually updates entities
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const OVERPASS_URL = "https://overpass-api.de/api/interpreter";
const OVERPASS_USER_AGENT =
  "so-much-sushi-osm-id-backfill/1.0 (https://github.com/770MOS/so-much-sushi)";

// Same Arlington County query as bulk-import-overpass.mjs.
const ARLINGTON_AREA_ID = 3600962190;
const CENTER = { lat: 38.8769326, lng: -77.0893094 };
const EXISTING_SEARCH_RADIUS_MILES = 15;

// Confident-match thresholds - same tolerances bulk-import-overpass.mjs
// already uses for its own duplicate detection.
const MATCH_DISTANCE_MILES = 0.1;
const MATCH_NAME_SIMILARITY = 0.82;

// Wider net for "close but not quite" - a candidate inside this net but
// outside the confident thresholds above gets flagged for manual review
// instead of silently skipped or silently matched.
const REVIEW_DISTANCE_MILES = 0.2;
const REVIEW_NAME_SIMILARITY = 0.55;

// Two extra nets applied only to entities that miss the review net above -
// each catches a different kind of "close but not quite" that a single
// combined distance+name gate misses:
//   - two places essentially in the same building/address, but with
//     unrelated-looking names (rebrand? closure+replacement? wrong stored
//     coordinates?) - distance alone is the signal here, name similarity
//     is ignored.
//   - a near-identical name found somewhere else in the county entirely -
//     name alone is the signal, distance is ignored (could mean our
//     entity's stored coordinates are wrong, or this is genuinely a
//     second location of the same chain).
const SAME_ADDRESS_DISTANCE_MILES = 0.05;
const HIGH_NAME_SIMILARITY = 0.85;

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !serviceRoleKey) {
  console.error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env.local");
  process.exit(1);
}

const supabase = createClient(supabaseUrl, serviceRoleKey);
const CONFIRM = process.argv.includes("--confirm");

// --- Overpass fetch (identical query to bulk-import-overpass.mjs) ---

async function fetchOverpassElements() {
  const query = `
    [out:json][timeout:90];
    area(${ARLINGTON_AREA_ID})->.searchArea;
    (
      node["amenity"~"^(restaurant|cafe|bar|pub)$"](area.searchArea);
      way["amenity"~"^(restaurant|cafe|bar|pub)$"](area.searchArea);
    );
    out center;
  `.trim();

  const res = await fetch(OVERPASS_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "User-Agent": OVERPASS_USER_AGENT,
    },
    body: `data=${encodeURIComponent(query)}`,
  });

  if (!res.ok) {
    throw new Error(`Overpass request failed: ${res.status} ${res.statusText}`);
  }

  const data = await res.json();
  return data.elements ?? [];
}

// --- fuzzy matching (same approach as bulk-import-overpass.mjs) ---

function normalizeName(name) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function levenshtein(a, b) {
  const m = a.length;
  const n = b.length;
  const dp = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)]);
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] =
        a[i - 1] === b[j - 1]
          ? dp[i - 1][j - 1]
          : 1 + Math.min(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1]);
    }
  }
  return dp[m][n];
}

function nameSimilarity(a, b) {
  const na = normalizeName(a);
  const nb = normalizeName(b);
  if (!na || !nb) return 0;
  if (na === nb) return 1;
  if (na.includes(nb) || nb.includes(na)) return 0.95;
  const distance = levenshtein(na, nb);
  return 1 - distance / Math.max(na.length, nb.length);
}

function haversineMiles(lat1, lng1, lat2, lng2) {
  const R = 3958.8;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(a));
}

// --- Supabase helpers ---

async function loadEntities() {
  // search_entities gives us id/name/lat/lng in one call (same RPC
  // bulk-import-overpass.mjs already uses to load "existing" entities);
  // show_hidden so nothing is silently excluded from matching.
  const { data, error } = await supabase.rpc("search_entities", {
    ref_lat: CENTER.lat,
    ref_lng: CENTER.lng,
    radius_miles: EXISTING_SEARCH_RADIUS_MILES,
    category_path: null,
    show_hidden: true,
  });
  if (error) throw new Error(`Failed to load entities: ${error.message}`);
  return data.map((e) => ({ id: e.id, name: e.name, lat: e.lat, lng: e.lng }));
}

async function loadSourceCodes() {
  // Unfiltered - the table is small (low hundreds of rows) and filtering
  // by a few hundred UUIDs via .in() blows past a usable URL length.
  const { data, error } = await supabase.from("entities").select("id, source_code");
  if (error) throw new Error(`Failed to load source_code: ${error.message}`);
  return new Map(data.map((r) => [r.id, r.source_code]));
}

async function main() {
  console.log(CONFIRM ? "Running with --confirm: entities WILL be updated.\n" : "Dry run (pass --confirm to actually write changes).\n");

  console.log("Loading entities...");
  const entities = await loadEntities();
  const sourceCodeById = await loadSourceCodes();
  console.log(`Loaded ${entities.length} entities.`);

  console.log("Querying Overpass API for Arlington, VA...");
  const elements = await fetchOverpassElements();
  console.log(`Overpass returned ${elements.length} raw elements.\n`);

  // Build every (entity, element) pair within the wider review net.
  const pairs = [];
  let elementsSkippedNoName = 0;
  let elementsSkippedNoCoords = 0;

  for (const el of elements) {
    const tags = el.tags ?? {};
    const name = tags.name;
    if (!name) {
      elementsSkippedNoName++;
      continue;
    }
    const lat = el.lat ?? el.center?.lat;
    const lng = el.lon ?? el.center?.lon;
    if (lat == null || lng == null) {
      elementsSkippedNoCoords++;
      continue;
    }

    for (const entity of entities) {
      const dist = haversineMiles(lat, lng, entity.lat, entity.lng);
      if (dist > REVIEW_DISTANCE_MILES) continue;
      const sim = nameSimilarity(name, entity.name);
      if (sim < REVIEW_NAME_SIMILARITY) continue;
      pairs.push({ el, entity, name, lat, lng, dist, sim });
    }
  }

  // Best match first (highest name similarity, then closest distance),
  // then greedily assign 1:1 - once an entity or an OSM element is
  // claimed, no other pair can claim it too.
  pairs.sort((a, b) => b.sim - a.sim || a.dist - b.dist);

  const matchedEntityIds = new Set();
  const matchedElementKeys = new Set();
  const confirmedMatches = [];

  for (const pair of pairs) {
    const elKey = `${pair.el.type}/${pair.el.id}`;
    if (matchedEntityIds.has(pair.entity.id) || matchedElementKeys.has(elKey)) continue;
    if (pair.dist <= MATCH_DISTANCE_MILES && pair.sim >= MATCH_NAME_SIMILARITY) {
      confirmedMatches.push(pair);
      matchedEntityIds.add(pair.entity.id);
      matchedElementKeys.add(elKey);
    }
  }

  // For entities that didn't get a confident match, surface their best
  // remaining gray-zone candidate (if any) as a manual-review flag.
  const reviewCandidates = [];
  const reviewedEntityIds = new Set();
  for (const pair of pairs) {
    if (matchedEntityIds.has(pair.entity.id)) continue;
    if (reviewedEntityIds.has(pair.entity.id)) continue;
    reviewCandidates.push(pair);
    reviewedEntityIds.add(pair.entity.id);
  }

  const trueUnmatched = entities.filter(
    (e) => !matchedEntityIds.has(e.id) && !reviewedEntityIds.has(e.id)
  );

  // --- Apply (or dry-run report) confirmed matches ---
  let updated = 0;
  let updateFailures = 0;
  let alreadyOsm = 0;
  let upgradedFromManual = 0;

  for (const match of confirmedMatches) {
    const prevSourceCode = sourceCodeById.get(match.entity.id);
    if (prevSourceCode === "osm") alreadyOsm++;
    else upgradedFromManual++;

    if (CONFIRM) {
      const { error } = await supabase
        .from("entities")
        .update({ osm_id: match.el.id, source_code: "osm" })
        .eq("id", match.entity.id);
      if (error) {
        console.error(`Failed to update "${match.entity.name}": ${error.message}`);
        updateFailures++;
        continue;
      }
    }
    updated++;
  }

  // --- Report ---
  console.log("--- Summary ---");
  console.log(`Entities loaded: ${entities.length}`);
  console.log(`Overpass elements: ${elements.length} (skipped ${elementsSkippedNoName} no-name, ${elementsSkippedNoCoords} no-coords)`);
  console.log();
  console.log(`Confidently matched (osm_id${CONFIRM ? "" : " would be"} set, source_code='osm'): ${updated}`);
  console.log(`  - already source_code='osm': ${alreadyOsm}`);
  console.log(`  - upgraded from a non-osm source_code: ${upgradedFromManual}`);
  if (updateFailures > 0) console.log(`  - update failures: ${updateFailures}`);
  console.log();
  console.log(`Flagged for manual review (close but below confident thresholds): ${reviewCandidates.length}`);
  for (const c of reviewCandidates) {
    console.log(
      `  - "${c.entity.name}" (entity ${c.entity.id}) vs OSM "${c.name}" (${c.el.type}/${c.el.id}): ` +
        `${(c.sim * 100).toFixed(0)}% name match, ${(c.dist * 5280).toFixed(0)} ft away`
    );
  }
  // Re-examine trueUnmatched with the two extra nets described above -
  // reclassify anything they catch as a manual-review flag instead of
  // "no plausible candidate at all."
  const coLocatedButNameMismatch = [];
  const highNameSimilarityFarAway = [];
  const genuinelyUnmatched = [];

  for (const e of trueUnmatched) {
    let nearest = null;
    let bestName = null;
    for (const el of elements) {
      const tags = el.tags ?? {};
      const name = tags.name;
      if (!name) continue;
      const lat = el.lat ?? el.center?.lat;
      const lng = el.lon ?? el.center?.lon;
      if (lat == null || lng == null) continue;
      const dist = haversineMiles(lat, lng, e.lat, e.lng);
      const sim = nameSimilarity(name, e.name);
      if (!nearest || dist < nearest.dist) nearest = { name, dist, sim };
      if (!bestName || sim > bestName.sim) bestName = { name, dist, sim };
    }

    if (nearest && nearest.dist <= SAME_ADDRESS_DISTANCE_MILES) {
      coLocatedButNameMismatch.push({ entity: e, match: nearest });
    } else if (bestName && bestName.sim >= HIGH_NAME_SIMILARITY) {
      highNameSimilarityFarAway.push({ entity: e, match: bestName });
    } else {
      genuinelyUnmatched.push({ entity: e, nearest, bestName });
    }
  }

  console.log();
  console.log(
    `Flagged for manual review - same address, name doesn't match (rebrand/closure/wrong coordinates?): ${coLocatedButNameMismatch.length}`
  );
  for (const { entity, match } of coLocatedButNameMismatch) {
    console.log(
      `  - "${entity.name}" (entity ${entity.id}) vs OSM "${match.name}": ${match.dist * 5280 | 0} ft away, only ${(match.sim * 100).toFixed(0)}% name match`
    );
  }

  console.log();
  console.log(
    `Flagged for manual review - near-identical name found far away (stale coordinates, or a second chain location?): ${highNameSimilarityFarAway.length}`
  );
  for (const { entity, match } of highNameSimilarityFarAway) {
    console.log(
      `  - "${entity.name}" (entity ${entity.id}) vs OSM "${match.name}": ${(match.sim * 100).toFixed(0)}% name match but ${(match.dist * 5280).toFixed(0)} ft away`
    );
  }

  console.log();
  console.log(`No plausible OSM candidate found nearby at all: ${genuinelyUnmatched.length}`);
  for (const { entity, nearest, bestName } of genuinelyUnmatched) {
    console.log(`  - "${entity.name}" (entity ${entity.id})`);
    if (nearest) {
      console.log(
        `      nearest OSM element: "${nearest.name}" (${(nearest.dist * 5280).toFixed(0)} ft away, ${(nearest.sim * 100).toFixed(0)}% name match)`
      );
    }
    if (bestName && bestName.name !== nearest?.name) {
      console.log(
        `      best name match overall: "${bestName.name}" (${(bestName.sim * 100).toFixed(0)}% name match, ${(bestName.dist * 5280).toFixed(0)} ft away)`
      );
    }
  }

  if (!CONFIRM) {
    console.log("\nDry run only - re-run with --confirm to actually write these changes.");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
