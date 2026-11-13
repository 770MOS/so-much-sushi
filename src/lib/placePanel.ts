// How the place panel opens on a phone (build step 4, decided 2026-11-10): from the map as a
// short card over it (swipe up for more), from a list at full height. The page that opens a
// place says which, just before it navigates; the panel reads it while it opens (its loading
// state and then the place itself), so the choice holds for a few seconds. In memory only.
export type SheetStart = "peek" | "full";

let next: { start: SheetStart; at: number } | null = null;

export function setSheetStart(start: SheetStart) {
  next = { start, at: Date.now() };
}

export function takeSheetStart(): SheetStart {
  return next && Date.now() - next.at < 8000 ? next.start : "full";
}

// The place a /venue/<id> address points at, or null.
export function placeIdFromPath(pathname: string | null): string | null {
  return pathname?.match(/^\/venue\/([0-9a-f-]{36})(?:\/|$)/i)?.[1] ?? null;
}
