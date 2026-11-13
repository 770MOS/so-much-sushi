"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import maplibregl from "maplibre-gl";
import type { GeoJSONSource, MapLayerMouseEvent, Offset } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { getMapStyleUrl, DEFAULT_MAP_CENTER, DEFAULT_MAP_ZOOM } from "@/lib/mapConfig";
import { closedLabel } from "@/lib/entityStatus";
import type { EntityType } from "@/lib/entityTypes";

export type MapMarkerEntity = {
  id: string;
  name: string;
  address: string | null;
  lat: number;
  lng: number;
  matchesFilter: boolean;
  isStarred: boolean;
  recommendedCount: number;
  // On the person's ready-made Want to try list.
  isWant?: boolean;
  status?: string;
  // Which of the 5 marker-icon shapes this pin gets - see
  // src/lib/entityTypes.ts's topLevelTypeForCategoryPaths. Purely about
  // which icon renders; color still means personal status (starred/
  // recommended/filtered), never category - the two are deliberately kept
  // independent.
  entityType?: Exclude<EntityType, "all"> | null;
};

export type MapBounds = {
  north: number;
  south: number;
  east: number;
  west: number;
};

type Props = {
  entities: MapMarkerEntity[];
  jumpTo?: { lat: number; lng: number } | null;
  onBoundsChange?: (bounds: MapBounds) => void;
  onToggleStar?: (id: string) => void;
  className?: string;
  // The map fits itself to the places once; a new fitKey (a new search) fits it again.
  fitKey?: string;
  // A place to draw larger, e.g. the list row under the pointer.
  highlightId?: string | null;
};

// Shared with the heart icon/pin coloring below, so the popup's heart button,
// the pin itself, and the list view's FavoriteIcon (src/components/icons.tsx)
// never disagree on what "favorite" looks like. (The data still calls a
// favorite a "star": the table is stars.)
const STARRED_COLOR = "#e04e76"; // --favorite, the rose heart
const UNSTARRED_COLOR = "#222222"; // plain places: the dark pin from the mockups

// Same path as FavoriteIcon in src/components/icons.tsx - duplicated here
// because this element is built with raw DOM APIs (a React component can't
// be rendered into a MapLibre marker/popup), not because it's a different
// icon.
const STAR_ICON_PATH =
  "M19.5 12.572l-7.5 7.428l-7.5 -7.428a5 5 0 1 1 7.5 -6.566a5 5 0 1 1 7.5 6.572";

// Same path data as RestaurantTypeIcon/BarTypeIcon/CoffeeTypeIcon/
// BakeryTypeIcon in src/components/icons.tsx (drinks uses the bar icon,
// markets the bakery icon) - duplicated
// here for the same raw-DOM reason as STAR_ICON_PATH above. Original
// source: Tabler Icons (tools-kitchen-2, glass-cocktail, cup, bread, beer -
// github.com/tabler/tabler-icons, MIT licensed).
const CATEGORY_ICON_PATHS: Record<Exclude<EntityType, "all">, string[]> = {
  restaurants: [
    "M19 3v12h-5c-.023 -3.681 .184 -7.406 5 -12m0 12v6h-1v-3m-10 -14v17m-3 -17v3a3 3 0 1 0 6 0v-3",
  ],
  drinks: [
    "M8 21h8",
    "M12 15v6",
    "M5 5a7 2 0 1 0 14 0a7 2 0 1 0 -14 0",
    "M5 5v.388c0 .432 .126 .853 .362 1.206l5 7.509c.633 .951 1.88 1.183 2.785 .517c.191 -.141 .358 -.316 .491 -.517l5 -7.509c.236 -.353 .362 -.774 .362 -1.206v-.388",
  ],
  coffee: [
    "M5 11h14v-3h-14l0 3",
    "M17.5 11l-1.5 10h-8l-1.5 -10",
    "M6 8v-1a2 2 0 0 1 2 -2h8a2 2 0 0 1 2 2v1",
    "M15 5v-2",
  ],
  markets: [
    "M18 4a3 3 0 0 1 2 5.235v8.765a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-8.764a3 3 0 0 1 1.824 -5.231h12.176v-.005",
  ],
};

// The category icon renders inside the pin's white circle (r=4.5, centered
// at 12,12 of the pin's own 24x32 viewBox - see pinImageSvg below). Tabler
// icons are natively a 24x24 viewBox; scaling by 1/3 and translating by
// (8,8) maps that down to an 8x8 box spanning (8,8)-(16,16), just inside
// the circle. The stroke is the pin's own status color (rose/dark) - color
// still means personal status, the icon shape is the only category signal.
function categoryIconMarkup(entityType: Exclude<EntityType, "all"> | null | undefined, color: string): string {
  if (!entityType) return "";
  const pathElements = CATEGORY_ICON_PATHS[entityType].map((d) => `<path d="${d}"/>`).join("");
  return `<g transform="translate(8,8) scale(0.333)" fill="none" stroke="${color}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">${pathElements}</g>`;
}

