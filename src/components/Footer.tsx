"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useSignedIn } from "@/lib/useSignedIn";

type Item = { label: string; href?: string };

// Pages that don't exist yet are listed without a link, under a "Soon" tag.
const COLUMNS: { title: string; soon?: boolean; items: Item[] }[] = [
  {
    title: "Explore",
    items: [
      { label: "Search", href: "/" },
      { label: "Lists", href: "/lists" },
      { label: "Request a place", href: "/request" },
    ],
  },
  {
    title: "About",
    soon: true,
    items: [{ label: "How it works" }, { label: "Why no ads or rankings" }, { label: "Where our data comes from" }, { label: "Contact" }],
  },
  {
    title: "For restaurants",
    soon: true,
    items: [{ label: "Fix your listing" }, { label: "Claim your listing" }, { label: "Why we don’t sell placement" }],
  },
  {
    title: "Legal",
    soon: true,
    items: [{ label: "Privacy" }, { label: "Terms" }, { label: "Accessibility" }],
  },
];

function SoonTag() {
  return <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-xs font-medium text-muted">Soon</span>;
}

// One footer for every page outside admin. On a phone, members have the tab bar
// and find these links under Account instead, so it shows there for visitors only.
export default function Footer() {
  const pathname = usePathname();
  const signedIn = useSignedIn();
  if (pathname.startsWith("/admin")) return null;

  return (
    // Until it's known whether someone is signed in, the phone gets no footer, so
    // members never see it flash up and disappear.
    <footer data-site-footer className={`w-full border-t border-line bg-white ${signedIn === false ? "" : "hidden md:block"}`}>
      <div className="mx-auto flex max-w-6xl flex-col gap-8 px-6 py-10">
        <div className="flex flex-wrap gap-x-12 gap-y-8">
          <div className="flex min-w-[200px] flex-1 flex-col gap-2">
            <span className="text-base font-medium text-zinc-950">So Much Sushi</span>
            <p className="max-w-xs text-sm text-muted">Every place to eat and drink. Nothing paid to the top.</p>
          </div>
          {COLUMNS.map((col) => (
            <div key={col.title} className="flex min-w-[150px] flex-col gap-2">
              <h2 className="flex items-center gap-2 text-sm font-medium text-zinc-950">
                {col.title}
                {col.soon && <SoonTag />}
              </h2>
              <ul className="flex flex-col gap-1.5 text-sm">
                {col.items.map((item) => (
                  <li key={item.label}>
                    {item.href ? (
                      <Link href={item.href} className="text-muted hover:text-zinc-950">
                        {item.label}
                      </Link>
                    ) : (
                      <span className="text-zinc-400">{item.label}</span>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <div className="flex flex-wrap justify-between gap-2 border-t border-line pt-5 text-xs text-muted">
          <span>© 2026 So Much Sushi</span>
          <span>
            Map data © MapTiler © OpenStreetMap contributors · Place data: Overture Maps Foundation, All the Places
          </span>
        </div>
      </div>
    </footer>
  );
}
