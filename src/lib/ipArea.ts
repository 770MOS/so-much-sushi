// The visitor's rough area from their internet connection (src/app/api/ip-area/route.ts):
// a city-level point and "City, ST". Asked for once per tab and kept in memory only.

export type IpArea = { lat: number; lng: number; label: string };

let pending: Promise<IpArea | null> | null = null;

export function fetchIpArea(): Promise<IpArea | null> {
  if (!pending) {
    pending = fetch("/api/ip-area", { cache: "no-store" })
      .then((res) => (res.ok ? res.json() : null))
      .then((body) => {
        const a = body?.area;
        return a && Number.isFinite(a.lat) && Number.isFinite(a.lng) ? { lat: a.lat, lng: a.lng, label: String(a.label ?? "") } : null;
      })
      .catch(() => null);
  }
  return pending;
}
