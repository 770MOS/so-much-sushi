import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const OVERPASS_URL = "https://overpass-api.de/api/interpreter";
const OVERPASS_USER_AGENT =
  "so-much-sushi-bulk-import/1.0 (https://github.com/770MOS/so-much-sushi)";

// Arlington County, VA (confirmed via Nominatim: relation 962190).
// Overpass area ids offset relation ids by 3600000000.
const ARLINGTON_AREA_ID = 3600962190;
const CENTER = { lat: 38.8769326, lng: -77.0893094 };
const EXISTING_SEARCH_RADIUS_MILES = 15; // comfortably covers the whole ~26 sq mi county

const DUPLICATE_DISTANCE_MILES = 0.1; // ~160m - same building/plaza tolerance
const DUPLICATE_NAME_SIMILARITY = 0.82; // 0-1, see nameSimilarity()

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !serviceRoleKey) {
  console.error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env.local");
  process.exit(1);
}

const supabase = createClient(supabaseUrl, serviceRoleKey);

// --- Overpass fetch ---

async function fetchOverpassElements() {
  // Queries by Arlington's actual polygon boundary (not a bounding-box
  // rectangle, which was found during testing to also sweep in ~900
  // establishments from neighboring DC/Falls Church/McLean near the edges).
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

// --- category mapping ---

function mapToCategorySlug(tags) {
  const cuisine = (tags.cuisine ?? "")
    .split(/[;,]/)[0]
    .trim()
    .toLowerCase();

  if (cuisine === "italian") return { slug: "italian", confident: true };
  if (cuisine === "pizza") return { slug: "pizza", confident: true };
  if (cuisine === "mexican") return { slug: "mexican", confident: true };
  if (cuisine === "sushi") return { slug: "sushi", confident: true };
  if (cuisine === "thai") return { slug: "thai", confident: true };
  if (tags.microbrewery === "yes") return { slug: "brewery", confident: true };
  if (tags.amenity === "cafe") return { slug: "coffee", confident: true };
  if (tags.amenity === "bar" || tags.amenity === "pub") return { slug: "bar", confident: true };

  return { slug: "restaurants", confident: false };
}

function buildAddress(tags) {
  const parts = [];
  if (tags["addr:housenumber"] && tags["addr:street"]) {
    parts.push(`${tags["addr:housenumber"]} ${tags["addr:street"]}`);
  } else if (tags["addr:street"]) {
    parts.push(tags["addr:street"]);
  }
  const cityStateZip = [tags["addr:city"], tags["addr:state"]].filter(Boolean).join(", ");
  const cityStateZipWithPostcode = [cityStateZip, tags["addr:postcode"]].filter(Boolean).join(" ");
  if (cityStateZipWithPostcode) parts.push(cityStateZipWithPostcode);

  return parts.length > 0 ? parts.join(", ") : null;
}

// --- fuzzy duplicate detection ---

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

function findDuplicate(candidate, existingList) {
  return existingList.find(
    (e) =>
      haversineMiles(candidate.lat, candidate.lng, e.lat, e.lng) <= DUPLICATE_DISTANCE_MILES &&
      nameSimilarity(candidate.name, e.name) >= DUPLICATE_NAME_SIMILARITY
  );
}

// --- Supabase helpers ---

async function loadCategoryIdsBySlug() {
  const { data, error } = await supabase.from("categories").select("id, slug");
  if (error) throw new Error(`Failed to load categories: ${error.message}`);
  return new Map(data.map((c) => [c.slug, c.id]));
}

async function loadExistingEntities() {
  const { data, error } = await supabase.rpc("search_entities", {
    ref_lat: CENTER.lat,
    ref_lng: CENTER.lng,
    radius_miles: EXISTING_SEARCH_RADIUS_MILES,
    category_path: null,
    show_hidden: true,
  });
  if (error) throw new Error(`Failed to load existing entities: ${error.message}`);
  return data.map((e) => ({ name: e.name, lat: e.lat, lng: e.lng }));
}

async function main() {
  console.log("Loading categories and existing entities...");
  const categoryIdBySlug = await loadCategoryIdsBySlug();
  const existing = await loadExistingEntities();
  console.log(`Found ${existing.length} existing entities to check against.`);

  console.log("Querying Overpass API for Arlington, VA...");
  const elements = await fetchOverpassElements();
  console.log(`Overpass returned ${elements.length} raw elements.`);

  let inserted = 0;
  let skippedDuplicates = 0;
  let flaggedNeedsReview = 0;
  let skippedNoName = 0;
  let skippedNoCoords = 0;
  let insertFailures = 0;

  const seenInThisRun = [];

  for (const el of elements) {
    const tags = el.tags ?? {};
    const name = tags.name;
    if (!name) {
      skippedNoName++;
      continue;
    }

    const lat = el.lat ?? el.center?.lat;
    const lng = el.lon ?? el.center?.lon;
    if (lat == null || lng == null) {
      skippedNoCoords++;
      continue;
    }

    const candidate = { name, lat, lng };
    if (findDuplicate(candidate, existing) || findDuplicate(candidate, seenInThisRun)) {
      skippedDuplicates++;
      continue;
    }

    const { slug, confident } = mapToCategorySlug(tags);
    const categoryId = categoryIdBySlug.get(slug);
    if (!categoryId) {
      console.warn(`Unknown category slug "${slug}" for "${name}" - skipping`);
      continue;
    }

    const entityPayload = {
      name,
      address: buildAddress(tags),
      phone: tags.phone ?? tags["contact:phone"] ?? null,
      website: tags.website ?? tags["contact:website"] ?? null,
      city: tags["addr:city"] ?? "Arlington",
      state: tags["addr:state"] ?? "VA",
      location: `SRID=4326;POINT(${lng} ${lat})`,
      source: "OpenStreetMap Overpass API",
      last_verified: null,
      needs_review: !confident,
    };

    const { data: entity, error: entityError } = await supabase
      .from("entities")
      .insert(entityPayload)
      .select("id")
      .single();

    if (entityError) {
      console.error(`Failed to insert "${name}": ${entityError.message}`);
      insertFailures++;
      continue;
    }

    const { error: categoryError } = await supabase
      .from("entity_categories")
      .insert({ entity_id: entity.id, category_id: categoryId });
    if (categoryError) {
      console.error(`Failed to tag category for "${name}": ${categoryError.message}`);
    }

    inserted++;
    if (!confident) flaggedNeedsReview++;
    seenInThisRun.push(candidate);
  }

  console.log("\n--- Summary ---");
  console.log(`Overpass elements returned: ${elements.length}`);
  console.log(`Skipped (no name tag): ${skippedNoName}`);
  console.log(`Skipped (no coordinates): ${skippedNoCoords}`);
  console.log(`Skipped as likely duplicates: ${skippedDuplicates}`);
  console.log(`Inserted: ${inserted}`);
  console.log(`  of which flagged needs_review: ${flaggedNeedsReview}`);
  console.log(`Insert failures: ${insertFailures}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