// Pins are drawn by MapLibre as one symbol layer (not one HTML element per
// place), so a search with up to 1,000 results stays smooth to pan and zoom.
// Each look a pin can have - category icon x starred x recommended badge - is
// registered once as a map image and picked per place by its "icon" property.
const SOURCE_ID = "sms-places";
const LAYER_ID = "sms-places-pins";
const PIN_TYPES: (Exclude<EntityType, "all"> | null)[] = ["restaurants", "drinks", "coffee", "markets", null];
const RECOMMENDED_COLOR = "#19693f"; // --friends, the dark green of the friends' thumbs up

// Image size in CSS pixels: the pin itself is 28x36 as before, plus 2px to the
// right and above so the recommended badge, which sticks out past the pin's
// top-right corner, isn't clipped. Drawn at 2x so pins stay sharp on retina.
const IMAGE_WIDTH = 30;
const IMAGE_HEIGHT = 38;
const IMAGE_SCALE = 2;
// The pin's tip is at x=14 of the 30px-wide image; the layer anchors the
// image's bottom-centre (x=15) on the place, so nudge it 1px right.
const ICON_OFFSET: [number, number] = [1, 0];
// Popups open above the pin's head (it now points at the place with its tip),
// or beside/below it when there isn't room above.
const POPUP_OFFSET: Offset = {
  center: [0, -IMAGE_HEIGHT / 2],
  top: [0, 0],
  "top-left": [0, 0],
  "top-right": [0, 0],
  bottom: [0, -IMAGE_HEIGHT],
  "bottom-left": [0, -IMAGE_HEIGHT],
  "bottom-right": [0, -IMAGE_HEIGHT],
  left: [14, -IMAGE_HEIGHT / 2],
  right: [-14, -IMAGE_HEIGHT / 2],
};

function pinImageId(entityType: Exclude<EntityType, "all"> | null | undefined, starred: boolean, recommended: boolean) {
  return `sms-pin-${entityType ?? "none"}-${starred ? 1 : 0}-${recommended ? 1 : 0}`;
}

function pinImageSvg(entityType: Exclude<EntityType, "all"> | null, color: string, recommended: boolean): string {
  // The badge matches the old HTML marker's: 13px across, 1.5px white border,
  // 2px past the pin's top-right corner.
  const badge = recommended
    ? `<circle cx="23.5" cy="6.5" r="5.75" fill="${RECOMMENDED_COLOR}" stroke="white" stroke-width="1.5"/>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${IMAGE_WIDTH * IMAGE_SCALE}" height="${IMAGE_HEIGHT * IMAGE_SCALE}" viewBox="0 0 ${IMAGE_WIDTH} ${IMAGE_HEIGHT}">
    <svg x="0" y="2" width="28" height="36" viewBox="0 0 24 32">
      <path d="M12 0C5.373 0 0 5.373 0 12c0 9 12 20 12 20s12-11 12-20c0-6.627-5.373-12-12-12z" fill="${color}"/>
      <circle cx="12" cy="12" r="4.5" fill="white" fill-opacity="0.9"/>
      ${categoryIconMarkup(entityType, color)}
    </svg>
    ${badge}
  </svg>`;
}

// Places with a status of the person's own get a round marker with its icon in place of the
// pin (decided 2026-11-11): a rose heart for their favorites, a green thumbs up for friends'
// favorites, a blue flag for Want to try. One per place, in that order of priority.
type Mark = "fav" | "friend" | "want";
const MARK_SIZE = 32;
const MARKS: Record<Mark, { fill: string; path: string; iconFill: string }> = {
  fav: { fill: STARRED_COLOR, path: STAR_ICON_PATH, iconFill: "#ffffff" },
  friend: {
    fill: RECOMMENDED_COLOR,
    path: "M7 11v8a1 1 0 0 1 -1 1h-2a1 1 0 0 1 -1 -1v-7a1 1 0 0 1 1 -1h3a4 4 0 0 0 4 -4v-1a2 2 0 0 1 4 0v5h3a2 2 0 0 1 2 2l-1 5a2 3 0 0 1 -2 2h-7a3 3 0 0 1 -3 -3",
    iconFill: "none",
  },
  want: { fill: "#3b5bdb", path: "M5 5a5 5 0 0 1 7 0a5 5 0 0 0 7 0v9a5 5 0 0 1 -7 0a5 5 0 0 0 -7 0v-9zM5 21v-7", iconFill: "none" },
};

