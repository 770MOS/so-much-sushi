"use client";

// A map to place a pin by clicking. The pin's position goes into hidden "lat"/"lng"
// inputs. "Find on map" only moves the map to a typed address; the pin is placed by
// hand, so the position is our own observation. "Use my location" (for someone standing
// at the place) drops the pin where their device says they are, to be dragged if needed.
// Load it through PinField, which holds the pin and its hidden inputs, so a pin that
// was already set is sent even if the form is submitted before the map has loaded.
import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { getMapStyleUrl, DEFAULT_MAP_CENTER, DEFAULT_MAP_ZOOM } from "@/lib/mapConfig";
import { forwardGeocodeCityState } from "@/lib/forwardGeocode";
import { getLastSearchCoords } from "@/lib/lastSearchCoords";

export type Pin = { lat: number; lng: number } | null;

const round = (n: number) => Number(n.toFixed(6));

export default function MapPicker({
  pin,
  onPin,
  addressFieldIds,
  locate = false,
  startAtLastSearch = false,
}: {
  pin: Pin;
  onPin: (pin: Pin) => void;
  addressFieldIds: string[];
  // Show "Use my location".
  locate?: boolean;
  // With no pin yet, start where the person last searched (this browser session).
  startAtLastSearch?: boolean;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const markerRef = useRef<maplibregl.Marker | null>(null);
  // The map's handlers are set up once; they call the latest onPin through this.
  const onPinRef = useRef(onPin);
  useEffect(() => {
    onPinRef.current = onPin;
  }, [onPin]);
  const [finding, setFinding] = useState(false);
  const [locating, setLocating] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!containerRef.current) return;
    const last = !pin && startAtLastSearch ? getLastSearchCoords() : null;
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: getMapStyleUrl(),
      center: pin ? [pin.lng, pin.lat] : last ? [last.lng, last.lat] : DEFAULT_MAP_CENTER,
      zoom: pin ? 17 : last ? 14 : DEFAULT_MAP_ZOOM,
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-left");
    map.getCanvas().style.cursor = "crosshair";
    map.on("click", (e) => onPinRef.current({ lat: round(e.lngLat.lat), lng: round(e.lngLat.lng) }));
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
        onPinRef.current({ lat: round(p.lat), lng: round(p.lng) });
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

  function placeAtMyLocation() {
    if (!("geolocation" in navigator)) {
      setMessage("This browser can't share your location. Find the address or move the map by hand.");
      return;
    }
    setLocating(true);
    setMessage(null);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLocating(false);
        const here = { lat: round(position.coords.latitude), lng: round(position.coords.longitude) };
        onPin(here);
        mapRef.current?.flyTo({ center: [here.lng, here.lat], zoom: 18 });
        setMessage("Pin placed where you are. Drag it onto the place if it's a little off.");
      },
      (err) => {
        setLocating(false);
        setMessage(
          err.code === err.PERMISSION_DENIED
            ? "Location access was denied. Find the address or move the map by hand."
            : "Couldn't get your location. Find the address or move the map by hand.",
        );
      },
      { enableHighAccuracy: true, timeout: 15000 },
    );
  }

  const button = "min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-3 font-medium hover:bg-neutral-50 disabled:opacity-50";

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap items-center gap-2 text-[13px]">
        {locate && (
          <button type="button" onClick={placeAtMyLocation} disabled={locating} className={button}>
            {locating ? "Locating…" : "Use my location"}
          </button>
        )}
        <button type="button" onClick={find} disabled={finding} className={button}>
          {finding ? "Finding…" : "Find the address on the map"}
        </button>
        <span className="text-neutral-600">
          {pin ? `Pin at ${pin.lat.toFixed(5)}, ${pin.lng.toFixed(5)}. Drag it or click elsewhere to move it.` : "Click the map to place the pin."}
        </span>
      </div>
      {message && <p role="status" className="text-[13px] text-orange-900">{message}</p>}
      <div ref={containerRef} className="h-80 w-full overflow-hidden rounded-xl border border-neutral-200" />
    </div>
  );
}
