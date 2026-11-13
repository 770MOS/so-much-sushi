// Which top-level section a path belongs to, for marking the header link and
// phone tab as current.
export type Section = "search" | "discover" | "favorites" | "lists" | "friends" | "account" | null;

export function sectionForPath(pathname: string): Section {
  if (pathname === "/" || pathname.startsWith("/search") || pathname.startsWith("/venue")) return "search";
  if (pathname.startsWith("/discover")) return "discover";
  if (pathname.startsWith("/favorites")) return "favorites";
  if (pathname.startsWith("/lists")) return "lists";
  if (pathname.startsWith("/friends") || pathname.startsWith("/recommended") || pathname.startsWith("/u/")) return "friends";
  if (pathname.startsWith("/profile") || pathname.startsWith("/request")) return "account";
  return null;
}
