export type SearchResult = {
  id: string;
  name: string;
  address: string;
  miles: number;
  lat: number;
  lng: number;
  is_starred: boolean;
  is_hidden: boolean;
  recommended_by: (string | null)[] | null;
  recommended_count: number;
  status: string;
  categories: string[] | null;
};

export type SortMode = "nearest" | "az";
export type ViewMode = "list" | "map";
