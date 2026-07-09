"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import type { ComponentType } from "react";
import {
  StarredNavIcon,
  ListsNavIcon,
  RecommendedNavIcon,
  ConnectionsNavIcon,
} from "@/components/icons";

type NavItem = {
  href: string;
  label: string;
  Icon: ComponentType;
};

const NAV_ITEMS: NavItem[] = [
  { href: "/starred", label: "Starred", Icon: StarredNavIcon },
  { href: "/profile?tab=lists", label: "Lists", Icon: ListsNavIcon },
  { href: "/recommended", label: "Recommended", Icon: RecommendedNavIcon },
  { href: "/profile?tab=connections", label: "Connections", Icon: ConnectionsNavIcon },
];

function desktopItemClass(active: boolean) {
  return `flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
    active
      ? "bg-primary text-white"
      : "text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-zinc-800 dark:hover:text-zinc-100"
  }`;
}

function mobileItemClass(active: boolean) {
  return `flex flex-1 flex-col items-center gap-0.5 py-2 text-xs font-medium transition-colors ${
    active
      ? "text-primary"
      : "text-zinc-500 dark:text-zinc-400"
  }`;
}

export default function Sidebar() {
  const pathname = usePathname();
  const searchParams = useSearchParams();

  function isActive(href: string) {
    const [path, query] = href.split("?");
    if (pathname !== path) return false;
    if (!query) return true;
    const params = new URLSearchParams(query);
    for (const [key, value] of params) {
      if (searchParams.get(key) !== value) return false;
    }
    return true;
  }

  return (
    <>
      <nav
        aria-label="Main"
        className="hidden w-48 shrink-0 flex-col gap-1 border-r border-zinc-200 bg-white px-3 py-6 dark:border-zinc-800 dark:bg-black md:flex"
      >
        {NAV_ITEMS.map(({ href, label, Icon }) => (
          <Link key={href} href={href} className={desktopItemClass(isActive(href))}>
            <Icon />
            <span>{label}</span>
          </Link>
        ))}
      </nav>

      <nav
        aria-label="Main"
        className="fixed inset-x-0 bottom-0 z-20 flex border-t border-zinc-200 bg-white md:hidden dark:border-zinc-800 dark:bg-black"
      >
        {NAV_ITEMS.map(({ href, label, Icon }) => (
          <Link key={href} href={href} className={mobileItemClass(isActive(href))}>
            <Icon />
            <span>{label}</span>
          </Link>
        ))}
      </nav>
    </>
  );
}
