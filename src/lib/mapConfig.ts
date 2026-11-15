// Isolates the map tile/style source so swapping providers later (e.g. to a
// self-hosted PMTiles source) is a small, contained change - nothing outside
// this file should know the source is MapTiler.

import type { Map as MapLibreMap, StyleSpecification } from "maplibre-gl";

const MAPTILER_API_KEY = process.env.NEXT_PUBLIC_MAPTILER_API_KEY;

// The two looks a browsing map can have (2026-11-15): "map" is MapTiler's Streets style, v4 (green
// parks, blue water, highway shields: color, like the big map apps), and "satellite" is its
// Satellite Hybrid style, v4 (imagery with street names). Before this the map was the plain
// "base-v4-light". Pins are placed by hand on the plain map only: map services' terms forbid
// making data from their imagery.
export type MapKind = "map" | "satellite";
const STYLE_IDS: Record<MapKind, string> = { map: "streets-v4", satellite: "hybrid-v4" };

export function getMapStyleUrl(kind: MapKind = "map"): string {
  if (!MAPTILER_API_KEY) {
    throw new Error("NEXT_PUBLIC_MAPTILER_API_KEY is not set");
  }
  return `https://api.maptiler.com/maps/${STYLE_IDS[kind]}/style.json?key=${MAPTILER_API_KEY}`;
}

// The map's own business icons (restaurants, shops, petrol stations and so on, from
// OpenStreetMap) are left out, so the only places on the map are ours: theirs would show places
// that aren't in our list and compete with our pins. Stations and airports stay, for finding
// your way.
const KEEP_POI = /station|transit|subway|metro|rail|train|tram|bus|ferry|airport|aerodrome/i;

export function isBusinessIconLayer(layer: { id: string; "source-layer"?: string }): boolean {
  const sourceLayer = layer["source-layer"];
  return typeof sourceLayer === "string" && /^poi/i.test(sourceLayer) && !KEEP_POI.test(layer.id);
}

export function withoutBusinessIcons(style: StyleSpecification): StyleSpecification {
  return { ...style, layers: style.layers.filter((layer) => !isBusinessIconLayer(layer as { id: string; "source-layer"?: string })) };
}

// Gives a map its look. Our own pins and bubbles are added again on the map's "style.load".
export function applyMapStyle(map: MapLibreMap, kind: MapKind = "map") {
  map.setStyle(getMapStyleUrl(kind), { diff: false, transformStyle: (_previous, next) => withoutBusinessIcons(next) });
}

// The last look someone picked, in this browser (a convenience: it can come back empty).
const KIND_KEY = "sms-map-kind";
export function loadMapKind(): MapKind {
  try {
    return localStorage.getItem(KIND_KEY) === "satellite" ? "satellite" : "map";
  } catch {
    return "map";
  }
}
export function saveMapKind(kind: MapKind) {
  try {
    localStorage.setItem(KIND_KEY, kind);
  } catch {
    // Storage can be off (private windows, some embeds); the choice just isn't remembered.
  }
}

// Plain places' pins and the bubbles that group them (2026-11-15: salmon, in place of the dark
// pin). It is apart from the colors that already mean something: rose for your favorites, green
// for friends' favorites, blue for Want to try. Deep enough for white numbers on the bubbles.
export const PIN_COLOR = "#de6630";

export const DEFAULT_MAP_CENTER: [number, number] = [-77.1, 38.88]; // [lng, lat]
export const DEFAULT_MAP_ZOOM = 12;

// How far in the browsing maps go (results, lists, a place's page): about street level, where a
// block's storefronts are still easy to tell apart. Closer than this, the few meters by which any
// source's point can be off look like mistakes. Placing a pin by hand may go closer.
export const MAX_BROWSE_ZOOM = 18;
export const MAX_PIN_ZOOM = 20;
