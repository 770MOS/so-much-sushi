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
  recommended_by: Recommender[] | null;
  recommended_count: number;
  status: string;
  categories: string[] | null;
  category_paths: string[] | null;
};

export type SortMode = "nearest" | "az";
export type ViewMode = "list" | "map";
