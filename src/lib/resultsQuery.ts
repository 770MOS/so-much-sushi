// The results page keeps everything about a search in its address, so a search can be
// shared, reloaded or gone back to:
//   /?q=pizza&kind=restaurants.italian&where=Clarendon%2C+Arlington%2C+VA&lat=38.887&lng=-77.095
//     &b=-77.1301,38.8601,-77.0599,38.9139&view=split&sort=az&only=favorites,friends&hidden=1
// and the All filters panel's choices (advanced search, 2026-11-19; MoreFilters below):
//     &cu=restaurants.asian.thai,restaurants.asian.vietnamese&st=Wilson+Blvd&chain=independent
//     &web=1&tel=1&closed=1&list=<id>&close=1
// Every part is optional. Nothing about the search is stored anywhere else.
//
// b is the search area: the box on the map (west, south, east, north) whose places are shown
// (build step 3: the map area is the search area). lat/lng is the point the search started
// from, which distances are measured from and the nearest places put first by.

export type View = "list" | "split" | "map";
export type Sort = "nearest" | "az";
export type Only = "favorites" | "friends" | "want";
export type Box = { west: number; south: number; east: number; north: number };
export type Chain = "chain" | "independent";

// The All filters panel (public.area_options reads them as `more`). cuisines: several kinds at
// once, any of them (one kind alone stays in `kind`); street: matched on its start; chain:
// 10 or more open places with the name nationwide; closed: places that have closed too; list:
// one of the person's own lists; close: the typed name also finds close spellings.
export type MoreFilters = {
  cuisines: string[];
  street: string;
  chain: Chain | null;
  website: boolean;
  phone: boolean;
  closed: boolean;
  list: string | null;
  close: boolean;
};

export const NO_MORE: MoreFilters = {
  cuisines: [],
  street: "",
  chain: null,
  website: false,
  phone: false,
  closed: false,
  list: null,
  close: false,
};

export type ResultsQuery = {
  q: string; // part of a name
  kind: string | null; // a category path: a type ("coffee") or a finer kind ("restaurants.italian")
  where: string; // the place typed or picked in the Where box, as shown
  lat: number | null;
  lng: number | null;
  b: Box | null; // the search area
  view: View;
  sort: Sort;
  only: Only[];
  hidden: boolean; // show places the person hid
  more: MoreFilters;
};

// What the Where box says after "Search this area" moved the search away from the place typed.
export const MAP_AREA_LABEL = "Map area";

// The largest box the database will search (public.area_box): 1.2 degrees north to south
// (about 80 miles) and 2.5 degrees east to west.
const MAX_LAT_SPAN = 1.2;
const MAX_LNG_SPAN = 2.5;
const MILES_PER_DEGREE_LAT = 69.0;

const ONLY_ORDER: Only[] = ["favorites", "friends", "want"];

type Params = { get(name: string): string | null };

