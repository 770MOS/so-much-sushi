"use client";

// A map to place a pin by clicking. The pin's position goes into hidden "lat"/"lng"
// inputs. "Find on map" only moves the map to a typed address; the pin is always placed
// by hand, so the position is our own observation.
import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { getMapStyleUrl, DEFAULT_MAP_CENTER, DEFAULT_MAP_ZOOM } from "@/lib/mapConfig";
import { forwardGeocodeCityState } from "@/lib/forwardGeocode";

type Pin = { lat: number; lng: number } | null;

export default function MapPicker({ initial, addressFieldIds }: { initial: Pin; addressFieldIds: string[] }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const markerRef = useRef<maplibregl.Marker | null>(null);
  const [pin, setPin] = useState<Pin>(initial);
  const [finding, setFinding] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!containerRef.current) return;
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: getMapStyleUrl(),
      center: initial ? [initial.lng, initial.lat] : DEFAULT_MAP_CENTER,
      zoom: initial ? 17 : DEFAULT_MAP_ZOOM,
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-left");
    map.getCanvas().style.cursor = "crosshair";
    map.on("click", (e) => setPin({ lat: Number(e.lngLat.lat.toFixed(6)), lng: Number(e.lngLat.lng.toFixed(6)) }));
    mapRef.current = map;
    return () => {
      markerRef.current?.remove();
      markerRef.current = null;
      map.remove();
      mapRef.current = null;
    };
    // The map is created once; later pins are handled below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    if (!pin) {
      markerRef.current?.remove();
      markerRef.current = null;
      return;
    }
    if (!markerRef.current) {
      const marker = new maplibregl.Marker({ draggable: true, color: "#171717" }).setLngLat([pin.lng, pin.lat]).addTo(map);
      marker.on("dragend", () => {
        const p = marker.getLngLat();
        setPin({ lat: Number(p.lat.toFixed(6)), lng: Number(p.lng.toFixed(6)) });
      });
      markerRef.current = marker;
    } else {
      markerRef.current.setLngLat([pin.lng, pin.lat]);
    }
  }, [pin]);

  async function find() {
    const text = addressFieldIds
      .map((id) => (document.getElementById(id) as HTMLInputElement | null)?.value.trim() ?? "")
      .filter(Boolean)
      .join(", ");
    if (!text) {
      setMessage("Type the address first.");
      return;
    }
    setFinding(true);
    setMessage(null);
    const found = await forwardGeocodeCityState(text);
    setFinding(false);
    if (!found) {
      setMessage("Couldn't find that address. Move the map by hand.");
      return;
    }
    mapRef.current?.flyTo({ center: [found.lng, found.lat], zoom: 18 });
    setMessage("Now click the exact spot to place the pin.");
  }

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap items-center gap-2 text-[13px]">
        <button type="button" onClick={find} disabled={finding} className="min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-3 font-medium hover:bg-neutral-50 disabled:opacity-50">
          {finding ? "Finding…" : "Find the address on the map"}
        </button>
        <span className="text-neutral-600">
          {pin ? `Pin at ${pin.lat.toFixed(5)}, ${pin.lng.toFixed(5)}. Drag it or click elsewhere to move it.` : "Click the map to place the pin."}
        </span>
      </div>
      {message && <p role="status" className="text-[13px] text-orange-900">{message}</p>}
      <div ref={containerRef} className="h-80 w-full overflow-hidden rounded-xl border border-neutral-200" />
      <input type="hidden" name="lat" value={pin?.lat ?? ""} />
      <input type="hidden" name="lng" value={pin?.lng ?? ""} />
    </div>
  );
}
