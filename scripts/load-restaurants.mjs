import fs from "node:fs";
import path from "node:path";
import dotenv from "dotenv";
import { parse } from "csv-parse/sync";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const CSV_PATH =
  process.argv[2] ?? path.join(process.cwd(), "data/arlington_restaurants_intake.csv");
const NOMINATIM_USER_AGENT =
  "so-much-sushi-data-loader/1.0 (https://github.com/770MOS/so-much-sushi)";
const GEOCODE_DELAY_MS = 1000;

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !serviceRoleKey) {
  console.error(
    "Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env.local"
  );
  process.exit(1);
}

if (!fs.existsSync(CSV_PATH)) {
  console.error(`CSV file not found at ${CSV_PATH}`);
  process.exit(1);
}

const supabase = createClient(supabaseUrl, serviceRoleKey);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function geocodeAddress(address) {
  const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${encodeURIComponent(address)}`;
  const res = await fetch(url, {
    headers: { "User-Agent": NOMINATIM_USER_AGENT },
  });
  if (!res.ok) {
    throw new Error(`Nominatim request failed: ${res.status} ${res.statusText}`);
  }
  const results = await res.json();
  if (!results.length) return null;
  return { lat: parseFloat(results[0].lat), lon: parseFloat(results[0].lon) };
}

async function loadCategoryIdsBySlug() {
  const { data, error } = await supabase.from("categories").select("id, slug");
  if (error) {
    throw new Error(`Failed to load categories: ${error.message}`);
  }
  return new Map(data.map((c) => [c.slug, c.id]));
}

async function main() {
  const csvContent = fs.readFileSync(CSV_PATH, "utf-8");
  const rows = parse(csvContent, { columns: true, skip_empty_lines: true, trim: true });

  const categoryIdBySlug = await loadCategoryIdsBySlug();

  const geocodeFailures = [];
  const insertFailures = [];
  let inserted = 0;

  for (const row of rows) {
    let coords = null;
    try {
      coords = await geocodeAddress(row.address);
    } catch (err) {
      console.error(`Geocode error for "${row.address}": ${err.message}`);
    }
    await sleep(GEOCODE_DELAY_MS);

    if (!coords) {
      console.warn(`No geocode result for "${row.name}" (${row.address})`);
      geocodeFailures.push({ name: row.name, address: row.address });
    }

    const entityPayload = {
      name: row.name,
      address: row.address,
      phone: row.phone?.trim() || null,
      website: row.website?.trim() || null,
      source: row.source,
      last_verified: row.last_verified?.trim() || null,
    };
    if (coords) {
      entityPayload.location = `SRID=4326;POINT(${coords.lon} ${coords.lat})`;
    }

    const { data: entity, error: entityError } = await supabase
      .from("entities")
      .insert(entityPayload)
      .select("id")
      .single();

    if (entityError) {
      console.error(`Failed to insert entity "${row.name}": ${entityError.message}`);
      insertFailures.push({ name: row.name, error: entityError.message });
      continue;
    }

    inserted += 1;

    const slugs = (row.category_slugs ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);

    const categoryRows = [];
    for (const slug of slugs) {
      const categoryId = categoryIdBySlug.get(slug);
      if (!categoryId) {
        console.warn(`Unknown category slug "${slug}" for entity "${row.name}"`);
        continue;
      }
      categoryRows.push({ entity_id: entity.id, category_id: categoryId });
    }

    if (categoryRows.length) {
      const { error: categoryError } = await supabase
        .from("entity_categories")
        .insert(categoryRows);
      if (categoryError) {
        console.error(
          `Failed to insert categories for "${row.name}": ${categoryError.message}`
        );
      }
    }
  }

  console.log("\n--- Summary ---");
  console.log(`Rows processed: ${rows.length}`);
  console.log(`Entities inserted: ${inserted}`);
  console.log(`Geocode failures: ${geocodeFailures.length}`);
  if (geocodeFailures.length) {
    console.log(geocodeFailures.map((f) => `  - ${f.name}: ${f.address}`).join("\n"));
  }
  console.log(`Insert failures: ${insertFailures.length}`);
  if (insertFailures.length) {
    console.log(insertFailures.map((f) => `  - ${f.name}: ${f.error}`).join("\n"));
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
