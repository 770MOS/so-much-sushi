"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

type PersonProfile = {
  id: string;
  handle: string | null;
  display_name: string | null;
  avatar_url: string | null;
};

type FriendshipRow = {
  requester_id: string;
  addressee_id: string;
  status: "pending" | "accepted" | "blocked";
  created_at: string;
  requester: PersonProfile;
  addressee: PersonProfile;
};

type Props = {
  userId: string;
};

function personLabel(p: PersonProfile) {
  return p.display_name?.trim() || p.handle?.trim() || "Unknown";
}

// Links to the person's public profile using their handle (the unique
// lookup key /u/[handle] resolves by) - falls back to plain text if they
// don't have one set.
function PersonName({ person }: { person: PersonProfile }) {
  const label = personLabel(person);
  if (!person.handle) {
    return <span className="font-medium text-zinc-950 dark:text-zinc-50">{label}</span>;
  }
  return (
    <Link
      href={`/u/${person.handle}`}
      className="font-medium text-zinc-950 hover:underline dark:text-zinc-50"
    >
      {label}
    </Link>
  );
}

function otherPerson(row: FriendshipRow, userId: string): PersonProfile {
  return row.requester_id === userId ? row.addressee : row.requester;
}

const rowClass = "flex items-center justify-between gap-4 py-3";

const secondaryBtnClass =
  "rounded-lg border border-zinc-300 px-3 py-1.5 text-sm font-medium text-zinc-700 transition-colors hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800";

const primaryBtnClass =
  "rounded-lg bg-primary px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-primary-hover";

