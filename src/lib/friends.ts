import type { ListPlace, Visibility } from "@/lib/lists";

// Friends, a person's page and invites (build step 6). Types for public.friends_overview,
// public.find_people, public.person_page and public.invite_info.

// How the viewer is connected to someone.
export type Relation = "self" | "friends" | "sent" | "received" | "none";

export type Person = {
  id: string;
  name: string;
  handle: string | null;
  in_common: number;
  since: string;
};

export type Friend = Person & { favorites: number; shared_lists: number };

export type FriendsOverview = { incoming: Person[]; outgoing: Person[]; friends: Friend[] };

export type FoundPerson = { id: string; name: string; handle: string | null; relation: Relation; in_common: number };

export type PersonList = {
  id: string;
  name: string;
  visibility: Visibility;
  is_default: boolean;
  place_count: number;
  towns: string[];
};

export type PersonPageData = {
  id: string;
  name: string;
  handle: string;
  relation: Relation;
  friends_since: string | null;
  favorites_count: number;
  favorites: ListPlace[];
  lists: PersonList[];
};

export type InviteInfo = { name: string; handle: string | null; relation: Relation };

// "March 2026".
export function monthYear(iso: string | null): string {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString("en-US", { month: "long", year: "numeric" });
}

export function plural(n: number, one: string, many: string) {
  return `${n.toLocaleString("en-US")} ${n === 1 ? one : many}`;
}

// A path inside the site to go to after signing in (?next=), or null. Only plain paths on this
// site: "/invite/abc", never "//elsewhere.com" or a full address.
export function safeNext(value: string | null | undefined): string | null {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.startsWith("/\\")) return null;
  return value;
}
