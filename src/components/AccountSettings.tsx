"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import { HANDLE_PATTERN, HANDLE_HINT, isHandleTakenError, handleTakenMessage } from "@/lib/handleValidation";

type Props = {
  userId: string;
};

type ProfileRow = {
  display_name: string | null;
  handle: string | null;
};

const inputClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50";

export default function AccountSettings({ userId }: Props) {
  const supabase = useMemo(() => createClient(), []);

  const [profile, setProfile] = useState<ProfileRow | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [displayName, setDisplayName] = useState("");
  const [handle, setHandle] = useState("");
  const [saving, setSaving] = useState(false);
  const [handleError, setHandleError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      await Promise.resolve();
      if (cancelled) return;
      const { data, error } = await supabase
        .from("profiles")
        .select("display_name, handle")
        .eq("id", userId)
        .single();
      if (cancelled) return;
      if (error) {
        setLoadError("Something went wrong loading your account settings.");
        return;
      }
      setProfile(data);
      setDisplayName(data?.display_name ?? "");
      setHandle(data?.handle ?? "");
    })();
    return () => {
      cancelled = true;
    };
  }, [supabase, userId]);

  async function handleSave(e: FormEvent) {
    e.preventDefault();
    if (saving) return;

    setHandleError(null);
    setSaveError(null);
    setSaved(false);

    const trimmedHandle = handle.trim().toLowerCase();
    if (trimmedHandle && !HANDLE_PATTERN.test(trimmedHandle)) {
      setHandleError(HANDLE_HINT);
      return;
    }

    setSaving(true);
    const { error } = await supabase
      .from("profiles")
      .update({
        display_name: displayName.trim() || null,
        handle: trimmedHandle || null,
      })
      .eq("id", userId);
    setSaving(false);

    if (error) {
      if (isHandleTakenError(error)) {
        setHandleError(handleTakenMessage());
      } else {
        setSaveError("Something went wrong saving your changes. Please try again.");
      }
      return;
    }

    setProfile({ display_name: displayName.trim() || null, handle: trimmedHandle || null });
    setHandle(trimmedHandle);
    setSaved(true);
  }

  return (
    <div className="flex flex-col gap-3 rounded-lg border border-zinc-200 p-4 dark:border-zinc-800">
      {loadError && <p className="text-sm text-red-600 dark:text-red-400">{loadError}</p>}

      {profile && !profile.handle && (
        <div className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-800 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-200">
          Set a handle so people can find you in Connections search.
        </div>
      )}

      <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">Account settings</h2>

      <form onSubmit={handleSave} className="flex flex-col gap-3 sm:flex-row sm:items-start">
        <div className="flex flex-1 flex-col gap-1">
          <label htmlFor="display-name" className="text-xs text-zinc-500 dark:text-zinc-400">
            Display name
          </label>
          <p className="text-xs text-zinc-400 dark:text-zinc-500">How you&apos;re shown to others.</p>
          <input
            id="display-name"
            type="text"
            maxLength={80}
            value={displayName}
            onChange={(e) => {
              setDisplayName(e.target.value);
              setSaved(false);
            }}
            className={inputClass}
          />
        </div>

        <div className="flex flex-1 flex-col gap-1">
          <label htmlFor="handle" className="text-xs text-zinc-500 dark:text-zinc-400">
            Handle
          </label>
          <p className="text-xs text-zinc-400 dark:text-zinc-500">How connections find you.</p>
          <div className="flex items-center gap-1">
            <span className="text-zinc-400">@</span>
            <input
              id="handle"
              type="text"
              maxLength={20}
              value={handle}
              onChange={(e) => {
                setHandle(e.target.value);
                setHandleError(null);
                setSaved(false);
              }}
              className={inputClass}
            />
          </div>
          <p
            className={`text-xs ${handleError ? "text-red-600 dark:text-red-400" : "text-zinc-400 dark:text-zinc-500"}`}
          >
            {handleError ?? HANDLE_HINT}
          </p>
        </div>

        <button
          type="submit"
          disabled={saving}
          className="shrink-0 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50 sm:mt-5"
        >
          {saving ? "Saving…" : "Save"}
        </button>
      </form>

      {saveError && <p className="text-sm text-red-600 dark:text-red-400">{saveError}</p>}
      {saved && <p className="text-sm text-green-600 dark:text-green-400">Saved.</p>}
    </div>
  );
}
