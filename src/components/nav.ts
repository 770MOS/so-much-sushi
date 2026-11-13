// Which top-level section a path belongs to, for marking the header link and
// phone tab as current.
export type Section = "search" | "favorites" | "lists" | "friends" | "account" | null;

export function sectionForPath(pathname: string): Section {
  if (pathname === "/" || pathname.startsWith("/search") || pathname.startsWith("/venue")) return "search";
  if (pathname.startsWith("/favorites")) return "favorites";
  if (pathname.startsWith("/lists")) return "lists";
  if (pathname.startsWith("/friends") || pathname.startsWith("/u/") || pathname.startsWith("/invite")) return "friends";
  if (pathname.startsWith("/settings") || pathname.startsWith("/profile") || pathname.startsWith("/request")) return "account";
  return null;
}
