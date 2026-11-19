"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import maplibregl from "maplibre-gl";
import type { GeoJSONSource, LngLatBoundsLike, MapGeoJSONFeature, MapLayerMouseEvent, MapMouseEvent, MapTouchEvent, PaddingOptions } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { applyMapStyle, loadMapKind, MAX_BROWSE_ZOOM, PIN_COLOR, saveMapKind, type MapKind } from "@/lib/mapConfig";
import {
  addPinImages,
  ICON_OFFSET,
  markFor,
  pinImageId,
  pinOffset,
  spreadOffsets,
  RECOMMENDED_COLOR,
  STARRED_COLOR,
  type MapMarkerEntity,
} from "@/components/EntityMap";
import type { AreaCell } from "@/lib/searchTypes";
import { MAX_SHAPE_POINTS, type Box, type LngLat } from "@/lib/resultsQuery";

// The results page's map (build step 3). The map area is the search area:
//   * it opens on the search's box;
//   * places close together are grouped into a bubble with how many there are, its ring showing
//     the mix of the person's favorites (rose), friends' favorites (green), Want to try (blue)
//     and other places (white). Clicking a bubble zooms in to it;
//   * when a search has more places than the list holds (1,000), the bubbles come from the
//     database's grid counts (cells) instead, so they are true counts; clicking one of those
//     zooms in to it and searches there;
//   * when the person moves the map, onMoved tells the page, which offers "Search this area";
//   * a drawn area (advanced search, 2026-11-19) is outlined; while drawing (draw), clicks drop
//     points (click the first point, or double-click, to close the shape; then drag points), and
//     on a touch screen one finger stroke draws the whole shape, closed when the finger lifts.
//     onDraw reports every change; the page holds the shape and the Done / Cancel bar.
// Overlays (the Search this area button, notes, the drawing bar) are passed as children.

// stroke: drawn with a finger, whose many points have no handles to drag.
export type DrawState = { points: LngLat[]; closed: boolean; stroke?: boolean };

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
  // The drawn area searched (outlined), and the shape being drawn (null: not drawing).
  shape?: LngLat[] | null;
  draw?: DrawState | null;
  onDraw?: (state: DrawState) => void;
  className?: string;
  children?: ReactNode;
};

const SOURCE_ID = "sms-area";
const DRAW_SOURCE = "sms-draw";
const DRAW_FILL = "sms-draw-fill";
const DRAW_LINE = "sms-draw-line";
const DRAW_POINTS = "sms-draw-points";
const DRAW_COLOR = "#1f4fbf"; // --link
// A finger stroke keeps a point every few pixels, then is simplified to at most this many.
const STROKE_POINTS = 60;
const PINS_LAYER = "sms-area-pins";
const BUBBLES_LAYER = "sms-area-bubbles";
const WANT_COLOR = "#3b5bdb"; // --want, the blue flag
const BUBBLE_FILL = PIN_COLOR;
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
  const spread = spreadOffsets(places);
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
          offset: pinOffset(mark ? [0, 0] : ICON_OFFSET, spread.get(place.id)),
          opacity: (place.matchesFilter ? 1 : 0.25) * statusOpacity,
          sortKey: mark === "fav" ? 3 : mark === "friend" ? 2 : mark === "want" ? 1 : 0,
        },
      };
    }),
  };
}


// The shape for the map: while drawing, its line so far, its points (the first marked, to close
// on) and, once closed, its fill; otherwise the drawn area searched, filled and outlined.
function drawFeatures(draw: DrawState | null, shape: LngLat[] | null): GeoJSON.FeatureCollection {
  const features: GeoJSON.Feature[] = [];
  const pts = draw ? draw.points : shape ?? [];
  const closed = draw ? draw.closed : pts.length >= 3;
  if (closed && pts.length >= 3) {
    features.push({ type: "Feature", properties: { kind: "fill" }, geometry: { type: "Polygon", coordinates: [[...pts, pts[0]]] } });
  }
  if (pts.length >= 2) {
    features.push({
      type: "Feature",
      properties: { kind: "line", open: closed ? 0 : 1 },
      geometry: { type: "LineString", coordinates: closed ? [...pts, pts[0]] : pts },
    });
  }
  if (draw && !draw.stroke) {
    pts.forEach((p, i) =>
      features.push({ type: "Feature", properties: { kind: "point", i, first: i === 0 && !closed && pts.length >= 3 ? 1 : 0 }, geometry: { type: "Point", coordinates: p } })
    );
  }
  return { type: "FeatureCollection", features };
}

