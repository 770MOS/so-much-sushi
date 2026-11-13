"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import Avatar from "@/components/Avatar";
import JoinPanel from "@/components/lists/JoinPanel";
import InviteDialog from "@/components/friends/InviteDialog";
import RelationButton from "@/components/friends/RelationButton";
import Dialog, { secondaryButton } from "@/components/lists/Dialog";
import { PEOPLE_PATH } from "@/lib/lists";
import { plural, type FoundPerson, type Friend, type FriendsOverview, type Person, type Relation } from "@/lib/friends";
import { useUserId } from "@/lib/useSignedIn";

// The Friends page (mocked 2026-11-12): requests waiting for you (Accept or Decline) and the ones
// you sent (Cancel); find people by name or username, or send your invite link; your friends
// with their favorites and the lists they share with you, each with a menu to remove them.
// Friends see each other's favorites and any lists set to Friends.

function PeopleIcon({ size = 18 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={PEOPLE_PATH} />
    </svg>
  );
}

function PersonLink({ p, children }: { p: { handle: string | null }; children: React.ReactNode }) {
  return p.handle ? (
    <Link href={`/u/${p.handle}`} className="hover:underline">
      {children}
    </Link>
  ) : (
    <>{children}</>
  );
}

function FriendMenu({ friend, onRemove }: { friend: Friend; onRemove: () => void }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    function onDown(e: PointerEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("pointerdown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);
  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-label={`More for ${friend.name}`}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className="flex h-11 w-11 items-center justify-center rounded-lg text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900"
      >
        <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" aria-hidden="true">
          <path d="M5 12h.01M12 12h.01M19 12h.01" />
        </svg>
      </button>
      {open && (
        <div role="menu" className="absolute right-0 z-20 mt-1 w-56 rounded-xl border border-line bg-white p-1 shadow-[0_8px_24px_rgba(0,0,0,0.12)]">
          {friend.handle && (
            <Link href={`/u/${friend.handle}`} role="menuitem" className="flex min-h-11 w-full items-center rounded-lg px-3 text-[15px] text-zinc-950 hover:bg-zinc-100">
              See their favorites
            </Link>
          )}
          <button
            type="button"
            role="menuitem"
            onClick={() => {
              setOpen(false);
              onRemove();
            }}
            className="flex min-h-11 w-full items-center rounded-lg px-3 text-left text-[15px] text-red-700 hover:bg-zinc-100"
          >
            Remove friend
          </button>
        </div>
      )}
    </div>
  );
}

export default function FriendsPage() {
  const supabase = useMemo(() => createClient(), []);
  const userId = useUserId();
  const [data, setData] = useState<FriendsOverview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [inviting, setInviting] = useState(false);
  const [removing, setRemoving] = useState<Friend | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [sort, setSort] = useState<"az" | "new">("az");
  const [q, setQ] = useState("");
  const [found, setFound] = useState<{ q: string; rows: FoundPerson[] } | null>(null);

  const load = useCallback(async () => {
    const { data: d, error: err } = await supabase.rpc("friends_overview");
    if (err) setError("Something went wrong loading your friends. Try again in a moment.");
    setData((d as FriendsOverview | null) ?? { incoming: [], outgoing: [], friends: [] });
  }, [supabase]);

  useEffect(() => {
    if (!userId) return;
    let cancelled = false;
    (async () => {
      await Promise.resolve();
      if (!cancelled) await load();
    })();
    return () => {
      cancelled = true;
    };
  }, [userId, load]);

  const term = q.trim();
  useEffect(() => {
    if (!userId || term.length < 2) return;
    let cancelled = false;
    const t = setTimeout(() => {
      supabase.rpc("find_people", { q: term }).then(({ data: rows }) => {
        if (!cancelled) setFound({ q: term, rows: (rows as FoundPerson[] | null) ?? [] });
      });
    }, 200);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [term, userId, supabase]);

  async function answer(p: Person, accept: boolean) {
    setBusy(p.id);
    await supabase.rpc("answer_friend_request", { other: p.id, accept });
    setBusy(null);
    load();
  }
  async function cancel(p: Person) {
    setBusy(p.id);
    await supabase.rpc("remove_friend", { other: p.id });
    setBusy(null);
    load();
  }
  async function remove(f: Friend) {
    setBusy(f.id);
    await supabase.rpc("remove_friend", { other: f.id });
    setBusy(null);
    setRemoving(null);
    load();
  }

  function foundChanged(id: string, relation: Relation) {
    setFound((prev) => (prev ? { ...prev, rows: prev.rows.map((r) => (r.id === id ? { ...r, relation } : r)) } : prev));
    load();
  }

  if (userId === undefined) return <main className="flex-1" />;
  if (userId === null) {
    return (
      <JoinPanel
        icon={<span className="text-friends-ink"><PeopleIcon size={28} /></span>}
        title="Friends come with a free account"
        body="Friends see each other's favorites, and any lists set to Friends. Join free to add yours."
      />
    );
  }

  const friends = [...(data?.friends ?? [])].sort((a, b) =>
    sort === "az" ? a.name.localeCompare(b.name) : new Date(b.since).getTime() - new Date(a.since).getTime()
  );
  const rows = found && found.q === term ? found.rows : null;
  const requests = (data?.incoming.length ?? 0) + (data?.outgoing.length ?? 0);
  const btn = "inline-flex h-10 shrink-0 items-center justify-center rounded-[10px] px-4 text-sm font-medium disabled:opacity-50";

  return (
    <main className="mx-auto flex w-full max-w-[920px] flex-1 flex-col gap-8 px-5 pb-14 pt-8 md:px-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="flex flex-col gap-1">
          <h1 className="text-3xl font-medium tracking-tight text-zinc-950">Friends</h1>
          <p className="text-[15px] text-muted">Friends see each other’s favorites and any lists set to Friends.</p>
        </div>
        <button
          type="button"
          onClick={() => setInviting(true)}
          className="inline-flex h-11 items-center gap-2 rounded-[10px] bg-primary px-4 text-[15px] font-medium text-white hover:bg-primary-hover"
        >
          <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0M16 19h6M19 16v6M6 21v-2a4 4 0 0 1 4 -4h4" />
          </svg>
          Invite a friend
        </button>
      </div>

      {error && <p className="text-sm text-red-700">{error}</p>}

      {requests > 0 && data && (
        <section aria-labelledby="req-h" className="flex flex-col gap-2.5">
          <h2 id="req-h" className="text-lg font-medium text-zinc-950">
            Requests
          </h2>
          <ul className="rounded-[14px] border border-line">
            {data.incoming.map((p) => (
              <li key={p.id} className="flex flex-wrap items-center gap-3.5 border-b border-[#f0f0f0] px-4 py-3.5 last:border-b-0">
                <Avatar name={p.name} seed={p.handle} />
                <span className="flex min-w-[180px] flex-1 flex-col gap-0.5">
                  <span className="text-base font-medium text-zinc-950">
                    <PersonLink p={p}>{p.name}</PersonLink>
                  </span>
                  <span className="text-sm text-muted">
                    Wants to be friends{p.in_common > 0 ? ` · ${plural(p.in_common, "friend", "friends")} in common` : ""}
                  </span>
                </span>
                <button type="button" disabled={busy === p.id} onClick={() => answer(p, true)} className={`${btn} bg-primary text-white hover:bg-primary-hover`}>
                  Accept
                </button>
                <button type="button" disabled={busy === p.id} onClick={() => answer(p, false)} className={`${btn} border border-[#dddddd] bg-white text-zinc-950 hover:bg-zinc-50`}>
                  Decline
                </button>
              </li>
            ))}
            {data.outgoing.map((p) => (
              <li key={p.id} className="flex flex-wrap items-center gap-3.5 border-b border-[#f0f0f0] px-4 py-3.5 last:border-b-0">
                <Avatar name={p.name} seed={p.handle} />
                <span className="flex min-w-[180px] flex-1 flex-col gap-0.5">
                  <span className="text-base font-medium text-zinc-950">
                    <PersonLink p={p}>{p.name}</PersonLink>
                  </span>
                  <span className="text-sm text-muted">You sent a request · waiting for an answer</span>
                </span>
                <button type="button" disabled={busy === p.id} onClick={() => cancel(p)} className={`${btn} border border-[#dddddd] bg-white text-zinc-950 hover:bg-zinc-50`}>
                  Cancel request
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section aria-labelledby="find-h" className="flex flex-col gap-2.5">
        <h2 id="find-h" className="text-lg font-medium text-zinc-950">
          Find friends
        </h2>
        <div className="flex flex-wrap gap-2.5">
          <label className="flex h-12 min-w-0 flex-[1_1_360px] items-center gap-2 rounded-[10px] border border-[#dddddd] px-3.5 focus-within:border-zinc-950">
            <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="#5c5c5c" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M10 10m-7 0a7 7 0 1 0 14 0a7 7 0 1 0 -14 0M21 21l-6 -6" />
            </svg>
            <span className="sr-only">Find a friend by name or username</span>
            <input
              type="search"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Name or username"
              autoComplete="off"
              className="h-10 min-w-0 flex-1 border-0 bg-transparent text-base text-zinc-950 placeholder:text-[#707070] focus:outline-none"
            />
          </label>
          <button
            type="button"
            onClick={() => setInviting(true)}
            className="inline-flex h-12 items-center gap-2 rounded-[10px] border border-[#dddddd] bg-white px-4 text-[15px] font-medium text-zinc-950 hover:bg-zinc-50"
          >
            <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M9 15l6 -6M11 6l.463 -.536a5 5 0 0 1 7.071 7.072l-.534 .464M13 18l-.397 .534a5.068 5.068 0 0 1 -7.127 0a4.972 4.972 0 0 1 0 -7.071l.524 -.463" />
            </svg>
            Copy your invite link
          </button>
        </div>
        {term.length >= 2 && (
          <div aria-live="polite">
            {rows === null ? (
              <p className="py-2 text-sm text-muted">Looking…</p>
            ) : rows.length === 0 ? (
              <p className="py-2 text-sm text-muted">No one by that name. Send them your invite link instead.</p>
            ) : (
              <ul className="border-t border-[#f0f0f0]">
                {rows.map((p) => (
                  <li key={p.id} className="flex items-center gap-3.5 border-b border-[#f0f0f0] py-3">
                    <Avatar name={p.name} seed={p.handle} />
                    <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                      <span className="truncate text-base font-medium text-zinc-950">
                        <PersonLink p={p}>{p.name}</PersonLink>
                      </span>
                      <span className="truncate text-sm text-muted">
                        {p.handle ? `@${p.handle}` : ""}
                        {p.in_common > 0 ? `${p.handle ? " · " : ""}${plural(p.in_common, "friend", "friends")} in common` : ""}
                      </span>
                    </span>
                    <RelationButton personId={p.id} name={p.name} relation={p.relation} signedIn onChange={(r) => foundChanged(p.id, r)} />
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
        <p className="text-[13px] text-muted">Finding friends by phone number, and from your phone’s contacts, comes with the app.</p>
      </section>

      <section aria-labelledby="yours-h" className="flex flex-col gap-2.5">
        <div className="flex items-baseline justify-between gap-3">
          <h2 id="yours-h" className="text-lg font-medium text-zinc-950">
            Your friends <span className="text-[15px] font-normal text-muted">{data ? friends.length : ""}</span>
          </h2>
          {friends.length > 1 && (
            <label className="relative inline-flex">
              <span className="sr-only">Sort friends</span>
              <select
                value={sort}
                onChange={(e) => setSort(e.target.value === "new" ? "new" : "az")}
                className="h-10 appearance-none bg-transparent pl-1 pr-6 text-sm font-medium text-zinc-950 focus:outline-none"
              >
                <option value="az">Name A–Z</option>
                <option value="new">Newest friends</option>
              </select>
              <svg className="pointer-events-none absolute right-1 top-3" viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M6 9l6 6l6 -6" />
              </svg>
            </label>
          )}
        </div>
        {data === null ? (
          <p className="py-6 text-sm text-muted">Loading…</p>
        ) : friends.length === 0 ? (
          <p className="py-6 text-[15px] text-muted">
            No friends here yet. Find someone above, or send your invite link.
          </p>
        ) : (
          <ul className="border-t border-[#f0f0f0]">
            {friends.map((f) => {
              const inner = (
                <>
                  <Avatar name={f.name} seed={f.handle} size={44} />
                  <span className="flex min-w-0 flex-col gap-0.5">
                    <span className="truncate text-base font-medium">{f.name}</span>
                    <span className="truncate text-sm text-muted">
                      {plural(f.favorites, "favorite", "favorites")} ·{" "}
                      {f.shared_lists === 0 ? "no shared lists" : `${plural(f.shared_lists, "list", "lists")} shared with you`}
                    </span>
                  </span>
                </>
              );
              return (
                <li key={f.id} className="flex items-center gap-1.5 border-b border-[#f0f0f0]">
                  {f.handle ? (
                    <Link href={`/u/${f.handle}`} className="flex min-w-0 flex-1 items-center gap-3.5 py-3.5 text-zinc-950">
                      {inner}
                    </Link>
                  ) : (
                    <span className="flex min-w-0 flex-1 items-center gap-3.5 py-3.5 text-zinc-950">{inner}</span>
                  )}
                  <FriendMenu friend={f} onRemove={() => setRemoving(f)} />
                </li>
              );
            })}
          </ul>
        )}
        <p className="mt-1 text-[13px] text-muted">You can remove a friend at any time from the menu next to their name.</p>
      </section>

      {inviting && <InviteDialog onClose={() => setInviting(false)} />}
      {removing && (
        <Dialog title={`Remove ${removing.name}?`} onClose={() => setRemoving(null)}>
          <p className="mt-2 text-[15px] leading-relaxed text-muted">
            You’ll stop seeing each other’s favorites and Friends lists. They aren’t told; you can add each other again later.
          </p>
          <div className="mt-5 flex justify-end gap-2">
            <button type="button" onClick={() => setRemoving(null)} className={secondaryButton}>
              Keep
            </button>
            <button
              type="button"
              onClick={() => remove(removing)}
              disabled={busy === removing.id}
              className="inline-flex h-11 items-center justify-center rounded-[10px] bg-red-700 px-5 text-[15px] font-medium text-white hover:bg-red-800 disabled:opacity-50"
            >
              Remove friend
            </button>
          </div>
        </Dialog>
      )}
    </main>
  );
}
