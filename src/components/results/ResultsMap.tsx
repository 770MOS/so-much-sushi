"use client";

import { useEffect, useRef, type ReactNode } from "react";
import maplibregl from "maplibre-gl";
import type { GeoJSONSource, LngLatBoundsLike, MapGeoJSONFeature, MapLayerMouseEvent } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { getMapStyleUrl } from "@/lib/mapConfig";
import {
  addPinImages,
  ICON_OFFSET,
  markFor,
  pinImageId,
  RECOMMENDED_COLOR,
  STARRED_COLOR,
  type MapMarkerEntity,
} from "@/components/EntityMap";
import type { AreaCell } from "@/lib/searchTypes";
import type { Box } from "@/lib/resultsQuery";

// The results page's map (build step 3). The map area is the search area:
//   * it opens on the search's box;
//   * places close together are grouped into a bubble with how many there are, its ring showing
//     the mix of the person's favorites (rose), friends' favorites (green), Want to try (blue)
//     and other places (white). Clicking a bubble zooms in to it;
//   * when a search has more places than the list holds (1,000), the bubbles come from the
//     database's grid counts (cells) instead, so they are true counts; clicking one of those
//     zooms in to it and searches there;
//   * when the person moves the map, onMoved tells the page, which offers "Search this area".
// Overlays (the Search this area button, notes) are passed as children.

type Props = {
  places: MapMarkerEntity[];
  cells: AreaCell[] | null;
  area: Box;
  highlightId?: string | null; // a row the pointer is over
  selectedId?: string | null; // the place whose panel is open
  onSelect?: (id: string) => void; // a pin was clicked: open its place
  // How much of the map the place panel covers (right on a computer, bottom on a phone), so
  // the open place can be moved into the part still showing.
  revealInset?: { right: number; bottom: number };
  onMoved?: (view: Box) => void;
  onSearchBox?: (box: Box) => void;
  className?: string;
  children?: ReactNode;
};

const SOURCE_ID = "sms-area";
const PINS_LAYER = "sms-area-pins";
const BUBBLES_LAYER = "sms-area-bubbles";
const WANT_COLOR = "#3b5bdb"; // --want, the blue flag
const BUBBLE_FILL = "#222222";
// Bubble images are drawn on demand, one per look (count and mix); past this many, the ones not
// on screen are dropped and drawn again if needed.
const MAX_BUBBLE_IMAGES = 300;


function bubbleLabel(n: number): string {
  return n < 10000 ? n.toLocaleString("en-US") : `${Math.round(n / 1000)}k`;
}

// The page's own typeface (DM Sans, loaded by next/font), for the numbers in the bubbles.
function pageFontFamily(): string {
  if (typeof document === "undefined") return "sans-serif";
  return getComputedStyle(document.body).fontFamily || "sans-serif";
}

function drawBubble(n: number, fav: number, friend: number, want: number): ImageData | null {
  const d = n < 10 ? 34 : n < 100 ? 38 : n < 1000 ? 44 : 50; // CSS pixels across
  const margin = 4; // room for the shadow
  const size = d + margin * 2;
  const scale = 2;
  const canvas = document.createElement("canvas");
  canvas.width = size * scale;
  canvas.height = size * scale;
  const ctx = canvas.getContext("2d");
  if (!ctx) return null;
  ctx.scale(scale, scale);
  const c = size / 2;
  const r = d / 2;

  // White disc with a soft shadow; the ring is drawn on it.
  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,0.28)";
  ctx.shadowBlur = 5;
  ctx.shadowOffsetY = 1;
  ctx.beginPath();
  ctx.arc(c, c, r, 0, Math.PI * 2);
  ctx.fillStyle = "#ffffff";
  ctx.fill();
  ctx.restore();

  const marked = fav + friend + want > 0;
  const ring = marked ? 4 : 2.5;
  if (marked) {
    // Each mark's share of the ring, but never less than a small arc, so one favorite among
    // 200 places still shows; the shares are scaled back if that overfills the ring.
    const MIN_SWEEP = 0.4;
    const parts = ([
      [fav, STARRED_COLOR],
      [friend, RECOMMENDED_COLOR],
      [want, WANT_COLOR],
    ] as const)
      .filter(([count]) => count > 0)
      .map(([count, color]) => ({ color, sweep: Math.max((Math.min(count, n) / n) * Math.PI * 2, MIN_SWEEP) }));
    const total = parts.reduce((sum, p) => sum + p.sweep, 0);
    const fit = total > Math.PI * 2 ? (Math.PI * 2) / total : 1;
    let start = -Math.PI / 2;
    ctx.lineWidth = ring;
    for (const part of parts) {
      const sweep = part.sweep * fit;
      ctx.beginPath();
      ctx.arc(c, c, r - ring / 2, start, start + sweep);
      ctx.strokeStyle = part.color;
      ctx.stroke();
      start += sweep;
    }
  }

  ctx.beginPath();
  ctx.arc(c, c, r - ring, 0, Math.PI * 2);
  ctx.fillStyle = BUBBLE_FILL;
  ctx.fill();

  const label = bubbleLabel(n);
  const fontSize = label.length <= 2 ? 14 : label.length === 3 ? 13 : 12;
  ctx.font = `500 ${fontSize}px ${pageFontFamily()}`;
  ctx.fillStyle = "#ffffff";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(label, c, c + 0.5);
  return ctx.getImageData(0, 0, canvas.width, canvas.height);
}

