export const TYPE_OPTIONS = [
  { key: "all", label: "All" },
  { key: "restaurants", label: "Restaurants" },
  { key: "bars", label: "Bars" },
  { key: "coffee", label: "Coffee" },
  { key: "bakeries", label: "Bakeries" },
  { key: "breweries", label: "Breweries" },
] as const;

export type EntityType = (typeof TYPE_OPTIONS)[number]["key"];

// Bakeries/Breweries aren't root categories in the tree - they're specific
// descendants (restaurants.bakery, bars.brewery) - so their type button sets
// category_path straight to that path rather than a root. Bars deliberately
// stays broad ("bars", not "bars.bar"): the ltree `<@` match already pulls
// in Brewery as a descendant, same is-a inclusion used everywhere else in
// the tree, so a brewery can surface under both the Bars and Breweries
// buttons - that's expected, not a bug.
const FIXED_CATEGORY_PATH: Partial<Record<EntityType, string>> = {
  bars: "bars",
  coffee: "coffee",
  bakeries: "restaurants.bakery",
  breweries: "bars.brewery",
};

export function categoryPathForType(type: EntityType): string {
  if (type === "all") return "";
  if (type === "restaurants") return "restaurants";
  return FIXED_CATEGORY_PATH[type] ?? "";
}

// The 5 real (non-"all") types, in the order a map marker's category icon
// should be decided - most specific first. An entity tagged under
// restaurants.bakery is also, technically, under restaurants (ltree
// containment), so without this precedence a bakery would be
// indistinguishable from a plain restaurant; checking bakeries/breweries
// before their broader parents resolves that.
const MARKER_TYPE_PRECEDENCE: { type: Exclude<EntityType, "all">; prefix: string }[] = [
  { type: "breweries", prefix: "bars.brewery" },
  { type: "bakeries", prefix: "restaurants.bakery" },
  { type: "bars", prefix: "bars" },
  { type: "coffee", prefix: "coffee" },
  { type: "restaurants", prefix: "restaurants" },
];

function pathIsUnderPrefix(path: string, prefix: string): boolean {
  return path === prefix || path.startsWith(`${prefix}.`);
}

// category_paths are ltree paths (e.g. "restaurants.bakery"), not the
// human-readable category names search_entities/get_entity_detail also
// return - only paths carry the hierarchy needed to tell a Bakery/Brewery
// apart from a plain Restaurant/Bar. Returns null for an entity with no
// categories at all (shouldn't happen in practice - search_entities'
// inner joins already require at least one - but not asserted here).
export function topLevelTypeForCategoryPaths(
  paths: string[] | null | undefined
): Exclude<EntityType, "all"> | null {
  if (!paths || paths.length === 0) return null;
  for (const { type, prefix } of MARKER_TYPE_PRECEDENCE) {
    if (paths.some((path) => pathIsUnderPrefix(path, prefix))) return type;
  }
  return null;
}
