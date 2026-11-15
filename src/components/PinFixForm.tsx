"use client";

import dynamic from "next/dynamic";
import { useState } from "react";
import type { MapMark, Pin } from "@/components/MapPicker";
import { GOOD_GPS_METERS, metersBetween, metersText, NOT_FROM_MAPS, PIN_AGREEMENT, PIN_HOW, type PinHow, type PinMethod, type PinPlacement } from "@/lib/pins";

// The map library needs a browser, so the map is loaded on the client only.
const MapPicker = dynamic(() => import("@/components/MapPicker"), {
  ssr: false,
  loading: () => <div className="h-72 w-full rounded-xl border border-neutral-200 bg-neutral-50" />,
});

export type PinFixValues = PinPlacement & { how: PinHow; note: string; agree: boolean };

// Moving a place's pin (2026-11-15), shared by the admin place page, the place panel and the
// review queue: the map with the pin's current spot faded, "Put the pin where I'm standing",
// how the person knows where the place is, an optional note, and for members the box that lets
// us use their correction. onSubmit returns an error to show, or null when it worked.
export default function PinFixForm({
  current,
  start,
  member,
  look,
  marks = [],
  submitLabel,
  onSubmit,
  onCancel,
  fixedHow,
}: {
  // Where the place's pin is now.
  current: { lat: number; lng: number };
  // Where the movable pin starts (the current spot unless given, e.g. a member's suggestion).
  start?: { lat: number; lng: number };
  member: boolean;
  look: "site" | "admin";
  marks?: MapMark[];
  submitLabel: string;
  onSubmit: (values: PinFixValues) => Promise<string | null>;
  onCancel?: () => void;
  // The review queue: how the member knew is already on the report, so it isn't asked.
  fixedHow?: PinHow;
}) {
  const [pin, setPin] = useState<Pin>(start ?? current);
  const [method, setMethod] = useState<PinMethod>("map");
  const [accuracy, setAccuracy] = useState<number | null>(null);
  const [how, setHow] = useState<PinHow | null>(fixedHow ?? null);
  const [note, setNote] = useState("");
  const [agree, setAgree] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const moved = pin ? metersBetween(current, pin) : 0;
  const minimum = member ? 3 : 0.5;
  const site = look === "site";
  const button = site
    ? "inline-flex h-11 items-center justify-center rounded-[10px] border border-[#dddddd] bg-white px-3.5 text-sm font-medium text-zinc-950 hover:bg-zinc-50 disabled:opacity-50"
    : undefined;
  const control = site
    ? "w-full rounded-[10px] border border-[#dddddd] bg-white px-3.5 py-2.5 text-[15px] text-zinc-950 placeholder:text-[#707070] focus:border-zinc-950 focus:outline-none"
    : "min-h-11 w-full rounded-lg border border-neutral-300 bg-white px-2.5 text-[13px]";
  const text = site ? "text-[15px]" : "text-[13px]";
  const primary = site
    ? "inline-flex h-11 items-center justify-center rounded-[10px] bg-primary px-5 text-[15px] font-medium text-white hover:bg-primary-hover disabled:opacity-50"
    : "min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-4 text-[13px] font-medium text-white hover:bg-neutral-700 disabled:cursor-not-allowed disabled:opacity-50";
  const secondary = site
    ? "inline-flex h-11 items-center justify-center rounded-[10px] border border-[#dddddd] bg-white px-5 text-[15px] font-medium text-zinc-950 hover:bg-zinc-50"
    : "min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-3.5 text-[13px] font-medium hover:bg-neutral-50";

  const hint =
    moved < minimum
      ? "Drag the pin onto the place’s front door, or tap the map there."
      : `${start && metersBetween(start, pin!) < 0.5 ? "Suggested spot" : "New spot"}: ${metersText(moved)} from where it is now${
          method === "gps" ? (accuracy !== null ? ` · from your phone, within ${Math.round(accuracy)} m` : " · from your phone") : ""
        }.`;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!pin || moved < minimum) return setError("Move the pin to the right spot first.");
    if (!how) return setError("Say how you know where the place is.");
    if (how === "other" && !note.trim()) return setError("Add a note saying how you know where the place is.");
    if (member && !agree) return setError("Tick the box to let us use your correction.");
    setPending(true);
    setError(null);
    const problem = await onSubmit({ lat: pin.lat, lng: pin.lng, method, accuracy: method === "gps" ? accuracy : null, how, note: note.trim(), agree });
    setPending(false);
    if (problem) setError(problem);
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-4">
      <MapPicker
        pin={pin}
        onPin={setPin}
        onPlaced={(m, a) => {
          setMethod(m);
          setAccuracy(a);
        }}
        locate
        locateLabel="Put the pin where I’m standing"
        marks={[{ ...current, label: "Now", tone: "current" }, ...marks]}
        heightClass={site ? "h-64 sm:h-72" : "h-80"}
        buttonClass={button}
        hint={hint}
      />
      {method === "gps" && accuracy !== null && accuracy > GOOD_GPS_METERS && moved >= minimum && (
        <p className={`${text} text-amber-800`}>Your phone’s location is rough here. Drag the pin onto the place before saving.</p>
      )}

      {!fixedHow && (
        <fieldset className="flex flex-col gap-1">
          <legend className={`mb-1 font-medium text-zinc-950 ${text}`}>How do you know where it is?</legend>
          {PIN_HOW.map((o) => (
            <label key={o.key} className={`flex min-h-11 cursor-pointer items-center gap-3 ${text} text-zinc-950`}>
              <input type="radio" name="how" value={o.key} checked={how === o.key} onChange={() => setHow(o.key)} className="h-5 w-5 shrink-0 accent-zinc-950" />
              {o.label}
            </label>
          ))}
          {member && <p className="text-[13px] text-muted">{NOT_FROM_MAPS}</p>}
        </fieldset>
      )}

      <label className={`flex flex-col gap-1.5 ${text}`}>
        <span className="font-medium text-zinc-950">Note {how === "other" ? "" : <span className="font-normal text-muted">(optional)</span>}</span>
        <input
          value={note}
          onChange={(e) => setNote(e.target.value)}
          maxLength={500}
          placeholder={member ? "For example: the entrance is around the back" : "Why you moved it, or how you checked"}
          className={control}
        />
      </label>

      {member && (
        <label className="flex cursor-pointer items-start gap-3 text-[14px] leading-snug text-zinc-950">
          <input type="checkbox" checked={agree} onChange={(e) => setAgree(e.target.checked)} className="mt-0.5 h-5 w-5 shrink-0 accent-zinc-950" />
          {PIN_AGREEMENT}
        </label>
      )}

      {error && (
        <p role="alert" className={`${text} text-red-700`}>
          {error}
        </p>
      )}
      <div className="flex flex-wrap items-center gap-2">
        <button type="submit" disabled={pending} className={primary}>
          {pending ? "Saving…" : submitLabel}
        </button>
        {onCancel && (
          <button type="button" onClick={onCancel} className={secondary}>
            Cancel
          </button>
        )}
      </div>
    </form>
  );
}