function markFor(entity: MapMarkerEntity): Mark | null {
  if (entity.isStarred) return "fav";
  if (entity.recommendedCount > 0) return "friend";
  if (entity.isWant) return "want";
  return null;
}

function markImageSvg(mark: Mark): string {
  const { fill, path, iconFill } = MARKS[mark];
  const s = MARK_SIZE;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${s * IMAGE_SCALE}" height="${s * IMAGE_SCALE}" viewBox="0 0 ${s} ${s}">
    <circle cx="16" cy="16" r="14.75" fill="${fill}" stroke="white" stroke-width="2.5"/>
    <g transform="translate(7.5,7.5) scale(0.7083)" fill="${iconFill}" stroke="white" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="${path}"/></g>
  </svg>`;
}

function loadSvgImage(svg: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const image = new Image(IMAGE_WIDTH * IMAGE_SCALE, IMAGE_HEIGHT * IMAGE_SCALE);
    image.onload = () => resolve(image);
    image.onerror = reject;
    image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
  });
}

async function addPinImages(map: maplibregl.Map, isCancelled: () => boolean) {
  const jobs: Promise<void>[] = [];
  for (const mark of Object.keys(MARKS) as Mark[]) {
    const id = `sms-mark-${mark}`;
    if (map.hasImage(id)) continue;
    const image = new Image(MARK_SIZE * IMAGE_SCALE, MARK_SIZE * IMAGE_SCALE);
    jobs.push(
      new Promise<void>((resolve, reject) => {
        image.onload = () => {
          if (!isCancelled() && !map.hasImage(id)) map.addImage(id, image, { pixelRatio: IMAGE_SCALE });
          resolve();
        };
        image.onerror = reject;
        image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(markImageSvg(mark))}`;
      })
    );
  }
  // Plain places only: places with a status get a round marker instead.
  for (const entityType of PIN_TYPES) {
    const id = pinImageId(entityType, false, false);
    if (map.hasImage(id)) continue;
    jobs.push(
      loadSvgImage(pinImageSvg(entityType, UNSTARRED_COLOR, false)).then((image) => {
        if (!isCancelled() && !map.hasImage(id)) map.addImage(id, image, { pixelRatio: IMAGE_SCALE });
      })
    );
  }
  await Promise.all(jobs);
}

function toFeatureCollection(entities: MapMarkerEntity[]): GeoJSON.FeatureCollection<GeoJSON.Point> {
  return {
    type: "FeatureCollection",
    features: entities.map((entity) => {
      const filterOpacity = entity.matchesFilter ? 1 : 0.25;
      const statusOpacity = entity.status && entity.status !== "active" ? 0.55 : 1;
      const mark = markFor(entity);
      return {
        type: "Feature",
        geometry: { type: "Point", coordinates: [entity.lng, entity.lat] },
        properties: {
          id: entity.id,
          icon: mark ? `sms-mark-${mark}` : pinImageId(entity.entityType, false, false),
          // A pin points at the place with its tip; a round marker sits centred on it.
          anchor: mark ? "center" : "bottom",
          offset: mark ? [0, 0] : ICON_OFFSET,
          opacity: filterOpacity * statusOpacity,
          // Status markers draw above plain pins: favorites, then friends', then Want to try.
          sortKey: mark === "fav" ? 3 : mark === "friend" ? 2 : mark === "want" ? 1 : 0,
        },
      };
    }),
  };
}

function escapeHtml(s: string | null | undefined) {
  if (!s) return "";
  const map: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  };
  return s.replace(/[&<>"']/g, (c) => map[c]);
}

function setStarButtonAppearance(button: HTMLButtonElement, isStarred: boolean) {
  const svg = button.querySelector("svg");
  if (svg) {
    svg.setAttribute("fill", isStarred ? STARRED_COLOR : "none");
    svg.setAttribute("stroke", isStarred ? STARRED_COLOR : UNSTARRED_COLOR);
  }
  button.setAttribute("aria-pressed", String(isStarred));
  button.setAttribute("aria-label", isStarred ? "Remove from your favorites" : "Add to your favorites");
}

function createStarButton(isStarred: boolean): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.style.display = "inline-flex";
  button.style.alignItems = "center";
  button.style.justifyContent = "center";
  button.style.flexShrink = "0";
  button.style.padding = "2px";
  button.style.border = "none";
  button.style.background = "none";
  button.style.cursor = "pointer";
  button.innerHTML = `<svg viewBox="0 0 24 24" width="18" height="18" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="${STAR_ICON_PATH}"/></svg>`;
  setStarButtonAppearance(button, isStarred);
  return button;
}

