"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { getMapStyleUrl, DEFAULT_MAP_CENTER, DEFAULT_MAP_ZOOM } from "@/lib/mapConfig";
import { closedLabel } from "@/lib/entityStatus";

export type MapMarkerEntity = {
  id: string;
  name: string;
  address: string | null;
  lat: number;
  lng: number;
  matchesFilter: boolean;
  isStarred: boolean;
  recommendedCount: number;
  status?: string;
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
};

// Shared with the star icon/pin coloring below, so the popup's star button,
// the pin itself, and the list view's StarIcon (src/components/icons.tsx)
// never disagree on what "starred" looks like.
const STARRED_COLOR = "#fbbf24"; // amber-400
const UNSTARRED_COLOR = "#a1a1aa"; // zinc-400

// Same path as StarIcon in src/components/icons.tsx - duplicated here
// because this element is built with raw DOM APIs (a React component can't
// be rendered into a MapLibre marker/popup), not because it's a different
// icon.
const STAR_ICON_PATH =
  "M12 3.5l2.6 5.27 5.82.85-4.21 4.1.99 5.8L12 16.9l-5.2 2.62.99-5.8-4.21-4.1 5.82-.85L12 3.5z";

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

const PIN_SVG = `
  <svg viewBox="0 0 24 32" width="28" height="36" xmlns="http://www.w3.org/2000/svg">
    <path d="M12 0C5.373 0 0 5.373 0 12c0 9 12 20 12 20s12-11 12-20c0-6.627-5.373-12-12-12z" fill="currentColor"/>
    <circle cx="12" cy="12" r="4.5" fill="white" fill-opacity="0.9"/>
  </svg>
`;

function createMarkerElement(isStarred: boolean, recommendedCount: number): HTMLDivElement {
  const wrapper = document.createElement("div");
  // This element becomes the root of a maplibregl.Marker, which requires
  // `position: absolute` (see .maplibregl-marker in maplibre-gl.css) so it
  // can be placed via a CSS transform. An inline `position: relative` here
  // used to override that (inline styles beat class rules), leaving every
  // marker in normal document flow instead - each one stacking ~36px below
  // the last rather than at its actual map position, which is what caused
  // all pins to render in a single vertical line regardless of their real
  // coordinates. `absolute` still gives the recommended-count badge below
  // a valid positioning context, so it doesn't need `relative` specifically.
  wrapper.style.position = "absolute";
  wrapper.style.width = "28px";
  wrapper.style.height = "36px";
  wrapper.style.color = isStarred ? STARRED_COLOR : UNSTARRED_COLOR;
  wrapper.innerHTML = PIN_SVG;

  if (recommendedCount > 0) {
    const badge = document.createElement("div");
    badge.style.position = "absolute";
    badge.style.top = "-2px";
    badge.style.right = "-2px";
    badge.style.width = "13px";
    badge.style.height = "13px";
    badge.style.borderRadius = "9999px";
    badge.style.background = "#fb7185"; // rose-400 - matches the heart icon elsewhere in the app
    badge.style.border = "1.5px solid white";
    wrapper.appendChild(badge);
  }

  return wrapper;
}

function setStarButtonAppearance(button: HTMLButtonElement, isStarred: boolean) {
  const svg = button.querySelector("svg");
  if (svg) {
    svg.setAttribute("fill", isStarred ? STARRED_COLOR : "none");
    svg.setAttribute("stroke", isStarred ? STARRED_COLOR : UNSTARRED_COLOR);
  }
  button.setAttribute("aria-pressed", String(isStarred));
  button.setAttribute("aria-label", isStarred ? "Unstar this place" : "Star this place");
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
  button.innerHTML = `<svg viewBox="0 0 24 24" width="18" height="18" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="${STAR_ICON_PATH}"/></svg>`;
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

export default function EntityMap({ entities, jumpTo, onBoundsChange, onToggleStar, className }: Props) {
  const router = useRouter();
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const markersRef = useRef<Map<string, maplibregl.Marker>>(new Map());
  const starButtonsRef = useRef<Map<string, HTMLButtonElement>>(new Map());
  const initialFitDoneRef = useRef(false);
  const onBoundsChangeRef = useRef(onBoundsChange);
  const onToggleStarRef = useRef(onToggleStar);

  useEffect(() => {
    onBoundsChangeRef.current = onBoundsChange;
  }, [onBoundsChange]);

  useEffect(() => {
    onToggleStarRef.current = onToggleStar;
  }, [onToggleStar]);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    // A fresh map instance means no markers actually exist on it yet, even if
    // markersRef (a plain ref) still remembers marker objects from a previous
    // instance - matters in dev because React Strict Mode destroys and
    // recreates the map once on mount, and refs survive that cycle.
    markersRef.current.forEach((m) => m.remove());
    markersRef.current.clear();
    starButtonsRef.current.clear();
    initialFitDoneRef.current = false;

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

    map.on("moveend", emitBounds);
    map.on("zoomend", emitBounds);
    map.on("load", emitBounds);
    mapRef.current = map;

    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    const currentIds = new Set(entities.map((e) => e.id));
    for (const [id, marker] of markersRef.current) {
      if (!currentIds.has(id)) {
        marker.remove();
        markersRef.current.delete(id);
        starButtonsRef.current.delete(id);
      }
    }

    const bounds = new maplibregl.LngLatBounds();
    for (const entity of entities) {
      bounds.extend([entity.lng, entity.lat]);

      let marker = markersRef.current.get(entity.id);
      if (!marker) {
        const element = createMarkerElement(entity.isStarred, entity.recommendedCount);
        const { element: popupContent, starButton, nameLink } = createPopupContent(entity);
        starButton.addEventListener("click", (event) => {
          event.stopPropagation();
          onToggleStarRef.current?.(entity.id);
        });
        starButtonsRef.current.set(entity.id, starButton);
        nameLink.addEventListener("click", (event) => {
          event.preventDefault();
          event.stopPropagation();
          router.push(`/venue/${entity.id}`);
        });

        marker = new maplibregl.Marker({ element })
          .setLngLat([entity.lng, entity.lat])
          .setPopup(new maplibregl.Popup({ offset: 20 }).setDOMContent(popupContent))
          .addTo(map);
        markersRef.current.set(entity.id, marker);
      } else {
        // Popup content (and the star button inside it) is only built once,
        // at marker creation - refresh it in place here so a starred state
        // that changed since then (e.g. the user just toggled it, from this
        // popup or anywhere else) is reflected without recreating the popup.
        const starButton = starButtonsRef.current.get(entity.id);
        if (starButton) setStarButtonAppearance(starButton, entity.isStarred);
      }

      // The pin's own color is set once at creation too - keep it in sync
      // with starred state for the same reason as the popup button above.
      marker.getElement().style.color = entity.isStarred ? STARRED_COLOR : UNSTARRED_COLOR;

      const filterOpacity = entity.matchesFilter ? 1 : 0.25;
      const statusOpacity = entity.status && entity.status !== "active" ? 0.55 : 1;
      marker.getElement().style.opacity = String(filterOpacity * statusOpacity);
    }

    if (entities.length > 0 && !initialFitDoneRef.current) {
      map.fitBounds(bounds, { padding: 40, maxZoom: 15, duration: 0 });
      initialFitDoneRef.current = true;
    }
  }, [entities, router]);

  useEffect(() => {
    if (jumpTo && mapRef.current) {
      mapRef.current.flyTo({ center: [jumpTo.lng, jumpTo.lat], zoom: 13 });
    }
  }, [jumpTo]);

  return <div ref={containerRef} className={className ?? "h-96 w-full rounded-lg"} />;
}
