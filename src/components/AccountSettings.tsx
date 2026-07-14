"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import { HANDLE_PATTERN, HANDLE_HINT, isHandleTakenError, handleTakenMessage } from "@/lib/handleValidation";
import LocationInput from "@/components/LocationInput";
import { useGeolocation } from "@/lib/useGeolocation";
import { CURRENT_LOCATION_LABEL, type Coords } from "@/lib/lastSearchCoords";
import { reverseGeocodeCityState } from "@/lib/reverseGeocode";
import { forwardGeocodeCityState } from "@/lib/forwardGeocode";

type Props = {
  userId: string;
};

type ProfileRow = {
  display_name: string | null;
  handle: string | null;
};

type HomeLocation = {
  home_city: string | null;
  home_state: string | null;
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

  const [homeLocation, setHomeLocation] = useState<HomeLocation | null | undefined>(undefined);
  const [editingLocation, setEditingLocation] = useState(false);
  const [locationValue, setLocationValue] = useState("");
  const [locationCoords, setLocationCoords] = useState<Coords | null>(null);
  const [locationSaving, setLocationSaving] = useState(false);
  const [locationError, setLocationError] = useState<string | null>(null);
  const [locationSaved, setLocationSaved] = useState(false);
  const locationGeo = useGeolocation("Try entering an address instead.");

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

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data, error } = await supabase.rpc("get_my_home_location");
      if (cancelled) return;
      if (error) {
        setHomeLocation(null);
        return;
      }
      setHomeLocation(data?.[0] ?? { home_city: null, home_state: null });
    })();
    return () => {
      cancelled = true;
    };
  }, [supabase]);

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

  function startEditingLocation() {
    setLocationValue(
      homeLocation?.home_city || homeLocation?.home_state
        ? [homeLocation.home_city, homeLocation.home_state].filter(Boolean).join(", ")
        : ""
    );
    setLocationCoords(null);
    setLocationError(null);
    setLocationSaved(false);
    setEditingLocation(true);
  }

  function cancelEditingLocation() {
    setEditingLocation(false);
    setLocationError(null);
  }

  async function handleUseMyLocationForHome() {
    const coords = await locationGeo.requestLocation();
    if (!coords) return;
    setLocationCoords(coords);
    setLocationValue(CURRENT_LOCATION_LABEL);
  }

  async function handleSaveLocation() {
    if (locationSaving) return;
    if (!locationValue.trim()) return;

    setLocationSaving(true);
    setLocationError(null);
    setLocationSaved(false);

    try {
      let cityState: { city: string | null; state: string | null } | null;
      if (locationValue === CURRENT_LOCATION_LABEL && locationCoords) {
        cityState = await reverseGeocodeCityState(locationCoords);
      } else {
        cityState = await forwardGeocodeCityState(locationValue);
      }

      if (!cityState || (!cityState.city && !cityState.state)) {
        setLocationError("We couldn't find a city and state for that location. Try a ZIP code or a fuller address.");
        return;
      }

      const { error } = await supabase
        .from("profiles")
        .update({ home_city: cityState.city, home_state: cityState.state })
        .eq("id", userId);
      if (error) {
        setLocationError("Something went wrong saving your home location. Please try again.");
        return;
      }

      setHomeLocation({ home_city: cityState.city, home_state: cityState.state });
      setEditingLocation(false);
      setLocationSaved(true);
    } finally {
      setLocationSaving(false);
    }
  }

  async function handleClearLocation() {
    setLocationSaving(true);
    setLocationError(null);
    setLocationSaved(false);
    try {
      const { error } = await supabase
        .from("profiles")
        .update({ home_city: null, home_state: null })
        .eq("id", userId);
      if (error) {
        setLocationError("Something went wrong clearing your home location. Please try again.");
        return;
      }
      setHomeLocation({ home_city: null, home_state: null });
      setEditingLocation(false);
      setLocationSaved(true);
    } finally {
      setLocationSaving(false);
    }
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

      <div className="flex flex-col gap-2 border-t border-zinc-200 pt-3 dark:border-zinc-800">
        {!editingLocation ? (
          <div className="flex items-center justify-between gap-3">
            <p className="text-sm text-zinc-700 dark:text-zinc-300">
              Home location:{" "}
              <span className="text-zinc-500 dark:text-zinc-400">
                {homeLocation === undefined
                  ? "Loading…"
                  : homeLocation?.home_city || homeLocation?.home_state
                    ? [homeLocation.home_city, homeLocation.home_state].filter(Boolean).join(", ")
                    : "Not set"}
              </span>
            </p>
            <div className="flex shrink-0 items-center gap-3">
              <button
                type="button"
                onClick={startEditingLocation}
                className="text-sm text-zinc-500 underline hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
              >
                {homeLocation?.home_city || homeLocation?.home_state ? "Change" : "Set"}
              </button>
              {(homeLocation?.home_city || homeLocation?.home_state) && (
                <button
                  type="button"
                  onClick={handleClearLocation}
                  disabled={locationSaving}
                  className="text-sm text-zinc-500 underline hover:text-zinc-900 disabled:cursor-not-allowed disabled:opacity-50 dark:text-zinc-400 dark:hover:text-zinc-100"
                >
                  Clear
                </button>
              )}
            </div>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            <label htmlFor="home-location" className="text-xs text-zinc-500 dark:text-zinc-400">
              Home location
            </label>
            <LocationInput
              id="home-location"
              value={locationValue}
              onChange={(v) => {
                setLocationValue(v);
                setLocationCoords(null);
              }}
              onUseMyLocation={handleUseMyLocationForHome}
              locating={locationGeo.locating}
            />
            {locationGeo.geoError && (
              <p className="text-xs text-red-600 dark:text-red-400">{locationGeo.geoError}</p>
            )}
            <div className="flex items-center gap-3">
              <button
                type="button"
                onClick={handleSaveLocation}
                disabled={locationSaving || !locationValue.trim()}
                className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
              >
                {locationSaving ? "Saving…" : "Save"}
              </button>
              <button
                type="button"
                onClick={cancelEditingLocation}
                disabled={locationSaving}
                className="text-sm text-zinc-500 underline hover:text-zinc-900 disabled:cursor-not-allowed disabled:opacity-50 dark:text-zinc-400 dark:hover:text-zinc-100"
              >
                Cancel
              </button>
            </div>
          </div>
        )}

        {locationError && <p className="text-sm text-red-600 dark:text-red-400">{locationError}</p>}
        {locationSaved && <p className="text-sm text-green-600 dark:text-green-400">Saved.</p>}
      </div>
    </div>
  );
}