// Popup content built via DOM APIs rather than Popup.setHTML(string) - a
// starring click needs a real event listener, and the star icon needs to
// be updated in place (without rebuilding the whole popup) whenever this
// entity's starred state changes on a later render.
function createPopupContent(entity: MapMarkerEntity): {
  element: HTMLDivElement;
  starButton: HTMLButtonElement;
  nameLink: HTMLAnchorElement;
} {
  const container = document.createElement("div");

  const topRow = document.createElement("div");
  topRow.style.display = "flex";
  topRow.style.alignItems = "center";
  topRow.style.justifyContent = "space-between";
  topRow.style.gap = "8px";

  // A real <a href> (not just a click handler) so middle-click/"open in new
  // tab"/right-click still work as an actual link - the click handler
  // wired up by the caller intercepts the plain left-click case to use
  // Next's router instead, which is what lets /venue/[id] open as a modal
  // here rather than a full navigation.
  const nameLink = document.createElement("a");
  nameLink.href = `/venue/${entity.id}`;
  nameLink.style.color = "inherit";
  nameLink.style.textDecoration = "none";
  nameLink.style.cursor = "pointer";
  const label = entity.status ? closedLabel(entity.status) : null;
  nameLink.innerHTML = label
    ? `<strong>${escapeHtml(entity.name)}</strong> <span style="color:#71717a;">(${label})</span>`
    : `<strong>${escapeHtml(entity.name)}</strong>`;

  const starButton = createStarButton(entity.isStarred);

  topRow.appendChild(nameLink);
  topRow.appendChild(starButton);
  container.appendChild(topRow);

  if (entity.address) {
    const addressLine = document.createElement("div");
    addressLine.textContent = entity.address;
    container.appendChild(addressLine);
  }

  return { element: container, starButton, nameLink };
}

