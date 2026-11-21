// Where the person is right now, for the blue dot on the maps.
//
// The position is held in memory only, for as long as a map is on screen: it is never saved and
// never sent anywhere (a user-control principle, like location search). The one thing kept, for
// this browser session only, is that the dot is on, so it comes back on the next page without
// another tap.
//
// The dot turns on when the person asks for it (the map's locate button, or any "Use my
// location"), or by itself when they have already allowed it: the browser says this site has
// their permission, or the dot was on earlier in this session. A map opening never asks someone
// who hasn't been asked before.

export type UserPosition = { lat: number; lng: number; accuracy: number };

// off: not asked for. locating: asked, no fix yet. on: showing. denied: the browser refused.
// unavailable: allowed, but no position could be found (or the browser can't give one).
export type UserLocationStatus = "off" | "locating" | "on" | "denied" | "unavailable";

export type UserLocationState = { status: UserLocationStatus; position: UserPosition | null };

type Listener = (state: UserLocationState) => void;

const SESSION_KEY = "sms:showMyLocation";

let state: UserLocationState = { status: "off", position: null };
let wanted = false;
let watchId: number | null = null;
const listeners = new Set<Listener>();
let waiting: ((position: UserPosition | null) => void)[] = [];
let listeningForVisibility = false;

function supported(): boolean {
  return typeof navigator !== "undefined" && "geolocation" in navigator;
}

function set(next: UserLocationState) {
  state = next;
  for (const listener of [...listeners]) listener(state);
}

function settle(position: UserPosition | null) {
  const resolvers = waiting;
  waiting = [];
  for (const resolve of resolvers) resolve(position);
}

function remember(on: boolean) {
  try {
    if (on) sessionStorage.setItem(SESSION_KEY, "1");
    else sessionStorage.removeItem(SESSION_KEY);
  } catch {
    // Storage can be off (private windows): the dot just needs a tap on the next page.
  }
}

function remembered(): boolean {
  try {
    return sessionStorage.getItem(SESSION_KEY) === "1";
  } catch {
    return false;
  }
}

function stopWatch() {
  if (watchId !== null) navigator.geolocation.clearWatch(watchId);
  watchId = null;
}

function startWatch() {
  if (watchId !== null || !wanted || !supported()) return;
  // Only while a map is showing and the page is in front: no reason to follow someone otherwise.
  if (listeners.size === 0 || document.visibilityState === "hidden") return;
  watchId = navigator.geolocation.watchPosition(
    (found) => {
      const position = { lat: found.coords.latitude, lng: found.coords.longitude, accuracy: found.coords.accuracy };
      remember(true);
      set({ status: "on", position });
      settle(position);
    },
    (error) => {
      if (error.code === error.PERMISSION_DENIED) {
        wanted = false;
        stopWatch();
        remember(false);
        set({ status: "denied", position: null });
      } else if (!state.position) {
        // No fix (yet). The watch keeps trying; an earlier position stays where it was.
        set({ status: "unavailable", position: null });
      }
      settle(state.position);
    },
    { enableHighAccuracy: true, maximumAge: 10_000, timeout: 20_000 }
  );
}

function onVisibility() {
  if (document.visibilityState === "hidden") stopWatch();
  else startWatch();
}

export function getUserLocation(): UserLocationState {
  return state;
}

// A map (or anything else that shows the position) listens while it is on screen.
export function subscribeUserLocation(listener: Listener): () => void {
  listeners.add(listener);
  if (!listeningForVisibility && typeof document !== "undefined") {
    listeningForVisibility = true;
    document.addEventListener("visibilitychange", onVisibility);
  }
  startWatch();
  return () => {
    listeners.delete(listener);
    if (listeners.size === 0) stopWatch();
  };
}

// The person asked to see where they are. The browser may ask for permission. Resolves with the
// first position found, or null if there is none (refused, or not found).
export function showUserLocation(): Promise<UserPosition | null> {
  if (!supported()) {
    set({ status: "unavailable", position: null });
    return Promise.resolve(null);
  }
  wanted = true;
  if (state.position && watchId !== null) return Promise.resolve(state.position);
  if (!state.position) {
    // A fresh try (a watch that already failed may stay quiet).
    stopWatch();
    set({ status: "locating", position: null });
  }
  return new Promise((resolve) => {
    waiting.push(resolve);
    startWatch();
    // Nothing is watching (no map on screen, or the page is hidden): don't leave it hanging.
    if (watchId === null) settle(state.position);
  });
}

// A position the person just gave some other way ("Use my location"): they have allowed it, so
// the maps show it and keep it up to date.
export function noteUserLocation(position: UserPosition) {
  wanted = true;
  remember(true);
  set({ status: "on", position });
  startWatch();
}

// Called when a map opens: turn the dot on by itself if the person has already allowed it, i.e.
// the browser reports this site as allowed, or the dot was on earlier in this session.
export async function resumeUserLocation(): Promise<void> {
  if (wanted || !supported()) return;
  let permission: PermissionState | null = null;
  try {
    permission = (await navigator.permissions.query({ name: "geolocation" })).state;
  } catch {
    // Older browsers can't say; go by this session.
  }
  if (wanted || permission === "denied") return;
  if (permission === "granted" || remembered()) {
    wanted = true;
    startWatch();
  }
}
