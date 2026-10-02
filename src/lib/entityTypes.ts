// The four main categories. Every entity has exactly one (entities.main_category_id),
// and each key is also the root path of that category's subtree.
export const TYPE_OPTIONS = [
  { key: "all", label: "All" },
  { key: "restaurants", label: "Restaurants" },
  { key: "drinks", label: "Drinks" },
  { key: "coffee", label: "Coffee" },
  { key: "markets", label: "Bakeries and Markets" },
] as const;

export type EntityType = (typeof TYPE_OPTIONS)[number]["key"];

export function categoryPathForType(type: EntityType): string {
  return type === "all" ? "" : type;
}

const MAIN_TYPES: Exclude<EntityType, "all">[] = ["restaurants", "drinks", "coffee", "markets"];

// search_entities/get_entity_detail return category_paths with the main category first,
// so the first path decides the marker icon. Falls back to the root of any path for
// safety. Returns null for an entity with no recognisable category.
export function topLevelTypeForCategoryPaths(
  paths: string[] | null | undefined
): Exclude<EntityType, "all"> | null {
  if (!paths) return null;
  for (const path of paths) {
    const root = path.split(".")[0] as Exclude<EntityType, "all">;
    if (MAIN_TYPES.includes(root)) return root;
  }
  return null;
}
