import maplibregl from "maplibre-gl";
import type { ControlPosition, IControl } from "maplibre-gl";
import {
  getUserLocation,
  resumeUserLocation,
  showUserLocation,
  subscribeUserLocation,
  type UserLocationState,
} from "@/lib/userLocation";

// The blue dot: where the person is, on any of the maps (2026-11-20).
//   * a blue dot with a white edge at their position, and around it a pale circle as wide as the
//     position is uncertain (hidden once it is smaller than the dot);
//   * a locate button under the zoom buttons. Pressing it turns the dot on (the browser asks for
//     permission the first time) and moves the map there; it is blue while the dot is on;
//   * the dot is also on, with no press, whenever the person has already allowed it (see
//     src/lib/userLocation.ts), and follows them as they move.
// Built with raw DOM, like the pins' popups: these sit inside MapLibre's own elements. The dot
// and circle let clicks through, so a pin under them can still be opened.

// The usual "you are here" blue: brighter than Want to try's flag blue, and a plain small dot
// where every mark of ours is a larger circle with an icon in it.
export const USER_DOT_COLOR = "#1a73e8";
const DOT_SIZE = 16;
// How close the button's move goes: about a neighborhood.
const LOCATE_ZOOM = 15;
const NOTE_MS = 7000;

// Same arrow as "Use my location" in the search form (Tabler Icons: location, MIT licensed).
const LOCATE_ICON_PATH = "M21 3l-6.5 18a.55 .55 0 0 1 -1 0l-3.5 -7l-7 -3.5a.55 .55 0 0 1 0 -1l18 -6.5";

const NOTES: Partial<Record<UserLocationState["status"], string>> = {
  denied: "Location is turned off for this site. You can allow it in your browser's settings.",
  unavailable: "We couldn't find your location. Try again in a moment.",
};

// Meters across one screen pixel at this latitude and zoom (MapLibre's 512px tiles).
export function metersPerPixel(lat: number, zoom: number): number {
  return (40075016.686 * Math.cos((lat * Math.PI) / 180)) / (512 * 2 ** zoom);
}

type Options = {
  // Which corner the button goes in: the one the zoom buttons are in.
  corner: ControlPosition;
  // Called just before the button moves the map to the person, e.g. to count it as their move.
  beforeMove?: () => void;
};

