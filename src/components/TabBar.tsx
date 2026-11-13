"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useSignedIn } from "@/lib/useSignedIn";
import { sectionForPath, type Section } from "@/components/nav";
import { HEART_PATH } from "@/components/icons";

// Tabler Icons outlines at tab-bar size, in the tab's text colour.
const TABS: { href: string; label: string; section: Section; d: string }[] = [
  { href: "/", label: "Search", section: "search", d: "M10 10m-7 0a7 7 0 1 0 14 0a7 7 0 1 0 -14 0M21 21l-6 -6" },
  { href: "/favorites", label: "Favs", section: "favorites", d: HEART_PATH },
  { href: "/lists", label: "Lists", section: "lists", d: "M9 6h11M9 12h11M9 18h11M5 6v.01M5 12v.01M5 18v.01" },
  {
    href: "/friends",
    label: "Friends",
    section: "friends",
    d: "M9 7m-4 0a4 4 0 1 0 8 0a4 4 0 1 0 -8 0M3 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2M16 3.13a4 4 0 0 1 0 7.75M21 21v-2a4 4 0 0 0 -3 -3.85",
  },
  {
    href: "/settings",
    label: "Account",
    section: "account",
    d: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0M9 10a3 3 0 1 0 6 0a3 3 0 1 0 -6 0M6.168 18.849a4 4 0 0 1 3.832 -2.849h4a4 4 0 0 1 3.834 2.855",
  },
];

// The phone's five tabs, for members only (visitors get Sign in and Join in the
// header). Hidden from the medium breakpoint up, where the header has the links.
export default function TabBar() {
  const pathname = usePathname();
  const signedIn = useSignedIn();
  if (!signedIn || pathname.startsWith("/admin")) return null;
  const current = sectionForPath(pathname);

  return (
    <>
      {/* Keeps the end of each page clear of the bar. */}
      <div aria-hidden="true" className="h-[74px] md:hidden" />
      <nav
        aria-label="Main"
        className="fixed inset-x-0 bottom-0 z-20 grid h-[74px] grid-cols-5 border-t border-line bg-white px-1 pb-3.5 pt-1.5 md:hidden"
      >
        {TABS.map(({ href, label, section, d }) => {
          const active = current === section;
          return (
            <Link
              key={href}
              href={href}
              aria-current={active ? "page" : undefined}
              className={`flex flex-col items-center justify-center gap-0.5 text-[11px] font-medium ${
                active ? "text-zinc-950" : "text-zinc-500"
              }`}
            >
              <svg viewBox="0 0 24 24" width={24} height={24} fill="none" stroke="currentColor" strokeWidth={active ? 2.2 : 1.9} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d={d} />
              </svg>
              {label}
            </Link>
          );
        })}
      </nav>
    </>
  );
}