type FeatureProps = Record<string, string | number | number[]>;

function toFeatures(places: MapMarkerEntity[], cells: AreaCell[] | null): GeoJSON.FeatureCollection<GeoJSON.Point, FeatureProps> {
  if (cells) {
    return {
      type: "FeatureCollection",
      features: cells.map((cell) => ({
        type: "Feature",
        geometry: { type: "Point", coordinates: [cell.lng, cell.lat] },
        properties: {
          n: cell.n,
          fav: cell.fav,
          friend: cell.friend,
          want: cell.want,
          cw: cell.cell_west,
          cs: cell.cell_south,
          ce: cell.cell_east,
          cn: cell.cell_north,
        },
      })),
    };
  }
  return {
    type: "FeatureCollection",
    features: places.map((place) => {
      const mark = markFor(place);
      const statusOpacity = place.status && place.status !== "active" ? 0.55 : 1;
      return {
        type: "Feature",
        geometry: { type: "Point", coordinates: [place.lng, place.lat] },
        properties: {
          id: place.id,
          n: 1,
          fav: mark === "fav" ? 1 : 0,
          friend: mark === "friend" ? 1 : 0,
          want: mark === "want" ? 1 : 0,
          icon: mark ? `sms-mark-${mark}` : pinImageId(place.entityType, false, false),
          anchor: mark ? "center" : "bottom",
          offset: mark ? [0, 0] : ICON_OFFSET,
          opacity: (place.matchesFilter ? 1 : 0.25) * statusOpacity,
          sortKey: mark === "fav" ? 3 : mark === "friend" ? 2 : mark === "want" ? 1 : 0,
        },
      };
    }),
  };
}

// Pins grow for the row the pointer is over, and more for the place whose panel is open.
function pinSize(hoverId: string | null, selectedId: string | null): maplibregl.ExpressionSpecification {
  return ["case", ["==", ["get", "id"], selectedId ?? ""], 1.45, ["==", ["get", "id"], hoverId ?? ""], 1.3, 1];
}

function boundsBox(map: maplibregl.Map): Box {
  const b = map.getBounds();
  return { west: b.getWest(), south: b.getSouth(), east: b.getEast(), north: b.getNorth() };
}

// The map already shows about this box (each edge within 3% of the box's size): no need to move.
function showsAbout(view: Box, area: Box): boolean {
  const w = area.east - area.west;
  const h = area.north - area.south;
  return (
    Math.abs(view.west - area.west) <= 0.03 * w &&
    Math.abs(view.east - area.east) <= 0.03 * w &&
    Math.abs(view.south - area.south) <= 0.03 * h &&
    Math.abs(view.north - area.north) <= 0.03 * h
  );
}

function areaBounds(area: Box): LngLatBoundsLike {
  return [
    [area.west, area.south],
    [area.east, area.north],
  ];
}

