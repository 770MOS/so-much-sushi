"use client";

import { useMemo, useState, type ReactNode } from "react";
import { createClient } from "@/lib/supabase/client";
import { useUserId } from "@/lib/useSignedIn";
import { useResultsState } from "@/lib/resultsStore";
import { announceMark, useMarkChanges } from "@/lib/placeMarks";
import { formatPhone, phoneHref, websiteHost } from "@/lib/format";
import { addressLines, milesBetween, placeKinds, sourcesLine, type PlaceDetail } from "@/lib/placeDetail";
import { FavoriteIcon } from "@/components/icons";
import StatusBadge from "@/components/StatusBadge";
import ShareButton from "@/components/ShareButton";
import JoinNote from "@/components/results/JoinNote";
import { friendsLabel } from "@/components/results/ResultRow";
import ListButton from "@/components/place/ListButton";
import DirectionsMenu from "@/components/place/DirectionsMenu";

// The details of one place (mocked 2026-11-10), shared by the side panel, the phone sheet and
// the full place page so the three can't drift apart:
//   name; kind ("Italian · Restaurants") with the distance from the search, when there is one;
//   Favorite and Add to list (a lock and the join note for visitors); which friends have it as
//   a favorite and which of the person's lists it's on; address with Directions, phone,
//   website, hours; where the details come from; Suggest an edit and Report closed (soon);
//   claiming (soon).
type Layout = "panel" | "sheet" | "page";

const LOCK_PATH = "M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6zM11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0M8 11v-4a4 4 0 1 1 8 0v4";
const AVATAR_COLORS = [
  ["#e7f4ec", "#17603a"],
  ["#e8eefb", "#2c4a9a"],
  ["#fbeaf0", "#9c2e55"],
];

function Lock() {
  return (
    <svg viewBox="0 0 24 24" width={14} height={14} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={LOCK_PATH} />
    </svg>
  );
}

function Row({ icon, children, alignTop }: { icon: string; children: ReactNode; alignTop?: boolean }) {
  return (
    <li className={`flex gap-3.5 border-b border-[#f0f0f0] py-3.5 ${alignTop ? "items-start" : "items-center"}`}>
      <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="#5c5c5c" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className={`shrink-0 ${alignTop ? "mt-px" : ""}`}>
        <path d={icon} />
      </svg>
      {children}
    </li>
  );
}

const ICONS = {
  pin: "M9 11a3 3 0 1 0 6 0a3 3 0 0 0 -6 0M17.657 16.657l-4.243 4.243a2 2 0 0 1 -2.827 0l-4.244 -4.243a8 8 0 1 1 11.314 0z",
  phone: "M5 4h4l2 5l-2.5 1.5a11 11 0 0 0 5 5l1.5 -2.5l5 2v4a2 2 0 0 1 -2 2a16 16 0 0 1 -15 -15a2 2 0 0 1 2 -2",
  globe: "M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0M3.6 9h16.8M3.6 15h16.8M11.5 3a17 17 0 0 0 0 18M12.5 3a17 17 0 0 1 0 18",
  clock: "M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0M12 7v5l3 3",
  flag: "M5 5a5 5 0 0 1 7 0a5 5 0 0 0 7 0v9a5 5 0 0 1 -7 0a5 5 0 0 0 -7 0v-9zM5 21v-7",
};