function num(v: string | null): number | null {
  if (v === null || v.trim() === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

const PATH_RE = /^[a-z_]+(\.[a-z_]+)*$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function parseMore(p: Params): MoreFilters {
  const cuisines = (p.get("cu") ?? "")
    .split(",")
    .filter((c) => PATH_RE.test(c))
    .slice(0, 20);
  const chain = p.get("chain");
  const list = p.get("list");
  return {
    cuisines: cuisines.length > 1 ? [...new Set(cuisines)] : [],
    street: (p.get("st") ?? "").trim().slice(0, 80),
    chain: chain === "chain" || chain === "independent" ? chain : null,
    website: p.get("web") === "1",
    phone: p.get("tel") === "1",
    closed: p.get("closed") === "1",
    list: list && UUID_RE.test(list) ? list : null,
    close: p.get("close") === "1",
  };
}

function parseBox(v: string | null): Box | null {
  if (!v) return null;
  const parts = v.split(",").map((s) => num(s));
  if (parts.length !== 4 || parts.some((n) => n === null)) return null;
  const [west, south, east, north] = parts as number[];
  const box = { west, south, east, north };
  const valid = west < east && south < north && west >= -180 && east <= 180 && south >= -90 && north <= 90;
  return valid && !boxTooLarge(box) ? box : null;
}

export function boxParam(box: Box): string {
  return [box.west, box.south, box.east, box.north].map((n) => n.toFixed(4)).join(",");
}

export function sameBox(a: Box | null, b: Box | null): boolean {
  if (!a || !b) return a === b;
  return boxParam(a) === boxParam(b);
}

export function boxTooLarge(box: Box): boolean {
  return box.north - box.south > MAX_LAT_SPAN || box.east - box.west > MAX_LNG_SPAN;
}

export function boxContains(box: Box, point: { lat: number; lng: number }): boolean {
  return point.lat >= box.south && point.lat <= box.north && point.lng >= box.west && point.lng <= box.east;
}

// A square about 2 x miles across, centred on the point.
export function boxAround(point: { lat: number; lng: number }, miles: number): Box {
  const dLat = miles / MILES_PER_DEGREE_LAT;
  const dLng = miles / (MILES_PER_DEGREE_LAT * Math.max(Math.cos((point.lat * Math.PI) / 180), 0.05));
  return {
    west: Math.max(point.lng - dLng, -180),
    south: Math.max(point.lat - dLat, -90),
    east: Math.min(point.lng + dLng, 180),
    north: Math.min(point.lat + dLat, 90),
  };
}

export function boxCenter(box: Box): { lat: number; lng: number } {
  return { lat: (box.south + box.north) / 2, lng: (box.west + box.east) / 2 };
}

export function parseResultsQuery(p: Params): ResultsQuery {
  const lat = num(p.get("lat"));
  const lng = num(p.get("lng"));
  const view = p.get("view");
  const only = (p.get("only") ?? "")
    .split(",")
    .filter((o): o is Only => (ONLY_ORDER as string[]).includes(o));
  const kind = p.get("kind");
  return {
    q: p.get("q") ?? "",
    kind: kind && PATH_RE.test(kind) ? kind : null,
    where: p.get("where") ?? "",
    lat: lat !== null && Math.abs(lat) <= 90 ? lat : null,
    lng: lng !== null && Math.abs(lng) <= 180 ? lng : null,
    b: parseBox(p.get("b")),
    view: view === "list" || view === "map" ? view : "split",
    sort: p.get("sort") === "az" ? "az" : "nearest",
    only: ONLY_ORDER.filter((o) => only.includes(o)),
    hidden: p.get("hidden") === "1",
    // One kind alone (with a dot: a cuisine) leaves no room for several.
    more: kind && kind.includes(".") ? { ...parseMore(p), cuisines: [] } : parseMore(p),
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
  if (query.b) p.set("b", boxParam(query.b));
  if (query.view !== "split") p.set("view", query.view);
  if (query.sort !== "nearest") p.set("sort", query.sort);
  if (query.only.length) p.set("only", query.only.join(","));
  if (query.hidden) p.set("hidden", "1");
  const m = query.more;
  if (m.cuisines.length > 1) p.set("cu", m.cuisines.join(","));
  if (m.street.trim()) p.set("st", m.street.trim());
  if (m.chain) p.set("chain", m.chain);
  if (m.website) p.set("web", "1");
  if (m.phone) p.set("tel", "1");
  if (m.closed) p.set("closed", "1");
  if (m.list) p.set("list", m.list);
  if (m.close) p.set("close", "1");
  const s = p.toString();
  return s ? `/?${s}` : "/";
}

export function emptyQuery(): ResultsQuery {
  return {
    q: "",
    kind: null,
    where: "",
    lat: null,
    lng: null,
    b: null,
    view: "split",
    sort: "nearest",
    only: [],
    hidden: false,
    more: NO_MORE,
  };
}

// The cuisines picked: several in more.cuisines, or the one in kind.
export function cuisinesOf(query: Pick<ResultsQuery, "kind" | "more">): string[] {
  if (query.more.cuisines.length > 1) return query.more.cuisines;
  return query.kind && query.kind.includes(".") ? [query.kind] : [];
}

// A query with these cuisines: none (back to the type), one (in kind, as before), or several
// (kind becomes their type, or none if they're of different types).
export function withCuisines(query: ResultsQuery, paths: string[], type: string | null): Partial<ResultsQuery> {
  const unique = [...new Set(paths)];
  if (unique.length === 0) return { kind: type, more: { ...query.more, cuisines: [] } };
  if (unique.length === 1) return { kind: unique[0], more: { ...query.more, cuisines: [] } };
  const roots = new Set(unique.map((p) => p.split(".")[0]));
  return { kind: roots.size === 1 ? [...roots][0] : null, more: { ...query.more, cuisines: unique } };
}

// The panel's filters as public.area_options takes them (only those that are on).
export function moreArg(more: MoreFilters, counts = false): Record<string, unknown> {
  const arg: Record<string, unknown> = {};
  if (more.cuisines.length > 1) arg.cuisines = more.cuisines;
  if (more.street.trim()) arg.street = more.street.trim();
  if (more.chain) arg.chain = more.chain;
  if (more.website) arg.website = true;
  if (more.phone) arg.phone = true;
  if (more.closed) arg.closed = true;
  if (more.list) arg.list = more.list;
  if (more.close) arg.close = true;
  if (counts) arg.counts = true;
  return arg;
}

// How many of the panel's own filters are on (cuisines show on the bar's Cuisine chip, so
// they don't count here). Close spellings count only with a name to spell.
export function moreCount(query: Pick<ResultsQuery, "q" | "more">): number {
  const m = query.more;
  return (
    (m.street.trim() ? 1 : 0) +
    (m.chain ? 1 : 0) +
    (m.website ? 1 : 0) +
    (m.phone ? 1 : 0) +
    (m.closed ? 1 : 0) +
    (m.list ? 1 : 0) +
    (m.close && query.q.trim() ? 1 : 0)
  );
}
