"use client";

import { useEffect, useRef } from "react";
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
  className?: string;
};

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
  // amber-400 for starred (matches the star icon elsewhere in the app),
  // zinc-400 plain pin otherwise.
  wrapper.style.color = isStarred ? "#fbbf24" : "#a1a1aa";
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

export default function EntityMap({ entities, jumpTo, onBoundsChange, className }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const markersRef = useRef<Map<string, maplibregl.Marker>>(new Map());
  const initialFitDoneRef = useRef(false);
  const onBoundsChangeRef = useRef(onBoundsChange);

  useEffect(() => {
    onBoundsChangeRef.current = onBoundsChange;
  }, [onBoundsChange]);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    // A fresh map instance means no markers actually exist on it yet, even if
    // markersRef (a plain ref) still remembers marker objects from a previous
    // instance - matters in dev because React Strict Mode destroys and
    // recreates the map once on mount, and refs survive that cycle.
    markersRef.current.forEach((m) => m.remove());
    markersRef.current.clear();
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
      }
    }

    const bounds = new maplibregl.LngLatBounds();
    for (const entity of entities) {
      bounds.extend([entity.lng, entity.lat]);

      let marker = markersRef.current.get(entity.id);
      if (!marker) {
        const element = createMarkerElement(entity.isStarred, entity.recommendedCount);
        const label = entity.status ? closedLabel(entity.status) : null;
        const nameLine = label
          ? `<strong>${escapeHtml(entity.name)}</strong> <span style="color:#71717a;">(${label})</span>`
          : `<strong>${escapeHtml(entity.name)}</strong>`;
        const popupHtml = entity.address ? `${nameLine}<br/>${escapeHtml(entity.address)}` : nameLine;
        marker = new maplibregl.Marker({ element })
          .setLngLat([entity.lng, entity.lat])
          .setPopup(new maplibregl.Popup({ offset: 20 }).setHTML(popupHtml))
          .addTo(map);
        markersRef.current.set(entity.id, marker);
      }
      const filterOpacity = entity.matchesFilter ? 1 : 0.25;
      const statusOpacity = entity.status && entity.status !== "active" ? 0.55 : 1;
      marker.getElement().style.opacity = String(filterOpacity * statusOpacity);
    }

    if (entities.length > 0 && !initialFitDoneRef.current) {
      map.fitBounds(bounds, { padding: 40, maxZoom: 15, duration: 0 });
      initialFitDoneRef.current = true;
    }
  }, [entities]);

  useEffect(() => {
    if (jumpTo && mapRef.current) {
      mapRef.current.flyTo({ center: [jumpTo.lng, jumpTo.lat], zoom: 13 });
    }
  }, [jumpTo]);

  return <div ref={containerRef} className={className ?? "h-96 w-full rounded-lg"} />;
}
