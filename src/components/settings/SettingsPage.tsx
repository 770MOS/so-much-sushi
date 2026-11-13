"use client";

import { useEffect, useMemo, useState, type FormEvent, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import Avatar from "@/components/Avatar";
import JoinPanel from "@/components/lists/JoinPanel";
import LocationInput from "@/components/LocationInput";
import PasswordInput from "@/components/PasswordInput";
import Dialog, { fieldClass, primaryButton, secondaryButton } from "@/components/lists/Dialog";
import { FavoriteIcon } from "@/components/icons";
import { HANDLE_HINT, HANDLE_PATTERN, handleTakenMessage, isHandleTakenError } from "@/lib/handleValidation";
import { PASSWORD_HINT, passwordMeetsPolicy } from "@/lib/password";
import { VISIBILITY, VISIBILITY_ORDER, type Visibility } from "@/lib/lists";
import { useGeolocation } from "@/lib/useGeolocation";
import { CURRENT_LOCATION_LABEL, type Coords } from "@/lib/lastSearchCoords";
import { reverseGeocodeCityState } from "@/lib/reverseGeocode";
import { forwardGeocodeCityState } from "@/lib/forwardGeocode";
import { deleteMyAccount } from "@/app/actions/account";

// Account settings (mocked 2026-11-12): profile and the name on public lists, sign-in, home
// area, privacy (who sees new lists), emails, download your data, sign out, delete account.

type Settings = {
  first_name: string | null;
  last_name: string | null;
  display_name: string | null;
  handle: string | null;
  public_name_full: boolean;
  new_list_visibility: Visibility;
  email_friend_requests: boolean;
  email_place_requests: boolean;
  home_city: string | null;
  home_state: string | null;
};

const SECTIONS = [
  ["profile", "Profile"],
  ["signin", "Sign-in"],
  ["home", "Home area"],
  ["privacy", "Privacy"],
  ["emails", "Emails"],
  ["data", "Your data"],
  ["account", "Sign out or delete"],
] as const;

const smallButton =
  "inline-flex h-10 shrink-0 items-center justify-center rounded-[10px] border border-[#dddddd] bg-white px-4 text-sm font-medium text-zinc-950 hover:bg-zinc-50 disabled:opacity-50";

function Section({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section id={id} aria-labelledby={`h-${id}`} className="flex scroll-mt-6 flex-col gap-4 border-b border-line py-6 last:border-b-0">
      <h2 id={`h-${id}`} className="text-lg font-medium text-zinc-950">
        {title}
      </h2>
      {children}
    </section>
  );
}

function Switch({ on, label, onChange, disabled }: { on: boolean; label: string; onChange?: (v: boolean) => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange?.(!on)}
      className={`flex h-7 w-12 shrink-0 rounded-full p-[3px] transition-colors ${on ? "justify-end bg-primary" : "justify-start bg-[#e3e3e3]"} disabled:cursor-not-allowed`}
    >
      <span className="h-[22px] w-[22px] rounded-full bg-white" />
    </button>
  );
}

function Saved({ show }: { show: boolean }) {
  return show ? (
    <span role="status" className="text-sm text-friends-ink">
      Saved
    </span>
  ) : null;
}

