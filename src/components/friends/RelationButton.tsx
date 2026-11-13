"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import type { Relation } from "@/lib/friends";

// The one button for how you're connected to someone: Add friend, Requested (tap to take it
// back), Accept, or Friends. Calls the friend-request functions and reports the new relation.
export default function RelationButton({
  personId,
  name,
  relation,
  onChange,
  signedIn,
  next,
}: {
  personId: string;
  name: string;
  relation: Relation;
  onChange: (r: Relation) => void;
  signedIn: boolean;
  next?: string;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);

  async function call(fn: "send_friend_request" | "answer_friend_request" | "remove_friend", args: Record<string, unknown>) {
    setBusy(true);
    setError(false);
    const { data, error: err } = await supabase.rpc(fn, args);
    setBusy(false);
    if (err) {
      setError(true);
      return;
    }
    onChange(data as Relation);
  }

  const base = "inline-flex h-10 shrink-0 items-center justify-center rounded-[10px] px-4 text-sm font-medium disabled:opacity-50";
  const dark = `${base} bg-primary text-white hover:bg-primary-hover`;
  const light = `${base} border border-[#dddddd] bg-white text-zinc-950 hover:bg-zinc-50`;

  if (relation === "self") return null;
  if (!signedIn) {
    return (
      <Link href={`/sign-in${next ? `?next=${encodeURIComponent(next)}` : ""}`} className={dark}>
        Sign in to add {name.split(/\s+/)[0]}
      </Link>
    );
  }
  return (
    <span className="inline-flex flex-col items-end gap-1">
      {relation === "none" && (
        <button type="button" disabled={busy} onClick={() => call("send_friend_request", { other: personId })} className={dark}>
          Add friend
        </button>
      )}
      {relation === "sent" && (
        <button
          type="button"
          disabled={busy}
          onClick={() => call("remove_friend", { other: personId })}
          aria-label={`Request sent to ${name}. Take it back`}
          className={light}
        >
          Requested · Cancel
        </button>
      )}
      {relation === "received" && (
        <button type="button" disabled={busy} onClick={() => call("answer_friend_request", { other: personId, accept: true })} className={dark}>
          Accept
        </button>
      )}
      {relation === "friends" && <span className="inline-flex h-10 items-center text-sm font-medium text-friends-ink">Friends</span>}
      {error && <span className="text-xs text-red-700">That didn&apos;t work. Try again.</span>}
    </span>
  );
}