// Fewer points along a finger's stroke, keeping its shape (Ramer-Douglas-Peucker on screen
// pixels), with the tolerance raised until it fits in max points.
function simplifyStroke(px: { x: number; y: number }[], max: number): number[] {
  function keep(tol: number): number[] {
    const kept = new Set<number>([0, px.length - 1]);
    const stack: [number, number][] = [[0, px.length - 1]];
    while (stack.length) {
      const [a, b] = stack.pop()!;
      let far = -1;
      let farDist = tol;
      const dx = px[b].x - px[a].x;
      const dy = px[b].y - px[a].y;
      const len = Math.hypot(dx, dy) || 1;
      for (let i = a + 1; i < b; i++) {
        const d = Math.abs(dy * px[i].x - dx * px[i].y + px[b].x * px[a].y - px[b].y * px[a].x) / len;
        if (d > farDist) {
          far = i;
          farDist = d;
        }
      }
      if (far >= 0) {
        kept.add(far);
        stack.push([a, far], [far, b]);
      }
    }
    return [...kept].sort((x, y) => x - y);
  }
  let tol = 2;
  let out = keep(tol);
  while (out.length > max && tol < 400) {
    tol *= 1.5;
    out = keep(tol);
  }
  return out;
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

// Room around an area shown on the map. In Split view the map is as tall as the window but
// starts below the filter bar, so until the page scrolls its bottom is off the screen: leave
// that part out, so the whole area shows.
function areaPadding(el: HTMLElement): PaddingOptions {
  const box = el.getBoundingClientRect();
  const hidden = Math.max(0, Math.min(box.height / 2, box.bottom - window.innerHeight));
  return { top: 8, right: 8, bottom: 8 + hidden, left: 8 };
}

function areaBounds(area: Box): LngLatBoundsLike {
  return [
    [area.west, area.south],
    [area.east, area.north],
  ];
}

export default function ResultsMap({
  places,
  cells,
  area,
  highlightId,
  selectedId,
  onSelect,
  revealInset,
  onMoved,
  onSearchBox,
  shape,
  draw,
  onDraw,
  className,
  children,
}: Props) {
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
  const drawRef = useRef<DrawState | null>(draw ?? null);
  const shapeRef = useRef<LngLat[] | null>(shape ?? null);
  const onDrawRef = useRef(onDraw);

  useEffect(() => {
    onSelectRef.current = onSelect;
    onMovedRef.current = onMoved;
    onSearchBoxRef.current = onSearchBox;
    onDrawRef.current = onDraw;
  }, [onSelect, onMoved, onSearchBox, onDraw]);

  // Map or Satellite: the last one picked in this browser.
  const [kind, setKind] = useState<MapKind>(loadMapKind);
  const kindRef = useRef(kind);
  const appliedKindRef = useRef<MapKind | null>(null);
  useEffect(() => {
    kindRef.current = kind;
    saveMapKind(kind);
    const map = mapRef.current;
    if (!map || appliedKindRef.current === kind) return;
    appliedKindRef.current = kind;
    readyRef.current = false;
    applyMapStyle(map, kind);
  }, [kind]);

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
      bounds: areaBounds(areaRef.current),
      fitBoundsOptions: { padding: areaPadding(containerRef.current) },
      maxZoom: MAX_BROWSE_ZOOM,
    });
    applyMapStyle(map, kindRef.current);
    appliedKindRef.current = kindRef.current;
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
        if (!drawRef.current) onMovedRef.current?.(boundsBox(map));
      }
    });

    // Our pins and bubbles go on top of the map's look, again each time the look changes (Map or
    // Satellite), since a new look starts empty.
    let look = 0;
    async function install() {
      const mine = ++look;
      // The bubbles' numbers are drawn in the page's typeface, so wait for it.
      await Promise.all([addPinImages(map, () => cancelled), document.fonts?.ready]);
      // A newer look arrived meanwhile: its own install adds them.
      if (cancelled || mine !== look || map.getSource(SOURCE_ID)) return;
      // The drawn area under the pins; the points to drag over them (added below).
      map.addSource(DRAW_SOURCE, { type: "geojson", data: drawFeatures(drawRef.current, shapeRef.current) });
      map.addLayer({
        id: DRAW_FILL,
        type: "fill",
        source: DRAW_SOURCE,
        filter: ["==", ["get", "kind"], "fill"],
        paint: { "fill-color": DRAW_COLOR, "fill-opacity": 0.1 },
      });
      map.addLayer({
        id: DRAW_LINE,
        type: "line",
        source: DRAW_SOURCE,
        filter: ["==", ["get", "kind"], "line"],
        layout: { "line-join": "round", "line-cap": "round" },
        paint: { "line-color": DRAW_COLOR, "line-width": 2.5 },
      });
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
      map.addLayer({
        id: DRAW_POINTS,
        type: "circle",
        source: DRAW_SOURCE,
        filter: ["==", ["get", "kind"], "point"],
        paint: {
          "circle-radius": ["case", ["==", ["get", "first"], 1], 9, 6],
          "circle-color": "#ffffff",
          "circle-stroke-color": DRAW_COLOR,
          "circle-stroke-width": 3,
        },
      });
      readyRef.current = true;
    }
    map.on("style.load", () => {
      readyRef.current = false;
      bubbleImages.clear();
      void install();
    });

    map.on("click", PINS_LAYER, (event: MapLayerMouseEvent) => {
      if (drawRef.current) return;
      const id = event.features?.[0]?.properties?.id as string | undefined;
      if (id) onSelectRef.current?.(id);
    });

    map.on("click", BUBBLES_LAYER, async (event: MapLayerMouseEvent) => {
      if (drawRef.current) return;
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
        if (!drawRef.current) map.getCanvas().style.cursor = "pointer";
      });
      map.on("mouseleave", layer, () => {
        if (!drawRef.current) map.getCanvas().style.cursor = "";
      });
    }

    // ------------------------------------------------------------ drawing
    // A click drops a point; on the first point (with 3 or more), or a double-click, it closes.
    let lastTouchAt = 0;
    const report = (state: DrawState) => onDrawRef.current?.(state);
    map.on("click", (e: MapMouseEvent) => {
      const d = drawRef.current;
      if (!d || d.closed || Date.now() - lastTouchAt < 700) return;
      if (d.points.length >= 3) {
        const first = map.project(d.points[0]);
        if (Math.hypot(first.x - e.point.x, first.y - e.point.y) < 14) {
          report({ points: d.points, closed: true });
          return;
        }
      }
      if (d.points.length >= MAX_SHAPE_POINTS) return;
      const last = d.points[d.points.length - 1];
      if (last) {
        const at = map.project(last);
        if (Math.hypot(at.x - e.point.x, at.y - e.point.y) < 4) return;
      }
      report({ points: [...d.points, [e.lngLat.lng, e.lngLat.lat]], closed: false });
    });
    map.on("dblclick", (e: MapMouseEvent) => {
      const d = drawRef.current;
      if (!d) return;
      e.preventDefault();
      if (!d.closed && d.points.length >= 3) report({ points: d.points, closed: true });
    });
    // Once closed, a point can be dragged.
    let dragging: number | null = null;
    map.on("mousedown", DRAW_POINTS, (e: MapLayerMouseEvent) => {
      const d = drawRef.current;
      const i = e.features?.[0]?.properties?.i;
      if (!d || !d.closed || typeof i !== "number") return;
      e.preventDefault();
      dragging = i;
      map.dragPan.disable();
    });
    map.on("mousemove", (e: MapMouseEvent) => {
      const d = drawRef.current;
      if (dragging === null || !d) return;
      const points = d.points.map((p, j) => (j === dragging ? ([e.lngLat.lng, e.lngLat.lat] as LngLat) : p));
      report({ points, closed: true });
    });
    map.on("mouseup", () => {
      if (dragging === null) return;
      dragging = null;
      map.dragPan.enable();
    });
    map.on("mouseenter", DRAW_POINTS, () => {
      if (drawRef.current?.closed) map.getCanvas().style.cursor = "move";
    });
    map.on("mouseleave", DRAW_POINTS, () => {
      if (drawRef.current?.closed) map.getCanvas().style.cursor = "";
    });
    // A touch screen: one finger draws the whole shape, which closes when it lifts.
    let stroke: { px: { x: number; y: number }[]; at: LngLat[] } | null = null;
    map.on("touchstart", (e: MapTouchEvent) => {
      const d = drawRef.current;
      if (!d || d.closed || e.points.length !== 1) return;
      e.preventDefault();
      map.dragPan.disable();
      stroke = { px: [e.point], at: [[e.lngLat.lng, e.lngLat.lat]] };
      report({ points: stroke.at, closed: false, stroke: true });
    });
    map.on("touchmove", (e: MapTouchEvent) => {
      if (!stroke) return;
      e.preventDefault();
      const last = stroke.px[stroke.px.length - 1];
      if (Math.hypot(last.x - e.point.x, last.y - e.point.y) < 6) return;
      stroke.px.push(e.point);
      stroke.at.push([e.lngLat.lng, e.lngLat.lat]);
      report({ points: [...stroke.at], closed: false, stroke: true });
    });
    map.on("touchend", () => {
      if (!stroke) return;
      const s = stroke;
      stroke = null;
      lastTouchAt = Date.now();
      map.dragPan.enable();
      const kept = s.px.length >= 3 ? simplifyStroke(s.px, STROKE_POINTS).map((i) => s.at[i]) : [];
      report(kept.length >= 3 ? { points: kept, closed: true, stroke: true } : { points: [], closed: false });
    });

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

  // The drawn area, or the shape being drawn: redraw it. While drawing, a crosshair, and no
  // zoom on double-click (it closes the shape).
  useEffect(() => {
    drawRef.current = draw ?? null;
    shapeRef.current = shape ?? null;
    const map = mapRef.current;
    if (!map) return;
    if (draw) map.doubleClickZoom.disable();
    else map.doubleClickZoom.enable();
    map.getCanvas().style.cursor = draw && !draw.closed ? "crosshair" : "";
    if (readyRef.current) (map.getSource(DRAW_SOURCE) as GeoJSONSource | undefined)?.setData(drawFeatures(draw ?? null, shape ?? null));
  }, [draw, shape]);

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
    const camera = map.cameraForBounds(areaBounds(area), { padding: areaPadding(map.getContainer()) });
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
      <div role="group" aria-label="Map look" className="absolute left-2.5 top-2.5 z-[2] flex rounded-[10px] bg-white p-[3px] shadow-[0_1px_4px_rgba(0,0,0,0.25)]">
        {(["map", "satellite"] as const).map((k) => (
          <button
            key={k}
            type="button"
            aria-pressed={kind === k}
            onClick={() => setKind(k)}
            className={`h-8 rounded-[7px] px-3 text-[13px] font-medium ${kind === k ? "bg-primary text-white" : "text-zinc-950 hover:bg-zinc-100"}`}
          >
            {/* "Streets", not "Map": the view switch (List · Split · Map) already says Map. */}
            {k === "map" ? "Streets" : "Satellite"}
          </button>
        ))}
      </div>
      {children}
    </div>
  );
}
