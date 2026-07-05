"use client";

import { useEffect, useRef } from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

const DEFAULT_ICON = L.icon({
  iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png",
  iconRetinaUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41],
});

export type MapMarkerEntity = {
  id: string;
  name: string;
  address: string;
  lat: number;
  lng: number;
  matchesFilter: boolean;
};

export type MapBounds = {
  north: number;
  south: number;
  east: number;
  west: number;
};

type Props = {
  entities: MapMarkerEntity[];
  jumpTo: { lat: number; lng: number } | null;
  onBoundsChange: (bounds: MapBounds) => void;
};

function escapeHtml(s: string) {
  const map: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  };
  return s.replace(/[&<>"']/g, (c) => map[c]);
}

export default function StarredMap({ entities, jumpTo, onBoundsChange }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const markersRef = useRef<Map<string, L.Marker>>(new Map());
  const initialFitDoneRef = useRef(false);
  const onBoundsChangeRef = useRef(onBoundsChange);

  useEffect(() => {
    onBoundsChangeRef.current = onBoundsChange;
  }, [onBoundsChange]);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    // A fresh map instance means no markers actually exist on it yet, even if
    // markersRef (a plain ref) still remembers marker objects from a previous
    // instance - this matters in dev because React Strict Mode destroys and
    // recreates the map once on mount, and refs survive that cycle.
    markersRef.current.forEach((m) => m.remove());
    markersRef.current.clear();
    initialFitDoneRef.current = false;

    const map = L.map(containerRef.current);
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19,
    }).addTo(map);

    map.setView([38.88, -77.1], 12);

    function emitBounds() {
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
    mapRef.current = map;
    emitBounds();

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

    const boundsPoints: [number, number][] = [];
    for (const entity of entities) {
      boundsPoints.push([entity.lat, entity.lng]);
      let marker = markersRef.current.get(entity.id);
      if (!marker) {
        marker = L.marker([entity.lat, entity.lng], { icon: DEFAULT_ICON });
        marker.bindPopup(
          `<strong>${escapeHtml(entity.name)}</strong><br/>${escapeHtml(entity.address)}`
        );
        marker.addTo(map);
        markersRef.current.set(entity.id, marker);
      }
      marker.setOpacity(entity.matchesFilter ? 1 : 0.25);
    }

    if (boundsPoints.length > 0 && !initialFitDoneRef.current) {
      map.fitBounds(boundsPoints, { padding: [30, 30], maxZoom: 15 });
      initialFitDoneRef.current = true;
    }
  }, [entities]);

  useEffect(() => {
    if (jumpTo && mapRef.current) {
      mapRef.current.flyTo([jumpTo.lat, jumpTo.lng], 13);
    }
  }, [jumpTo]);

  return <div ref={containerRef} className="h-96 w-full rounded-lg" />;
}