export default function ResultsMap({ places, cells, area, highlightId, selectedId, onSelect, revealInset, onMoved, onSearchBox, className, children }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const readyRef = useRef(false);
  const dataRef = useRef(toFeatures(places, cells));
  // True while the bubbles come from the database's counted squares.
  const cellsRef = useRef(cells !== null);
  const placeByIdRef = useRef<Map<string, MapMarkerEntity>>(new Map());
  const labelRef = useRef<maplibregl.Marker | null>(null);
  const areaRef = useRef(area);
  const highlightRef = useRef<string | null>(highlightId ?? null);
  const selectedRef = useRef<string | null>(selectedId ?? null);
  const onSelectRef = useRef(onSelect);
  const onMovedRef = useRef(onMoved);
  const onSearchBoxRef = useRef(onSearchBox);

  useEffect(() => {
    onSelectRef.current = onSelect;
    onMovedRef.current = onMoved;
    onSearchBoxRef.current = onSearchBox;
  }, [onSelect, onMoved, onSearchBox]);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    let cancelled = false;
    readyRef.current = false;
    const bubbleImages = new Set<string>();
    // Set when the person starts moving the map (drag, wheel, buttons) or clicks a bubble; the
    // move's end then tells the page.
    let movedByPerson = false;
    // Set when a counted square was clicked: once the map has zoomed to it, search there.
    let searchWhenStill = false;

    const map = new maplibregl.Map({
      container: containerRef.current,
      style: getMapStyleUrl(),
      bounds: areaBounds(areaRef.current),
      fitBoundsOptions: { padding: 8 },
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");

    map.on("styleimagemissing", (e) => {
      const m = /^sms-b-(\d+)-(\d+)-(\d+)-(\d+)$/.exec(e.id);
      if (!m || map.hasImage(e.id)) return;
      const [n, fav, friend, want] = m.slice(1).map(Number);
      const image = drawBubble(Math.max(n, 1), fav, friend, want);
      if (!image) return;
      map.addImage(e.id, image, { pixelRatio: 2 });
      bubbleImages.add(e.id);
    });

    // Drop bubble images no longer on screen once there are many (each look is its own image).
    map.on("idle", () => {
      if (bubbleImages.size <= MAX_BUBBLE_IMAGES || !readyRef.current) return;
      const inUse = new Set(
        map.queryRenderedFeatures({ layers: [BUBBLES_LAYER] }).map((f) => {
          const p = f.properties ?? {};
          return `sms-b-${p.n}-${p.fav}-${p.friend}-${p.want}`;
        })
      );
      for (const id of bubbleImages) {
        if (!inUse.has(id)) {
          map.removeImage(id);
          bubbleImages.delete(id);
        }
      }
    });

    map.on("movestart", (e) => {
      if ((e as { originalEvent?: Event }).originalEvent) movedByPerson = true;
    });
    map.on("moveend", () => {
      if (searchWhenStill) {
        searchWhenStill = false;
        movedByPerson = false;
        onSearchBoxRef.current?.(boundsBox(map));
        return;
      }
      if (movedByPerson) {
        movedByPerson = false;
        onMovedRef.current?.(boundsBox(map));
      }
    });

    map.on("load", async () => {
      // The bubbles' numbers are drawn in the page's typeface, so wait for it.
      await Promise.all([addPinImages(map, () => cancelled), document.fonts?.ready]);
      if (cancelled) return;
      map.addSource(SOURCE_ID, {
        type: "geojson",
        data: dataRef.current,
        cluster: true,
        clusterRadius: 60,
        clusterMaxZoom: 14,
        clusterProperties: {
          n: ["+", ["get", "n"]],
          fav: ["+", ["get", "fav"]],
          friend: ["+", ["get", "friend"]],
          want: ["+", ["get", "want"]],
        },
      });
      map.addLayer({
        id: PINS_LAYER,
        type: "symbol",
        source: SOURCE_ID,
        filter: ["all", ["!", ["has", "point_count"]], ["has", "id"]],
        layout: {
          "icon-image": ["get", "icon"],
          "icon-anchor": ["get", "anchor"],
          "icon-offset": ["get", "offset"],
          "icon-size": pinSize(highlightRef.current, selectedRef.current),
          "icon-allow-overlap": true,
          "icon-ignore-placement": true,
          "symbol-sort-key": ["get", "sortKey"],
        },
        paint: { "icon-opacity": ["get", "opacity"] },
      });
      map.addLayer({
        id: BUBBLES_LAYER,
        type: "symbol",
        source: SOURCE_ID,
        // Groups of places, and the database's counted squares (which have no id).
        filter: ["any", ["has", "point_count"], ["!", ["has", "id"]]],
        layout: {
          // One image per look: "sms-b-{n}-{fav}-{friend}-{want}", drawn when first needed.
          "icon-image": [
            "concat",
            "sms-b-",
            ["to-string", ["get", "n"]],
            "-",
            ["to-string", ["get", "fav"]],
            "-",
            ["to-string", ["get", "friend"]],
            "-",
            ["to-string", ["get", "want"]],
          ],
          "icon-allow-overlap": true,
          "icon-ignore-placement": true,
          "symbol-sort-key": ["get", "n"],
        },
      });
      readyRef.current = true;
    });

    map.on("click", PINS_LAYER, (event: MapLayerMouseEvent) => {
      const id = event.features?.[0]?.properties?.id as string | undefined;
      if (id) onSelectRef.current?.(id);
    });

    map.on("click", BUBBLES_LAYER, async (event: MapLayerMouseEvent) => {
      const feature = event.features?.[0] as MapGeoJSONFeature | undefined;
      if (!feature || feature.geometry.type !== "Point") return;
      const p = feature.properties ?? {};
      const center = feature.geometry.coordinates as [number, number];
      if (p.cluster_id !== undefined) {
        const source = map.getSource(SOURCE_ID) as GeoJSONSource | undefined;
        if (!source) return;
        const zoom = await source.getClusterExpansionZoom(Number(p.cluster_id));
        // Counted squares (more than 1,000 places): the list holds only the nearest 1,000, so
        // zooming in alone wouldn't show this bubble's places; search where it zooms to.
        if (cellsRef.current) searchWhenStill = true;
        else movedByPerson = true;
        map.easeTo({ center, zoom: Math.min(zoom, 18) });
        return;
      }
      // A counted square: zoom to its places, then search there.
      searchWhenStill = true;
      map.fitBounds(
        [
          [Number(p.cw), Number(p.cs)],
          [Number(p.ce), Number(p.cn)],
        ],
        { padding: 60, maxZoom: 16 }
      );
    });

    for (const layer of [PINS_LAYER, BUBBLES_LAYER]) {
      map.on("mouseenter", layer, () => {
        map.getCanvas().style.cursor = "pointer";
      });
      map.on("mouseleave", layer, () => {
        map.getCanvas().style.cursor = "";
      });
    }

    mapRef.current = map;
    const resizeObserver = new ResizeObserver(() => map.resize());
    resizeObserver.observe(containerRef.current);

    return () => {
      cancelled = true;
      resizeObserver.disconnect();
      readyRef.current = false;
      labelRef.current?.remove();
      labelRef.current = null;
      map.remove();
      mapRef.current = null;
    };
  }, []);

  // New places or counts: redraw them.
  useEffect(() => {
    dataRef.current = toFeatures(places, cells);
    cellsRef.current = cells !== null;
    placeByIdRef.current = new Map(places.map((p) => [p.id, p]));
    const map = mapRef.current;
    if (map && readyRef.current) (map.getSource(SOURCE_ID) as GeoJSONSource | undefined)?.setData(dataRef.current);
  }, [places, cells]);

  // A new search area: show it, unless the map already does (e.g. it came from this map).
  useEffect(() => {
    areaRef.current = area;
    const map = mapRef.current;
    if (!map) return;
    if (showsAbout(boundsBox(map), area)) return;
    const camera = map.cameraForBounds(areaBounds(area), { padding: 8 });
    if (camera) map.jumpTo({ center: camera.center, zoom: camera.zoom });
  }, [area]);

  useEffect(() => {
    highlightRef.current = highlightId ?? null;
    selectedRef.current = selectedId ?? null;
    const map = mapRef.current;
    if (!map || !readyRef.current) return;
    map.setLayoutProperty(PINS_LAYER, "icon-size", pinSize(highlightId ?? null, selectedId ?? null));
  }, [highlightId, selectedId]);

  // The open place: its name over its marker, and moved out from under the panel if hidden.
  useEffect(() => {
    const map = mapRef.current;
    labelRef.current?.remove();
    labelRef.current = null;
    const place = selectedId ? placeByIdRef.current.get(selectedId) : undefined;
    if (!map || !place) return;
    const label = document.createElement("div");
    label.className = "pointer-events-none whitespace-nowrap rounded-lg bg-[#141414] px-2.5 py-1 text-[13px] font-medium text-white shadow-[0_2px_6px_rgba(0,0,0,0.25)]";
    label.textContent = place.name;
    labelRef.current = new maplibregl.Marker({ element: label, anchor: "bottom", offset: [0, markFor(place) ? -24 : -48] })
      .setLngLat([place.lng, place.lat])
      .addTo(map);

    const inset = revealInset ?? { right: 0, bottom: 0 };
    const canvas = map.getCanvas();
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    const at = map.project([place.lng, place.lat]);
    const margin = 48;
    const hidden = at.x < margin || at.y < margin || at.x > width - inset.right - margin || at.y > height - inset.bottom - margin;
    if (hidden) {
      // Centre it in the part of the map the panel leaves showing. Not a move by the person,
      // so no "Search this area".
      map.easeTo({ center: [place.lng, place.lat], offset: [-inset.right / 2, -inset.bottom / 2], duration: 400 });
    }
    // Only when the open place changes, not on every new inset or list.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedId, places]);

  return (
    <div className={`relative ${className ?? ""}`}>
      {/* Sized by its box, not positioned: MapLibre's own style makes the map element relative. */}
      <div ref={containerRef} className="h-full w-full" />
      {children}
    </div>
  );
}
