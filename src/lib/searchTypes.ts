// A friend who starred this place - handle is the /u/[handle] link target,
// null if they never set one (renders as plain text instead of a link).
export type Recommender = { name: string; handle: string | null };

export type SearchResult = {
  id: string;
  name: string;
  address: string;
  miles: number;
  lat: number;
  lng: number;
  is_starred: boolean;
  is_hidden: boolean;
  // On the person's ready-made Want to try list (search_places only).
  is_want?: boolean;
  recommended_by: Recommender[] | null;
  recommended_count: number;
  status: string;
  categories: string[] | null;
  category_paths: string[] | null;
  // How many places matched in all; search returns at most the nearest 1,000.
  // Missing from databases that predate 20261108000000_nearest_first_search.
  total_count?: number;
};

export type SortMode = "nearest" | "az";
export type ViewMode = "list" | "map";

// The counts on the results page's filter buttons (public.search_facets).
export type Facets = {
  types: Partial<Record<"all" | "restaurants" | "drinks" | "coffee" | "markets", number>>;
  cuisines: { path: string; name: string; n: number }[];
  favorites: number;
  friends: number;
  want: number;
  hidden: number;
};