// Adds the dot and its button to a map. Returns the function that takes them off again.
export function addUserLocation(map: maplibregl.Map, { corner, beforeMove }: Options): () => void {
  let removed = false;
  // True from a press of the button until its answer: only then is a failure worth a note.
  let asked = false;
  let noteTimer: ReturnType<typeof setTimeout> | null = null;

  // ------------------------------------------------------------ the dot
  const circle = document.createElement("div");
  circle.style.cssText = `border-radius:9999px;background:${USER_DOT_COLOR}24;border:1px solid ${USER_DOT_COLOR}55;pointer-events:none;box-sizing:border-box;`;
  const dot = document.createElement("div");
  dot.dataset.testid = "user-location-dot";
  dot.style.cssText = `width:${DOT_SIZE}px;height:${DOT_SIZE}px;border-radius:9999px;background:${USER_DOT_COLOR};border:2.5px solid #ffffff;box-shadow:0 0 0 1px rgba(0,0,0,0.08),0 1px 4px rgba(0,0,0,0.35);pointer-events:none;box-sizing:border-box;`;
  const circleMarker = new maplibregl.Marker({ element: circle });
  const dotMarker = new maplibregl.Marker({ element: dot });
  let shown = false;

  function sizeCircle() {
    const position = getUserLocation().position;
    if (!position) return;
    const across = (2 * position.accuracy) / metersPerPixel(position.lat, map.getZoom());
    // Smaller than the dot's own edge says nothing; leave it out.
    const useful = Number.isFinite(across) && across >= DOT_SIZE + 12;
    circle.style.display = useful ? "" : "none";
    if (useful) {
      circle.style.width = `${across}px`;
      circle.style.height = `${across}px`;
    }
  }

  // ------------------------------------------------------------ the button
  const container = document.createElement("div");
  container.className = "maplibregl-ctrl";
  container.style.position = "relative";
  const group = document.createElement("div");
  group.className = "maplibregl-ctrl-group";
  const button = document.createElement("button");
  button.type = "button";
  button.dataset.testid = "locate-button";
  button.style.cssText = "display:flex;align-items:center;justify-content:center;";
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("width", "17");
  svg.setAttribute("height", "17");
  svg.setAttribute("fill", "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", "2");
  svg.setAttribute("stroke-linecap", "round");
  svg.setAttribute("stroke-linejoin", "round");
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(NS, "path");
  path.setAttribute("d", LOCATE_ICON_PATH);
  svg.appendChild(path);
  button.appendChild(svg);
  group.appendChild(button);
  container.appendChild(group);

  // A short note beside the button when a press couldn't show the dot.
  const note = document.createElement("p");
  note.setAttribute("role", "status");
  note.style.cssText =
    "position:absolute;top:0;width:220px;margin:0;padding:8px 10px;border-radius:10px;background:#ffffff;color:#141414;font-size:13px;line-height:1.35;box-shadow:0 2px 8px rgba(0,0,0,0.18);display:none;";
  note.style[corner.endsWith("right") ? "right" : "left"] = "calc(100% + 8px)";
  container.appendChild(note);

  function showNote(text: string) {
    note.textContent = text;
    note.style.display = "";
    if (noteTimer) clearTimeout(noteTimer);
    noteTimer = setTimeout(() => {
      note.style.display = "none";
    }, NOTE_MS);
  }

  function paintButton(state: UserLocationState) {
    const on = state.status === "on";
    const label = state.status === "locating" ? "Finding your location…" : on ? "Go to my location" : "Show my location";
    button.setAttribute("aria-label", label);
    button.title = label;
    button.setAttribute("aria-pressed", on ? "true" : "false");
    button.style.color = on ? USER_DOT_COLOR : "#333333";
    path.setAttribute("fill", on ? "currentColor" : "none");
    svg.style.opacity = state.status === "locating" ? "0.45" : "1";
  }

  button.addEventListener("click", async () => {
    asked = true;
    const position = await showUserLocation();
    asked = false;
    if (removed || !position) return;
    beforeMove?.();
    map.easeTo({ center: [position.lng, position.lat], zoom: Math.max(map.getZoom(), Math.min(LOCATE_ZOOM, map.getMaxZoom())), duration: 600 });
  });

  const control: IControl = {
    onAdd: () => container,
    onRemove: () => container.remove(),
  };
  map.addControl(control, corner);

  // ------------------------------------------------------------ keeping up
  function render(state: UserLocationState) {
    if (removed) return;
    paintButton(state);
    if (state.position) {
      const at: [number, number] = [state.position.lng, state.position.lat];
      circleMarker.setLngLat(at);
      dotMarker.setLngLat(at);
      if (!shown) {
        // The circle first, so the dot is drawn over it.
        circleMarker.addTo(map);
        dotMarker.addTo(map);
        shown = true;
      }
      sizeCircle();
      note.style.display = "none";
    } else if (shown) {
      circleMarker.remove();
      dotMarker.remove();
      shown = false;
    }
    if (asked && (state.status === "denied" || state.status === "unavailable")) {
      asked = false;
      showNote(NOTES[state.status]!);
    }
  }

  map.on("zoom", sizeCircle);
  const unsubscribe = subscribeUserLocation(render);
  render(getUserLocation());
  void resumeUserLocation();

  return () => {
    removed = true;
    unsubscribe();
    map.off("zoom", sizeCircle);
    if (noteTimer) clearTimeout(noteTimer);
    circleMarker.remove();
    dotMarker.remove();
    try {
      map.removeControl(control);
    } catch {
      // The map may already be gone.
    }
  };
}
