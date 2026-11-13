"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import AccountMenu from "@/components/AccountMenu";
import { sectionForPath, type Section } from "@/components/nav";
import {
  DiscoverNavIcon,
  FavoritesNavIcon,
  FriendsNavIcon,
  ListsNavIcon,
  LogoMark,
  SearchNavIcon,
} from "@/components/icons";

type Profile = {
  display_name: string | null;
  first_name: string | null;
  handle: string | null;
  avatar_url: string | null;
};

type NavLink = { href: string; label: string; section: Section; Icon: () => React.ReactElement; membersOnly: boolean };

// Search and Discover become one results page with the search boxes in the
// header in the next step; until then both stay one click away.
const NAV: NavLink[] = [
  { href: "/", label: "Search", section: "search", Icon: SearchNavIcon, membersOnly: false },
  { href: "/discover", label: "Discover", section: "discover", Icon: DiscoverNavIcon, membersOnly: false },
  { href: "/favorites", label: "Favorites", section: "favorites", Icon: FavoritesNavIcon, membersOnly: true },
  { href: "/lists", label: "Lists", section: "lists", Icon: ListsNavIcon, membersOnly: true },
  { href: "/friends", label: "Friends", section: "friends", Icon: FriendsNavIcon, membersOnly: true },
];

export default function Header() {
  const pathname = usePathname();
  const supabase = useMemo(() => createClient(), []);
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [profile, setProfile] = useState<Profile | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user ?? null));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    supabase
      .from("profiles")
      .select("display_name, first_name, handle, avatar_url")
      .eq("id", user.id)
      .single()
      .then(({ data }) => {
        if (!cancelled) setProfile(data);
      });
    return () => {
      cancelled = true;
    };
  }, [user, supabase]);

  // The admin section has its own top bar.
  if (pathname.startsWith("/admin")) return null;

  const current = sectionForPath(pathname);
  const links = NAV.filter((l) => !l.membersOnly || user);

  return (
    <header className="w-full border-b border-line bg-white">
      <div className="flex min-h-16 items-center gap-x-6 gap-y-2 px-4 py-2 md:px-6">
        <Link href="/" className="flex shrink-0 items-center gap-2.5 text-zinc-950">
          <LogoMark />
          <span className="whitespace-nowrap text-lg font-medium tracking-tight">So Much Sushi</span>
        </Link>

        {/* On a phone, members get the tab bar at the bottom instead. */}
        <nav aria-label="Main" className="ml-auto hidden items-center gap-0.5 md:flex">
          {links.map(({ href, label, section, Icon }) => {
            const active = current === section;
            return (
              <Link
                key={href}
                href={href}
                aria-current={active ? "page" : undefined}
                className={`inline-flex h-11 items-center gap-2 px-3 text-[15px] font-medium text-zinc-950 transition-colors hover:text-zinc-600 ${
                  active ? "shadow-[inset_0_-2px_0_#141414]" : ""
                }`}
              >
                <Icon />
                {label}
              </Link>
            );
          })}
        </nav>

        <div className="ml-auto flex shrink-0 items-center gap-1 md:ml-2">
          {user === undefined ? null : user ? (
            <div className="hidden md:block">
              <AccountMenu
                supabase={supabase}
                email={user.email ?? ""}
                firstName={profile?.first_name ?? null}
                displayName={profile?.display_name ?? null}
                handle={profile?.handle ?? null}
                avatarUrl={profile?.avatar_url ?? null}
              />
            </div>
          ) : (
            <>
              <Link
                href="/sign-in"
                className="inline-flex h-11 items-center px-3 text-[15px] font-medium text-zinc-950 hover:text-zinc-600"
              >
                Sign in
              </Link>
              <Link
                href="/sign-up"
                className="inline-flex h-11 items-center rounded-[10px] bg-primary px-4 text-[15px] font-medium text-white hover:bg-primary-hover"
              >
                Join free
              </Link>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