function toCsv(rows: Record<string, unknown>[], columns: [string, string][]): string {
  const cell = (v: unknown) => {
    const s = v === null || v === undefined ? "" : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [columns.map(([, h]) => cell(h)).join(","), ...rows.map((r) => columns.map(([k]) => cell(r[k])).join(","))].join("\n");
}

export default function SettingsPage() {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [s, setS] = useState<Settings | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [savedKey, setSavedKey] = useState<string | null>(null);

  // Profile
  const [first, setFirst] = useState("");
  const [last, setLast] = useState("");
  const [handle, setHandle] = useState("");
  const [profileError, setProfileError] = useState<string | null>(null);
  const [savingProfile, setSavingProfile] = useState(false);

  // Sign-in
  const [editing, setEditing] = useState<"email" | "password" | null>(null);
  const [newEmail, setNewEmail] = useState("");
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [signinMsg, setSigninMsg] = useState<{ ok: boolean; text: string } | null>(null);

  // Home area
  const [editingHome, setEditingHome] = useState(false);
  const [homeText, setHomeText] = useState("");
  const [homeCoords, setHomeCoords] = useState<Coords | null>(null);
  const [homeBusy, setHomeBusy] = useState(false);
  const [homeError, setHomeError] = useState<string | null>(null);
  const geo = useGeolocation("Try typing a city or ZIP code instead.");

  // Data and account
  const [downloading, setDownloading] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  useEffect(() => {
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => setUser(session?.user ?? null));
    return () => subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    supabase.rpc("my_settings").then(({ data, error: err }) => {
      if (cancelled) return;
      if (err || !data) {
        setError("Something went wrong loading your settings. Try again in a moment.");
        return;
      }
      const v = data as Settings;
      setS(v);
      setFirst(v.first_name ?? v.display_name?.split(/\s+/)[0] ?? "");
      setLast(v.last_name ?? "");
      setHandle(v.handle ?? "");
    });
    return () => {
      cancelled = true;
    };
  }, [user, supabase]);

  function flash(key: string) {
    setSavedKey(key);
    setTimeout(() => setSavedKey((k) => (k === key ? null : k)), 2500);
  }

  async function update(patch: Partial<Settings>, key: string) {
    if (!user || !s) return false;
    const { error: err } = await supabase.from("profiles").update(patch).eq("id", user.id);
    if (err) {
      setError("Something went wrong saving that. Try again.");
      return false;
    }
    setS({ ...s, ...patch });
    flash(key);
    return true;
  }

  async function saveProfile(e: FormEvent) {
    e.preventDefault();
    const f = first.trim();
    const l = last.trim();
    const h = handle.trim().toLowerCase();
    setProfileError(null);
    if (!f) {
      setProfileError("Add your first name.");
      return;
    }
    if (!HANDLE_PATTERN.test(h)) {
      setProfileError(`Username: ${HANDLE_HINT}`);
      return;
    }
    setSavingProfile(true);
    const patch = { first_name: f, last_name: l || null, display_name: [f, l].filter(Boolean).join(" "), handle: h };
    const { error: err } = await supabase.from("profiles").update(patch).eq("id", user!.id);
    setSavingProfile(false);
    if (err) {
      setProfileError(isHandleTakenError(err) ? handleTakenMessage().replace("handle", "username") : "Something went wrong saving. Try again.");
      return;
    }
    setS((prev) => (prev ? { ...prev, ...patch } : prev));
    setHandle(h);
    flash("profile");
  }

  async function saveEmail(e: FormEvent) {
    e.preventDefault();
    const v = newEmail.trim();
    if (!v) return;
    const { error: err } = await supabase.auth.updateUser({ email: v }, { emailRedirectTo: `${window.location.origin}/auth/callback?next=/settings` });
    if (err) {
      setSigninMsg({ ok: false, text: "That email didn't work. Check it and try again." });
      return;
    }
    setEditing(null);
    setSigninMsg({ ok: true, text: `We sent a link to ${v}. Your email changes once you open it.` });
  }

  async function savePassword(e: FormEvent) {
    e.preventDefault();
    if (!passwordMeetsPolicy(pw)) {
      setSigninMsg({ ok: false, text: PASSWORD_HINT });
      return;
    }
    if (pw !== pw2) {
      setSigninMsg({ ok: false, text: "The passwords don't match." });
      return;
    }
    const { error: err } = await supabase.auth.updateUser({ password: pw });
    if (err) {
      setSigninMsg({ ok: false, text: "That password didn't work. Try another." });
      return;
    }
    setEditing(null);
    setPw("");
    setPw2("");
    setSigninMsg({ ok: true, text: "Password changed." });
  }

  async function saveHome() {
    if (!homeText.trim()) return;
    setHomeBusy(true);
    setHomeError(null);
    try {
      const cityState =
        homeText === CURRENT_LOCATION_LABEL && homeCoords ? await reverseGeocodeCityState(homeCoords) : await forwardGeocodeCityState(homeText);
      if (!cityState || (!cityState.city && !cityState.state)) {
        setHomeError("We couldn't find a town for that. Try a ZIP code or a fuller name.");
        return;
      }
      if (await update({ home_city: cityState.city, home_state: cityState.state }, "home")) setEditingHome(false);
    } finally {
      setHomeBusy(false);
    }
  }

  async function download() {
    setDownloading(true);
    const { data, error: err } = await supabase.rpc("my_data_export");
    setDownloading(false);
    if (err || !data) {
      setError("Something went wrong making your file. Try again.");
      return;
    }
    const csv = toCsv(data as Record<string, unknown>[], [
      ["section", "Section"],
      ["list_name", "List"],
      ["name", "Name"],
      ["address", "Address"],
      ["town", "Town"],
      ["state", "State"],
      ["added", "Added"],
      ["place_id", "Place ID"],
    ]);
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = "so-much-sushi-data.csv";
    a.click();
    URL.revokeObjectURL(url);
  }

  async function signOut() {
    await supabase.auth.signOut();
    router.push("/");
    router.refresh();
  }

  async function deleteAccount() {
    setDeleteBusy(true);
    setDeleteError(null);
    const { ok } = await deleteMyAccount();
    if (!ok) {
      setDeleteBusy(false);
      setDeleteError("Something went wrong deleting your account. Nothing was removed; try again.");
      return;
    }
    await supabase.auth.signOut();
    router.push("/");
    router.refresh();
  }

  if (user === undefined) return <main className="flex-1" />;
  if (user === null) {
    return (
      <JoinPanel
        icon={<span />}
        title="Sign in to see your settings"
        body="Your name, home area, who sees your lists, and your data live here."
      />
    );
  }

  const fullName = [first.trim(), last.trim()].filter(Boolean).join(" ") || s?.display_name || "You";
  const shortName = first.trim() && last.trim() ? `${first.trim()} ${last.trim().charAt(0).toUpperCase()}.` : fullName;
  const home = [s?.home_city, s?.home_state].filter(Boolean).join(", ");
  const since = user.last_sign_in_at ? new Date(user.last_sign_in_at).toLocaleDateString("en-US", { month: "short", day: "numeric" }) : null;

  return (
    <div className="mx-auto flex w-full max-w-[1080px] flex-1 flex-wrap items-start gap-x-14 gap-y-6 px-5 pb-14 pt-8 md:px-6">
      <nav aria-label="Settings sections" className="sticky top-6 hidden w-[200px] shrink-0 flex-col gap-0.5 md:flex">
        {SECTIONS.map(([id, label]) => (
          <a key={id} href={`#${id}`} className="flex h-10 items-center rounded-lg px-3 text-[15px] font-medium text-muted hover:bg-zinc-50 hover:text-zinc-950">
            {label}
          </a>
        ))}
      </nav>

      <main className="flex min-w-0 flex-[1_1_520px] flex-col">
        <h1 className="mb-2 text-3xl font-medium tracking-tight text-zinc-950">Account settings</h1>
        {error && <p className="text-sm text-red-700">{error}</p>}
        {!s ? (
          <p className="py-10 text-sm text-muted">Loading…</p>
        ) : (
          <>
            <Section id="profile" title="Profile">
              <form onSubmit={saveProfile} className="flex flex-col gap-4">
                <div className="flex items-start gap-4">
                  <Avatar name={fullName} seed={s.handle} size={56} />
                  <div className="grid min-w-0 flex-1 gap-3 sm:grid-cols-2">
                    <label className="flex flex-col gap-1.5">
                      <span className="text-sm font-medium text-zinc-950">First name</span>
                      <input value={first} onChange={(e) => setFirst(e.target.value)} maxLength={40} autoComplete="given-name" className={fieldClass} />
                    </label>
                    <label className="flex flex-col gap-1.5">
                      <span className="text-sm font-medium text-zinc-950">Last name</span>
                      <input value={last} onChange={(e) => setLast(e.target.value)} maxLength={40} autoComplete="family-name" className={fieldClass} />
                    </label>
                    <label className="flex flex-col gap-1.5 sm:col-span-2">
                      <span className="text-sm font-medium text-zinc-950">Username</span>
                      <span className="flex items-center gap-1.5">
                        <span className="text-muted">@</span>
                        <input value={handle} onChange={(e) => setHandle(e.target.value)} maxLength={20} autoComplete="username" className={`${fieldClass} max-w-[280px]`} />
                      </span>
                      <span className="text-[13px] text-muted">How friends find you, and your page’s link.</span>
                    </label>
                  </div>
                </div>
                {profileError && <p className="text-sm text-red-700">{profileError}</p>}
                <div className="flex items-center gap-3">
                  <button type="submit" disabled={savingProfile} className={primaryButton}>
                    {savingProfile ? "Saving…" : "Save"}
                  </button>
                  <Saved show={savedKey === "profile"} />
                </div>
              </form>
              <fieldset className="flex flex-col gap-1">
                <legend className="pb-1 text-sm font-medium text-zinc-950">Name on your public lists</legend>
                {[false, true].map((full) => (
                  <label key={String(full)} className="flex min-h-11 cursor-pointer items-center gap-2.5 text-[15px] text-zinc-950">
                    <input
                      type="radio"
                      name="pubname"
                      checked={s.public_name_full === full}
                      onChange={() => update({ public_name_full: full }, "pubname")}
                      className="h-5 w-5 accent-zinc-950"
                    />
                    {full ? fullName : shortName}
                    <span className="text-muted">{full ? "full name" : "first name and last initial"}</span>
                  </label>
                ))}
                <p className="flex items-center gap-3 text-[13px] text-muted">
                  Friends always see your full name. <Saved show={savedKey === "pubname"} />
                </p>
              </fieldset>
            </Section>

            <Section id="signin" title="Sign-in">
              <div className="flex flex-col">
                <div className="flex flex-wrap items-center gap-4 border-b border-[#f0f0f0] py-2.5">
                  <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="text-sm text-muted">Email</span>
                    <span className="flex flex-wrap items-center gap-2 text-base text-zinc-950">
                      {user.email}
                      {user.email_confirmed_at && (
                        <span className="inline-flex items-center gap-1 text-[13px] text-friends-ink">
                          <svg viewBox="0 0 24 24" width={14} height={14} fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                            <path d="M5 12l5 5l10 -10" />
                          </svg>
                          Confirmed
                        </span>
                      )}
                    </span>
                    <span className="text-[13px] text-muted">For signing in and account notices. Never shown to anyone.</span>
                  </div>
                  <button type="button" onClick={() => { setEditing(editing === "email" ? null : "email"); setSigninMsg(null); }} className={smallButton}>
                    Change
                  </button>
                </div>
                {editing === "email" && (
                  <form onSubmit={saveEmail} className="flex flex-wrap items-end gap-2 border-b border-[#f0f0f0] py-3">
                    <label className="flex min-w-[240px] flex-1 flex-col gap-1.5">
                      <span className="text-sm font-medium text-zinc-950">New email</span>
                      <input type="email" value={newEmail} onChange={(e) => setNewEmail(e.target.value)} autoComplete="email" className={fieldClass} />
                    </label>
                    <button type="submit" className={primaryButton}>
                      Send link
                    </button>
                  </form>
                )}
                <div className="flex flex-wrap items-center gap-4 border-b border-[#f0f0f0] py-2.5">
                  <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="text-sm text-muted">Password</span>
                    <span className="text-base text-zinc-950">••••••••</span>
                  </div>
                  <button type="button" onClick={() => { setEditing(editing === "password" ? null : "password"); setSigninMsg(null); }} className={smallButton}>
                    Change
                  </button>
                </div>
                {editing === "password" && (
                  <form onSubmit={savePassword} className="flex flex-col gap-3 border-b border-[#f0f0f0] py-3">
                    <PasswordInput id="new-password" value={pw} onChange={setPw} placeholder="New password" className={fieldClass} />
                    <PasswordInput id="new-password-2" value={pw2} onChange={setPw2} placeholder="New password again" className={fieldClass} />
                    <p className="text-[13px] text-muted">{PASSWORD_HINT}</p>
                    <div>
                      <button type="submit" className={primaryButton}>
                        Change password
                      </button>
                    </div>
                  </form>
                )}
                <div className="flex flex-wrap items-center gap-4 py-2.5">
                  <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="flex items-center gap-2 text-sm text-muted">
                      Phone number
                      <span className="rounded-full bg-[#f2f2f2] px-2 py-0.5 text-xs font-medium">Soon</span>
                    </span>
                    <span className="text-[13px] text-muted">Signing in with a code by text, and friends finding you by number, come with the app.</span>
                  </div>
                </div>
                {signinMsg && (
                  <p role="status" className={`pt-2 text-sm ${signinMsg.ok ? "text-friends-ink" : "text-red-700"}`}>
                    {signinMsg.text}
                  </p>
                )}
              </div>
            </Section>

            <Section id="home" title="Home area">
              {!editingHome ? (
                <div className="flex flex-wrap items-center gap-4">
                  <span className="flex min-w-0 flex-1 items-center gap-2.5 text-base text-zinc-950">
                    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="#5c5c5c" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                      <path d="M9 11a3 3 0 1 0 6 0a3 3 0 0 0 -6 0M17.657 16.657l-4.243 4.243a2 2 0 0 1 -2.827 0l-4.244 -4.243a8 8 0 1 1 11.314 0z" />
                    </svg>
                    {home || <span className="text-muted">Not set</span>}
                    <Saved show={savedKey === "home"} />
                  </span>
                  {home && (
                    <button type="button" disabled={homeBusy} onClick={() => update({ home_city: null, home_state: null }, "home")} className="h-10 px-2 text-sm font-medium text-muted hover:text-zinc-950 hover:underline">
                      Clear
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={() => {
                      setHomeText(home);
                      setHomeCoords(null);
                      setHomeError(null);
                      setEditingHome(true);
                    }}
                    className={smallButton}
                  >
                    {home ? "Change" : "Set"}
                  </button>
                </div>
              ) : (
                <div className="flex flex-col gap-2.5">
                  <LocationInput
                    id="home-area"
                    value={homeText}
                    onChange={(v) => {
                      setHomeText(v);
                      setHomeCoords(null);
                    }}
                    onUseMyLocation={async () => {
                      const c = await geo.requestLocation();
                      if (!c) return;
                      setHomeCoords(c);
                      setHomeText(CURRENT_LOCATION_LABEL);
                    }}
                    locating={geo.locating}
                  />
                  {(geo.geoError || homeError) && <p className="text-sm text-red-700">{geo.geoError || homeError}</p>}
                  <div className="flex gap-2">
                    <button type="button" onClick={saveHome} disabled={homeBusy || !homeText.trim()} className={primaryButton}>
                      {homeBusy ? "Saving…" : "Save"}
                    </button>
                    <button type="button" onClick={() => setEditingHome(false)} className={secondaryButton}>
                      Cancel
                    </button>
                  </div>
                </div>
              )}
              <p className="text-[13px] text-muted">
                Where searches start when you don’t type a place. We don’t keep a history of your searches or where you’ve been.
              </p>
            </Section>

            <Section id="privacy" title="Privacy">
              <div className="flex items-start gap-3">
                <span className="mt-0.5 text-favorite-ink">
                  <FavoriteIcon filled={false} size={20} />
                </span>
                <div className="flex flex-col gap-0.5">
                  <span className="text-base text-zinc-950">Your favorites</span>
                  <span className="text-sm text-muted">Your friends always see them. No one else does.</span>
                </div>
              </div>
              <div className="flex flex-wrap items-start gap-3">
                <svg className="mt-0.5 shrink-0" viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="#141414" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M9 6h11M9 12h11M9 18h11M5 6v.01M5 12v.01M5 18v.01" />
                </svg>
                <div className="flex min-w-[220px] flex-1 flex-col gap-0.5">
                  <label htmlFor="newlist" className="text-base text-zinc-950">
                    Who can see new lists
                  </label>
                  <span className="flex items-center gap-3 text-sm text-muted">
                    You can change each list on its own page. <Saved show={savedKey === "newlist"} />
                  </span>
                </div>
                <span className="relative shrink-0">
                  <select
                    id="newlist"
                    value={s.new_list_visibility}
                    onChange={(e) => update({ new_list_visibility: e.target.value as Visibility }, "newlist")}
                    className="h-11 appearance-none rounded-[10px] border border-[#dddddd] bg-white pl-3.5 pr-10 text-[15px] font-medium text-zinc-950"
                  >
                    {VISIBILITY_ORDER.map((v) => (
                      <option key={v} value={v}>
                        {VISIBILITY[v].label}
                      </option>
                    ))}
                  </select>
                  <svg className="pointer-events-none absolute right-3.5 top-3.5" viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="#141414" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <path d="M6 9l6 6l6 -6" />
                  </svg>
                </span>
              </div>
            </Section>

            <Section id="emails" title="Emails">
              <div className="flex flex-col">
                {(
                  [
                    ["email_friend_requests", "Friend requests", "When someone asks to be your friend or accepts your request"],
                    ["email_place_requests", "Places you asked us to add", "When a place you requested is added or turned down"],
                  ] as const
                ).map(([key, title, help]) => (
                  <div key={key} className="flex min-h-14 items-center gap-4 border-b border-[#f0f0f0] py-2">
                    <div className="flex flex-1 flex-col gap-0.5">
                      <span className="text-base text-zinc-950">{title}</span>
                      <span className="text-[13px] text-muted">{help}</span>
                    </div>
                    <Switch on={s[key]} label={title} onChange={(v) => update({ [key]: v } as Partial<Settings>, "emails")} />
                  </div>
                ))}
                <div className="flex min-h-14 items-center gap-4 py-2">
                  <div className="flex flex-1 flex-col gap-0.5">
                    <span className="flex items-center gap-2 text-base text-muted">
                      Changes to your favorite places
                      <span className="rounded-full bg-[#f2f2f2] px-2 py-0.5 text-xs font-medium">Soon</span>
                    </span>
                    <span className="text-[13px] text-[#707070]">New hours, a move or a closing</span>
                  </div>
                  <Switch on={false} label="Changes to your favorite places (coming soon)" disabled />
                </div>
              </div>
              <p className="flex items-center gap-3 text-[13px] text-muted">
                We don’t send these emails yet; your choices are kept for when we do. Account emails, such as confirming a new
                address, are always sent. <Saved show={savedKey === "emails"} />
              </p>
            </Section>

            <Section id="data" title="Your data">
              <div className="flex flex-wrap items-center gap-4">
                <p className="min-w-[260px] flex-1 text-sm text-muted">
                  Download your favorites, lists and friends as a file you can open in a spreadsheet.
                </p>
                <button type="button" onClick={download} disabled={downloading} className={`${smallButton} h-11 gap-2`}>
                  <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2 -2v-2M7 11l5 5l5 -5M12 4v12" />
                  </svg>
                  {downloading ? "Preparing…" : "Download"}
                </button>
              </div>
            </Section>

            <Section id="account" title="Sign out or delete">
              <div className="flex flex-wrap items-center gap-4">
                <p className="min-w-[260px] flex-1 text-sm text-muted">
                  Signed in as {user.email}
                  {since ? `, last signed in ${since}` : ""}.
                </p>
                <button type="button" onClick={signOut} className={`${smallButton} h-11`}>
                  Sign out
                </button>
              </div>
              <div className="flex flex-wrap items-center gap-4 rounded-xl border border-[#f1c9c9] p-4">
                <div className="flex min-w-[260px] flex-1 flex-col gap-1">
                  <span className="text-base font-medium text-zinc-950">Delete your account</span>
                  <span className="text-sm text-muted">
                    Removes your favorites, lists and friends for good. Places you asked us to add stay in the directory without your name.
                  </span>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setDeleting(true);
                    setConfirmText("");
                    setDeleteError(null);
                  }}
                  className="inline-flex h-11 items-center rounded-[10px] border border-[#b42318] bg-white px-4 text-[15px] font-medium text-[#b42318] hover:bg-[#fef3f2]"
                >
                  Delete account
                </button>
              </div>
            </Section>
          </>
        )}
      </main>

      {deleting && (
        <Dialog title="Delete your account?" onClose={() => !deleteBusy && setDeleting(false)}>
          <p className="mt-2 text-[15px] leading-relaxed text-muted">
            This removes your favorites, lists and friends, and you won’t be able to sign in again with this email’s account. It can’t be
            undone. Download your data first if you want a copy.
          </p>
          <label className="mt-4 flex flex-col gap-1.5">
            <span className="text-sm font-medium text-zinc-950">Type DELETE to confirm</span>
            <input value={confirmText} onChange={(e) => setConfirmText(e.target.value)} autoComplete="off" className={fieldClass} />
          </label>
          {deleteError && <p className="mt-3 text-sm text-red-700">{deleteError}</p>}
          <div className="mt-5 flex justify-end gap-2">
            <button type="button" onClick={() => setDeleting(false)} disabled={deleteBusy} className={secondaryButton}>
              Keep my account
            </button>
            <button
              type="button"
              onClick={deleteAccount}
              disabled={deleteBusy || confirmText.trim() !== "DELETE"}
              className="inline-flex h-11 items-center justify-center rounded-[10px] bg-[#b42318] px-5 text-[15px] font-medium text-white hover:bg-[#912018] disabled:opacity-50"
            >
              {deleteBusy ? "Deleting…" : "Delete account"}
            </button>
          </div>
        </Dialog>
      )}
    </div>
  );
}
