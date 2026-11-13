// The results page keeps everything about a search in its address, so a search can be
// shared, reloaded or gone back to:
//   /?q=pizza&kind=restaurants.italian&where=Clarendon%2C+Arlington%2C+VA&lat=38.887&lng=-77.095
//     &r=10&view=split&sort=az&only=favorites,friends&hidden=1
// Every part is optional. Nothing about the search is stored anywhere else.

export type View = "list" | "split" | "map";
export type Sort = "nearest" | "az";
export type Only = "favorites" | "friends" | "want";

export type ResultsQuery = {
  q: string; // part of a name
  kind: string | null; // a category path: a type ("coffee") or a finer kind ("restaurants.italian")
  where: string; // the place typed or picked in the Where box, as shown
  lat: number | null;
  lng: number | null;
  r: number; // miles around the point (until the map area becomes the search area)
  view: View;
  sort: Sort;
  only: Only[];
  hidden: boolean; // show places the person hid
};

export const DEFAULT_RADIUS = 10;
export const RADIUS_OPTIONS = [1, 3, 5, 10, 25];
const ONLY_ORDER: Only[] = ["favorites", "friends", "want"];

type Params = { get(name: string): string | null };

function num(v: string | null): number | null {
  if (v === null || v.trim() === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

export function parseResultsQuery(p: Params): ResultsQuery {
  const lat = num(p.get("lat"));
  const lng = num(p.get("lng"));
  const r = num(p.get("r"));
  const view = p.get("view");
  const only = (p.get("only") ?? "")
    .split(",")
    .filter((o): o is Only => (ONLY_ORDER as string[]).includes(o));
  const kind = p.get("kind");
  return {
    q: p.get("q") ?? "",
    kind: kind && /^[a-z_]+(\.[a-z_]+)*$/.test(kind) ? kind : null,
    where: p.get("where") ?? "",
    lat: lat !== null && Math.abs(lat) <= 90 ? lat : null,
    lng: lng !== null && Math.abs(lng) <= 180 ? lng : null,
    r: r !== null && r > 0 && r <= 50 ? r : DEFAULT_RADIUS,
    view: view === "list" || view === "map" ? view : "split",
    sort: p.get("sort") === "az" ? "az" : "nearest",
    only: ONLY_ORDER.filter((o) => only.includes(o)),
    hidden: p.get("hidden") === "1",
  };
}

// The address for a query, leaving out anything at its default.
export function resultsHref(query: ResultsQuery): string {
  const p = new URLSearchParams();
  if (query.q.trim()) p.set("q", query.q.trim());
  if (query.kind) p.set("kind", query.kind);
  if (query.where.trim()) p.set("where", query.where.trim());
  if (query.lat !== null && query.lng !== null) {
    p.set("lat", query.lat.toFixed(5));
    p.set("lng", query.lng.toFixed(5));
  }
  if (query.r !== DEFAULT_RADIUS) p.set("r", String(query.r));
  if (query.view !== "split") p.set("view", query.view);
  if (query.sort !== "nearest") p.set("sort", query.sort);
  if (query.only.length) p.set("only", query.only.join(","));
  if (query.hidden) p.set("hidden", "1");
  const s = p.toString();
  return s ? `/?${s}` : "/";
}

export function emptyQuery(): ResultsQuery {
  return { q: "", kind: null, where: "", lat: null, lng: null, r: DEFAULT_RADIUS, view: "split", sort: "nearest", only: [], hidden: false };
}
