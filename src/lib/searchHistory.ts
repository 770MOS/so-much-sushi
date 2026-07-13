const KEY = "sms:searchHistory";
const MAX_ENTRIES = 5;

// localStorage, not sessionStorage - this should persist across visits,
// signed in or not, unlike lastSearchCoords.ts's session-only cache.
export function getSearchHistory(): string[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((v): v is string => typeof v === "string").slice(0, MAX_ENTRIES);
  } catch {
    return [];
  }
}

export function addSearchHistory(entry: string) {
  if (typeof window === "undefined") return;
  const trimmed = entry.trim();
  if (!trimmed) return;
  try {
    const existing = getSearchHistory().filter((e) => e.toLowerCase() !== trimmed.toLowerCase());
    const next = [trimmed, ...existing].slice(0, MAX_ENTRIES);
    localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    // ignore - e.g. private browsing storage restrictions
  }
}
