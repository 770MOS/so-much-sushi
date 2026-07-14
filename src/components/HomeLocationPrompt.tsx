"use client";

import { useEffect, useMemo, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { useGeolocation } from "@/lib/useGeolocation";
import { reverseGeocodeCityState } from "@/lib/reverseGeocode";
import { isHomeLocationPromptDismissed, dismissHomeLocationPrompt } from "@/lib/homeLocationPrompt";

// Shown once per device, the first time a signed-in user with no home
// location set loads any page under the sidebar layout - not literally
// "at sign-up" (there's no active session yet at that point, since email
// confirmation is required before the first real sign-in), but the first
// real opportunity to ask with a session that can actually write to
// profiles. Clearly skippable; skipping is remembered permanently on this
// device (see homeLocationPrompt.ts), not just for this session.
export default function HomeLocationPrompt() {
  const supabase = useMemo(() => createClient(), []);
  const [user, setUser] = useState<User | null>(null);
  const [visible, setVisible] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const geo = useGeolocation("You can set this later from Account Settings.");

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!user || isHomeLocationPromptDismissed(user.id)) {
        if (!cancelled) setVisible(false);
        return;
      }

      const { data, error: rpcError } = await supabase.rpc("get_my_home_location");
      if (cancelled || rpcError) return;
      const row = data?.[0];
      setVisible(!row || (!row.home_city && !row.home_state));
    })();
    return () => {
      cancelled = true;
    };
  }, [user, supabase]);

  async function handleUseMyLocation() {
    if (!user) return;
    setSaving(true);
    setError(null);
    try {
      const coords = await geo.requestLocation();
      if (!coords) return; // geo.geoError is already set by the hook

      const cityState = await reverseGeocodeCityState(coords);
      if (!cityState || (!cityState.city && !cityState.state)) {
        setError("We couldn't determine a city and state for your location.");
        return;
      }

      const { error: updateError } = await supabase
        .from("profiles")
        .update({ home_city: cityState.city, home_state: cityState.state })
        .eq("id", user.id);
      if (updateError) {
        setError("Something went wrong saving your home location.");
        return;
      }

      setVisible(false);
    } finally {
      setSaving(false);
    }
  }

  function handleSkip() {
    if (!user) return;
    dismissHomeLocationPrompt(user.id);
    setVisible(false);
  }

  if (!visible) return null;

  return (
    <div className="fixed inset-0 z-30 flex items-center justify-center bg-black/40 px-6">
      <div className="w-full max-w-sm rounded-lg border border-zinc-300 bg-white p-6 shadow-lg dark:border-zinc-700 dark:bg-zinc-900">
        <h2 className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">
          Set your home location?
        </h2>
        <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
          Pre-fill the home page&apos;s search with where you usually search from. You can change
          or remove this anytime in Account Settings.
        </p>

        {(geo.geoError || error) && (
          <p className="mt-3 text-sm text-red-600 dark:text-red-400">{geo.geoError || error}</p>
        )}

        <div className="mt-5 flex flex-col gap-2">
          <button
            type="button"
            onClick={handleUseMyLocation}
            disabled={saving || geo.locating}
            className="w-full rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
          >
            {saving || geo.locating ? "Locating…" : "Use my current location"}
          </button>
          <button
            type="button"
            onClick={handleSkip}
            className="w-full rounded-lg px-4 py-2.5 text-sm font-medium text-zinc-600 transition-colors hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
          >
            Skip for now
          </button>
        </div>
      </div>
    </div>
  );
}