export default function ConnectionsTab({ userId }: Props) {
  const supabase = useMemo(() => createClient(), []);

  const [friendships, setFriendships] = useState<FriendshipRow[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const [query, setQuery] = useState("");
  const [searching, setSearching] = useState(false);
  const [searchResults, setSearchResults] = useState<PersonProfile[] | null>(null);
  const [searchError, setSearchError] = useState<string | null>(null);

  const loadFriendships = useCallback(async () => {
    const { data, error } = await supabase
      .from("friendships")
      .select(
        "requester_id, addressee_id, status, created_at, " +
          "requester:profiles!friendships_requester_id_fkey(id, handle, display_name, avatar_url), " +
          "addressee:profiles!friendships_addressee_id_fkey(id, handle, display_name, avatar_url)"
      )
      .or(`requester_id.eq.${userId},addressee_id.eq.${userId}`);

    if (error) {
      setLoadError("Something went wrong loading your connections.");
      return;
    }
    setFriendships((data as unknown as FriendshipRow[]) ?? []);
  }, [supabase, userId]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      await Promise.resolve();
      if (cancelled) return;
      await loadFriendships();
    })();
    return () => {
      cancelled = true;
    };
  }, [loadFriendships]);

  const incoming = (friendships ?? []).filter(
    (f) => f.status === "pending" && f.addressee_id === userId
  );
  const outgoing = (friendships ?? []).filter(
    (f) => f.status === "pending" && f.requester_id === userId
  );
  const connections = (friendships ?? []).filter((f) => f.status === "accepted");

  function statusWith(otherId: string): FriendshipRow | undefined {
    return (friendships ?? []).find(
      (f) =>
        (f.requester_id === userId && f.addressee_id === otherId) ||
        (f.addressee_id === userId && f.requester_id === otherId)
    );
  }

  async function handleSearch(e: FormEvent) {
    e.preventDefault();
    if (!query.trim() || searching) return;

    setSearching(true);
    setSearchError(null);
    const { data, error } = await supabase
      .from("profiles")
      .select("id, handle, display_name, avatar_url")
      .neq("id", userId)
      .not("handle", "is", null)
      .ilike("handle", `%${query.trim()}%`)
      .limit(20);
    setSearching(false);

    if (error) {
      setSearchError("Something went wrong searching. Please try again.");
      return;
    }
    setSearchResults(data ?? []);
  }

  async function handleConnect(otherId: string) {
    setActionError(null);
    const { error } = await supabase
      .from("friendships")
      .insert({ requester_id: userId, addressee_id: otherId });
    if (error) {
      setActionError("Something went wrong sending that request.");
      return;
    }
    await loadFriendships();
  }

  async function handleAccept(row: FriendshipRow) {
    setActionError(null);
    const { error } = await supabase
      .from("friendships")
      .update({ status: "accepted" })
      .eq("requester_id", row.requester_id)
      .eq("addressee_id", row.addressee_id);
    if (error) {
      setActionError("Something went wrong accepting that request.");
      return;
    }
    await loadFriendships();
  }

  async function handleRemove(row: FriendshipRow) {
    setActionError(null);
    const { error } = await supabase
      .from("friendships")
      .delete()
      .eq("requester_id", row.requester_id)
      .eq("addressee_id", row.addressee_id);
    if (error) {
      setActionError("Something went wrong. Please try again.");
      return;
    }
    await loadFriendships();
  }

  return (
    <div className="flex flex-col gap-8">
      {loadError && <p className="text-sm text-red-600 dark:text-red-400">{loadError}</p>}
      {actionError && <p className="text-sm text-red-600 dark:text-red-400">{actionError}</p>}

      <div className="flex flex-col gap-3">
        <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">Find people</h2>
        <form onSubmit={handleSearch} className="flex gap-2">
          <input
            type="text"
            placeholder="Search by handle"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
          />
          <button
            type="submit"
            disabled={!query.trim() || searching}
            className={`${primaryBtnClass} shrink-0 disabled:cursor-not-allowed disabled:opacity-50`}
          >
            {searching ? "Searching…" : "Search"}
          </button>
        </form>
        {searchError && <p className="text-sm text-red-600 dark:text-red-400">{searchError}</p>}

        {searchResults !== null &&
          (searchResults.length === 0 ? (
            <p className="text-sm text-zinc-500 dark:text-zinc-400">No matching handles found.</p>
          ) : (
            <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
              {searchResults.map((p) => {
                const existing = statusWith(p.id);
                return (
                  <li key={p.id} className={rowClass}>
                    <div className="flex flex-col gap-0.5">
                      <PersonName person={p} />
                      {p.handle && (
                        <span className="text-sm text-zinc-500 dark:text-zinc-400">@{p.handle}</span>
                      )}
                    </div>
                    {!existing ? (
                      <button
                        type="button"
                        onClick={() => handleConnect(p.id)}
                        className={primaryBtnClass}
                      >
                        Connect
                      </button>
                    ) : existing.status === "accepted" ? (
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">Connected</span>
                    ) : existing.requester_id === userId ? (
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">Requested</span>
                    ) : (
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">Respond below</span>
                    )}
                  </li>
                );
              })}
            </ul>
          ))}
      </div>

      <div className="flex flex-col gap-3">
        <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
          Incoming requests{incoming.length > 0 ? ` (${incoming.length})` : ""}
        </h2>
        {incoming.length === 0 ? (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">No incoming requests.</p>
        ) : (
          <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
            {incoming.map((row) => {
              const other = otherPerson(row, userId);
              return (
                <li key={`${row.requester_id}-${row.addressee_id}`} className={rowClass}>
                  <div className="flex flex-col gap-0.5">
                    <PersonName person={other} />
                    {other.handle && (
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">@{other.handle}</span>
                    )}
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    <button type="button" onClick={() => handleAccept(row)} className={primaryBtnClass}>
                      Accept
                    </button>
                    <button type="button" onClick={() => handleRemove(row)} className={secondaryBtnClass}>
                      Decline
                    </button>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <div className="flex flex-col gap-3">
        <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
          Outgoing requests{outgoing.length > 0 ? ` (${outgoing.length})` : ""}
        </h2>
        {outgoing.length === 0 ? (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">No outgoing requests.</p>
        ) : (
          <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
            {outgoing.map((row) => {
              const other = otherPerson(row, userId);
              return (
                <li key={`${row.requester_id}-${row.addressee_id}`} className={rowClass}>
                  <div className="flex flex-col gap-0.5">
                    <PersonName person={other} />
                    {other.handle && (
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">@{other.handle}</span>
                    )}
                  </div>
                  <button type="button" onClick={() => handleRemove(row)} className={secondaryBtnClass}>
                    Cancel
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <div className="flex flex-col gap-3">
        <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
          Connections{connections.length > 0 ? ` (${connections.length})` : ""}
        </h2>
        {connections.length === 0 ? (
          <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
            You haven&apos;t connected with anyone yet. Search for a handle above to get started.
          </p>
        ) : (
          <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
            {connections.map((row) => {
              const other = otherPerson(row, userId);
              return (
                <li key={`${row.requester_id}-${row.addressee_id}`} className={rowClass}>
                  <div className="flex flex-col gap-0.5">
                    <PersonName person={other} />
                    {other.handle && (
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">@{other.handle}</span>
                    )}
                  </div>
                  <button type="button" onClick={() => handleRemove(row)} className={secondaryBtnClass}>
                    Remove
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
}