export default function PlaceBody({ place, layout, headingId }: { place: PlaceDetail; layout: Layout; headingId?: string }) {
  const supabase = useMemo(() => createClient(), []);
  const userId = useUserId();
  const { origin } = useResultsState();
  const [starred, setStarred] = useState(place.is_starred);
  const [want, setWant] = useState(place.is_want);
  const [lists, setLists] = useState(place.lists);
  const [joinOpen, setJoinOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  // A heart or Want to try changed elsewhere on the page (a result row): follow it.
  useMarkChanges((change) => {
    if (change.id !== place.id) return;
    if (change.starred !== undefined) setStarred(change.starred);
    if (change.want !== undefined) setWant(change.want);
  });

  const { cuisine, type } = placeKinds(place);
  const lines = addressLines(place);
  const miles = layout !== "page" && origin ? milesBetween(origin, place) : null;
  const friends = friendsLabel(place.friends, place.friends_count);
  const signedIn = Boolean(userId);

  async function toggleFavorite() {
    if (!userId) {
      setJoinOpen(true);
      return;
    }
    if (busy) return;
    setBusy(true);
    const on = starred;
    const { error } = on
      ? await supabase.from("stars").delete().eq("user_id", userId).eq("entity_id", place.id)
      : await supabase.from("stars").insert({ user_id: userId, entity_id: place.id });
    setBusy(false);
    if (error) return;
    setStarred(!on);
    announceMark({ id: place.id, starred: !on, from: "panel" });
  }

  const Heading = layout === "page" ? "h1" : "h2";
  const kindParts = [
    cuisine ? <span key="c" className="font-medium text-link">{cuisine.name}</span> : null,
    type ? <span key="t">{type.label}</span> : null,
    miles !== null ? <span key="m">{miles < 10 ? miles.toFixed(1) : Math.round(miles)} mi</span> : null,
    layout === "page" && place.city ? <span key="p">{[place.city, place.state].filter(Boolean).join(", ")}</span> : null,
  ].filter(Boolean);

  return (
    <div className="flex flex-col gap-[18px]">
      <div className="flex flex-col gap-1.5">
        <Heading
          id={headingId}
          tabIndex={-1}
          className={`font-medium leading-tight tracking-[-0.4px] text-zinc-950 focus:outline-none ${layout === "page" ? "text-[32px]" : "text-[26px]"}`}
        >
          {place.name}
        </Heading>
        {kindParts.length > 0 && (
          <p className="text-[15px] text-muted">
            {kindParts.map((part, i) => (
              <span key={i}>
                {i > 0 && " · "}
                {part}
              </span>
            ))}
          </p>
        )}
        <StatusBadge status={place.status} />
      </div>

      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={toggleFavorite}
          aria-pressed={signedIn ? starred : undefined}
          disabled={userId === undefined}
          className={`inline-flex h-[42px] items-center gap-1.5 rounded-[10px] border px-3.5 text-sm font-medium ${
            starred ? "border-favorite bg-[#fcebef] text-favorite-ink" : "border-[#dddddd] bg-white text-zinc-950 hover:bg-zinc-50"
          }`}
        >
          <FavoriteIcon filled={starred} size={18} />
          {starred ? "Favorited" : "Favorite"}
          {userId === null && <Lock />}
        </button>
        {userId ? (
          <ListButton
            userId={userId}
            placeId={place.id}
            onChange={(w, l) => {
              setWant(w);
              setLists(l);
            }}
          />
        ) : (
          <button
            type="button"
            onClick={() => setJoinOpen(true)}
            disabled={userId === undefined}
            className="inline-flex h-[42px] items-center gap-1.5 rounded-[10px] border border-[#dddddd] bg-white px-3.5 text-sm font-medium text-zinc-950 hover:bg-zinc-50"
          >
            Add to list
            <Lock />
          </button>
        )}
        {layout === "sheet" && place.phone && (
          <a href={phoneHref(place.phone)} className="inline-flex h-[42px] items-center gap-1.5 rounded-[10px] border border-[#dddddd] bg-white px-3.5 text-sm font-medium text-zinc-950">
            <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d={ICONS.phone} />
            </svg>
            Call
          </a>
        )}
        {layout === "page" && <ShareButton path={`/venue/${place.id}`} title={place.name} />}
      </div>

      {(friends || want || lists.length > 0) && (
        <div className="flex flex-col gap-2">
          {friends && (
            <div className="flex items-center gap-2.5">
              <span aria-hidden="true" className="flex">
                {place.friends.slice(0, 3).map((f, i) => (
                  <span
                    key={i}
                    style={{ background: AVATAR_COLORS[i][0], color: AVATAR_COLORS[i][1] }}
                    className={`h-[30px] w-[30px] rounded-full border-2 border-white text-center text-[13px] font-medium leading-[26px] ${i > 0 ? "-ml-2" : ""}`}
                  >
                    {(f.name?.trim()[0] ?? "?").toUpperCase()}
                  </span>
                ))}
              </span>
              <p className="text-sm font-medium text-zinc-950">{friends}</p>
            </div>
          )}
          {want && (
            <p className="flex items-center gap-2 text-sm font-medium text-want">
              <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d={ICONS.flag} />
              </svg>
              On your Want to try list
            </p>
          )}
          {lists.length > 0 && (
            <p className="text-sm text-muted">
              {lists.length === 1 ? "On your list: " : "On your lists: "}
              {lists.map((l) => l.name).join(", ")}
            </p>
          )}
        </div>
      )}

      <ul className="border-t border-[#f0f0f0]">
        {lines.length > 0 && (
          <Row icon={ICONS.pin} alignTop>
            <span className="flex-1 text-[15px] leading-[1.45] text-zinc-950">
              {lines.map((l, i) => (
                <span key={i} className="block">
                  {l}
                </span>
              ))}
            </span>
            {layout !== "page" && <DirectionsMenu place={place} />}
          </Row>
        )}
        {place.phone && (
          <Row icon={ICONS.phone}>
            <a href={phoneHref(place.phone)} className="text-[15px] text-link hover:underline">
              {formatPhone(place.phone)}
            </a>
          </Row>
        )}
        {place.website && (
          <Row icon={ICONS.globe}>
            <a
              href={place.website.includes("://") ? place.website : `https://${place.website}`}
              target="_blank"
              rel="noopener noreferrer"
              className="min-w-0 truncate text-[15px] text-link hover:underline"
            >
              {websiteHost(place.website)}
            </a>
          </Row>
        )}
        <Row icon={ICONS.clock} alignTop>
          <span className="text-[15px] leading-[1.45] text-zinc-950">
            {place.hours ?? "Hours not listed"}
            {!place.hours && place.website && <span className="block text-sm text-muted">Check their website for today’s hours.</span>}
          </span>
        </Row>
      </ul>

      <div className="flex flex-col gap-2 text-[13px] text-muted">
        <p>{sourcesLine(place.sources)}</p>
        <p>
          Something wrong? Suggest an edit · Report closed{" "}
          <span className="ml-1 rounded-full bg-zinc-100 px-1.5 py-0.5 text-[11px] font-medium text-[#5c5c5c]">Soon</span>
        </p>
        <p>Own this place? Claiming is coming soon.</p>
      </div>

      <JoinNote open={joinOpen} onClose={() => setJoinOpen(false)} />
    </div>
  );
}