export default function EntityMap({ entities, jumpTo, onBoundsChange, onToggleStar, className, fitKey, highlightId }: Props) {
  const router = useRouter();
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  // True once the pin images, source and layer exist on the current map.
  const layerReadyRef = useRef(false);
  const entitiesRef = useRef(entities);
  const entityByIdRef = useRef<Map<string, MapMarkerEntity>>(new Map());
  const popupRef = useRef<{ id: string; popup: maplibregl.Popup; starButton: HTMLButtonElement } | null>(null);
  // The fitKey the map last fitted itself to (undefined: not fitted yet).
  const fittedKeyRef = useRef<string | undefined>(undefined);
  const highlightRef = useRef<string | null>(highlightId ?? null);
  const routerRef = useRef(router);
  const onBoundsChangeRef = useRef(onBoundsChange);
  const onToggleStarRef = useRef(onToggleStar);

  useEffect(() => {
    routerRef.current = router;
  }, [router]);

  useEffect(() => {
    onBoundsChangeRef.current = onBoundsChange;
  }, [onBoundsChange]);

  useEffect(() => {
    onToggleStarRef.current = onToggleStar;
  }, [onToggleStar]);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    // A fresh map instance has no pins or popup yet, even if refs (which
    // survive React Strict Mode's mount/unmount/mount in dev) remember them
    // from a previous instance.
    let cancelled = false;
    layerReadyRef.current = false;
    popupRef.current = null;
    fittedKeyRef.current = undefined;

    const map = new maplibregl.Map({
      container: containerRef.current,
      style: getMapStyleUrl(),
      center: DEFAULT_MAP_CENTER,
      zoom: DEFAULT_MAP_ZOOM,
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-left");

    function emitBounds() {
      if (!onBoundsChangeRef.current) return;
      const b = map.getBounds();
      onBoundsChangeRef.current({
        north: b.getNorth(),
        south: b.getSouth(),
        east: b.getEast(),
        west: b.getWest(),
      });
    }

    function openPopup(entity: MapMarkerEntity) {
      const open = popupRef.current;
      open?.popup.remove();
      // Clicking the pin whose popup is already open closes it, as before.
      if (open?.id === entity.id) return;

      const { element, starButton, nameLink } = createPopupContent(entity);
      starButton.addEventListener("click", (event) => {
        event.stopPropagation();
        onToggleStarRef.current?.(entity.id);
      });
      nameLink.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        routerRef.current.push(`/venue/${entity.id}`);
      });

      const popup = new maplibregl.Popup({ offset: markFor(entity) ? MARK_SIZE / 2 : POPUP_OFFSET })
        .setLngLat([entity.lng, entity.lat])
        .setDOMContent(element)
        .addTo(map);
      const current = { id: entity.id, popup, starButton };
      popupRef.current = current;
      popup.on("close", () => {
        if (popupRef.current === current) popupRef.current = null;
      });
    }

    map.on("moveend", emitBounds);
    map.on("zoomend", emitBounds);
    map.on("load", emitBounds);

    map.on("load", async () => {
      await addPinImages(map, () => cancelled);
      if (cancelled) return;
      map.addSource(SOURCE_ID, { type: "geojson", data: toFeatureCollection(entitiesRef.current) });
      map.addLayer({
        id: LAYER_ID,
        type: "symbol",
        source: SOURCE_ID,
        layout: {
          "icon-image": ["get", "icon"],
          "icon-anchor": ["get", "anchor"],
          "icon-offset": ["get", "offset"],
          "icon-size": ["case", ["==", ["get", "id"], highlightRef.current ?? ""], 1.3, 1],
          // Every pin is shown, even where pins overlap, as with the old markers.
          "icon-allow-overlap": true,
          "icon-ignore-placement": true,
          "symbol-sort-key": ["get", "sortKey"],
        },
        paint: {
          "icon-opacity": ["get", "opacity"],
        },
      });
      layerReadyRef.current = true;
    });

    map.on("click", LAYER_ID, (event: MapLayerMouseEvent) => {
      const id = event.features?.[0]?.properties?.id as string | undefined;
      const entity = id ? entityByIdRef.current.get(id) : undefined;
      if (entity) openPopup(entity);
    });
    map.on("mouseenter", LAYER_ID, () => {
      map.getCanvas().style.cursor = "pointer";
    });
    map.on("mouseleave", LAYER_ID, () => {
      map.getCanvas().style.cursor = "";
    });

    mapRef.current = map;

    // The box can change size after the map starts (a sticky column, the phone's List/Map
    // switch, the window): redraw to fit instead of leaving a blank strip.
    const resizeObserver = new ResizeObserver(() => map.resize());
    resizeObserver.observe(containerRef.current);

    return () => {
      cancelled = true;
      resizeObserver.disconnect();
      layerReadyRef.current = false;
      popupRef.current = null;
      map.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    entitiesRef.current = entities;
    entityByIdRef.current = new Map(entities.map((e) => [e.id, e]));

    const map = mapRef.current;
    if (!map) return;

    // Before the layer exists, the load handler picks up entitiesRef instead.
    if (layerReadyRef.current) {
      (map.getSource(SOURCE_ID) as GeoJSONSource | undefined)?.setData(toFeatureCollection(entities));
    }

    // Keep an open popup in step: its star button follows starred state
    // changed anywhere, and it closes if its place is no longer in the results.
    const open = popupRef.current;
    if (open) {
      const entity = entityByIdRef.current.get(open.id);
      if (entity) setStarButtonAppearance(open.starButton, entity.isStarred);
      else open.popup.remove();
    }

    const key = fitKey ?? "once";
    if (entities.length > 0 && fittedKeyRef.current !== key) {
      const bounds = new maplibregl.LngLatBounds();
      for (const entity of entities) bounds.extend([entity.lng, entity.lat]);
      // Extra room at the top: pins stand above the point they mark.
      // Worked out with padding, then moved to without it: passing padding to fitBounds keeps
      // it on the map afterwards, which shifts every later move and left part of a tall map
      // (a phone's) unpainted.
      const camera = map.cameraForBounds(bounds, {
        padding: { top: 40 + IMAGE_HEIGHT, bottom: 40, left: 40, right: 40 },
        maxZoom: 15,
      });
      if (camera) map.jumpTo({ center: camera.center, zoom: camera.zoom });
      fittedKeyRef.current = key;
    }
  }, [entities, fitKey]);

  useEffect(() => {
    highlightRef.current = highlightId ?? null;
    const map = mapRef.current;
    if (!map || !layerReadyRef.current) return;
    map.setLayoutProperty(LAYER_ID, "icon-size", ["case", ["==", ["get", "id"], highlightId ?? ""], 1.3, 1]);
  }, [highlightId]);

  useEffect(() => {
    if (jumpTo && mapRef.current) {
      mapRef.current.flyTo({ center: [jumpTo.lng, jumpTo.lat], zoom: 13 });
    }
  }, [jumpTo]);

  return <div ref={containerRef} className={className ?? "h-96 w-full rounded-lg"} />;
}
