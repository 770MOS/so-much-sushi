"use client";

// A map to place a pin by clicking. The pin's position goes into hidden "lat"/"lng"
// inputs. "Find on map" only moves the map to a typed address; the pin is placed by
// hand, so the position is our own observation. "Use my location" (for someone standing
// at the place) drops the pin where their device says they are, to be dragged if needed.
// Load it through PinField, which holds the pin and its hidden inputs, so a pin that
// was already set is sent even if the form is submitted before the map has loaded.
// Fixing a place's pin (PinFixForm) uses it directly, with the current spot shown faded.
import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { getMapStyleUrl, DEFAULT_MAP_CENTER, DEFAULT_MAP_ZOOM, MAX_PIN_ZOOM } from "@/lib/mapConfig";
import { forwardGeocodeCityState } from "@/lib/forwardGeocode";
import { getLastSearchCoords } from "@/lib/lastSearchCoords";
import { GOOD_GPS_METERS, type PinMethod } from "@/lib/pins";

export type Pin = { lat: number; lng: number } | null;

// A fixed marker shown for comparison: the pin's current spot, or another person's suggestion.
export type MapMark = { lat: number; lng: number; label: string; tone: "current" | "other" };

function markElement(mark: MapMark): HTMLElement {
  const el = document.createElement("div");
  // The dot sits on the spot and the label to its right, so the movable pin (drawn above
  // the spot) never covers the label.
  el.style.display = "flex";
  el.style.alignItems = "center";
  el.style.gap = "4px";
  el.style.pointerEvents = "none";
  const label = document.createElement("span");
  label.textContent = mark.label;
  label.style.cssText =
    "padding:1px 6px;border-radius:9999px;font:500 11px/16px system-ui,sans-serif;white-space:nowrap;" +
    (mark.tone === "current" ? "background:#fff;color:#525252;border:1px solid #d4d4d4;" : "background:#fff7ed;color:#9a3412;border:1px solid #fdba74;");
  const dot = document.createElement("span");
  dot.style.cssText = `width:14px;height:14px;border-radius:9999px;border:2px solid #fff;box-shadow:0 1px 3px rgba(0,0,0,.35);background:${
    mark.tone === "current" ? "#a3a3a3" : "#ea580c"
  };`;
  el.append(dot, label);
  return el;
}

const round = (n: number) => Number(n.toFixed(6));

export default function MapPicker({
  pin,
  onPin,
  addressFieldIds = [],
  locate = false,
  startAtLastSearch = false,
  onPlaced,
  marks = [],
  locateLabel = "Use my location",
  heightClass = "h-80",
  buttonClass,
  hint,
}: {
  pin: Pin;
  onPin: (pin: Pin) => void;
  // Address boxes for "Find the address on the map" (left out when there are none).
  addressFieldIds?: string[];
  // Show "Use my location".
  locate?: boolean;
  // With no pin yet, start where the person last searched (this browser session).
  startAtLastSearch?: boolean;
  // How the pin was last placed: on the map, or the phone's location with its accuracy.
  onPlaced?: (method: PinMethod, accuracy: number | null) => void;
  // Fixed markers shown for comparison.
  marks?: MapMark[];
  locateLabel?: string;
  heightClass?: string;
  buttonClass?: string;
  // Replaces the line beside the buttons that gives the pin's position.
  hint?: string;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const markerRef = useRef<maplibregl.Marker | null>(null);
  // The map's handlers are set up once; they call the latest onPin through this.
  const onPinRef = useRef(onPin);
  const onPlacedRef = useRef(onPlaced);
  useEffect(() => {
    onPinRef.current = onPin;
    onPlacedRef.current = onPlaced;
  }, [onPin, onPlaced]);
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
      zoom: pin ? 18 : last ? 14 : DEFAULT_MAP_ZOOM,
      maxZoom: MAX_PIN_ZOOM,
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-left");
    map.getCanvas().style.cursor = "crosshair";
    map.on("click", (e) => {
      onPinRef.current({ lat: round(e.lngLat.lat), lng: round(e.lngLat.lng) });
      onPlacedRef.current?.("map", null);
    });
    const fixed = marks.map((m) =>
      new maplibregl.Marker({ element: markElement(m), anchor: "left", offset: [-7, 0] }).setLngLat([m.lng, m.lat]).addTo(map),
    );
    mapRef.current = map;
    return () => {
      fixed.forEach((m) => m.remove());
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
        onPlacedRef.current?.("map", null);
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
        const accuracy = Number.isFinite(position.coords.accuracy) ? Math.round(position.coords.accuracy * 10) / 10 : null;
        onPin(here);
        onPlaced?.("gps", accuracy);
        mapRef.current?.flyTo({ center: [here.lng, here.lat], zoom: 19 });
        setMessage(
          accuracy !== null && accuracy > GOOD_GPS_METERS
            ? `Your phone says this is only accurate to about ${Math.round(accuracy)} m. Drag the pin onto the place's front door.`
            : accuracy !== null
              ? `Pin placed where you are (within about ${Math.max(1, Math.round(accuracy))} m). Drag it onto the front door if it's a little off.`
              : "Pin placed where you are. Drag it onto the place if it's a little off.",
        );
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

  const button =
    buttonClass ?? "min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-3 font-medium hover:bg-neutral-50 disabled:opacity-50";

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap items-center gap-2 text-[13px]">
        {locate && (
          <button type="button" onClick={placeAtMyLocation} disabled={locating} className={button}>
            {locating ? "Locating…" : locateLabel}
          </button>
        )}
        {addressFieldIds.length > 0 && (
          <button type="button" onClick={find} disabled={finding} className={button}>
            {finding ? "Finding…" : "Find the address on the map"}
          </button>
        )}
        <span className="text-neutral-600">
          {hint ?? (pin ? `Pin at ${pin.lat.toFixed(5)}, ${pin.lng.toFixed(5)}. Drag it or click elsewhere to move it.` : "Click the map to place the pin.")}
        </span>
      </div>
      {message && <p role="status" className="text-[13px] text-orange-900">{message}</p>}
      <div ref={containerRef} className={`${heightClass} w-full overflow-hidden rounded-xl border border-neutral-200`} />
    </div>
  );
}
