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
