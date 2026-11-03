"use client";

import Link from "next/link";
import PinField from "@/components/PinField";
import { useActionState, useEffect, useRef } from "react";
import type { RequestState } from "@/app/(with-sidebar)/request/actions";


export type PlaceKind = { path: string; name: string };

const input =
  "w-full rounded-lg border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50";
const labelText = "text-sm font-medium text-zinc-700 dark:text-zinc-300";
const hint = "font-normal text-zinc-500 dark:text-zinc-400";

export default function RequestPlaceForm({
  kinds,
  initialName,
  isAdmin,
  action,
}: {
  kinds: PlaceKind[];
  initialName: string;
  isAdmin: boolean;
  action: (state: RequestState, formData: FormData) => Promise<RequestState>;
}) {
  const [state, formAction, pending] = useActionState(action, { values: initialName ? { name: initialName } : {} });
  const v = state.values;
  const pin = v.lat && v.lng ? { lat: Number(v.lat), lng: Number(v.lng) } : null;
  // After sending, bring the thanks, the error or the possible matches into view
  // (on a phone the button is far below them).
  const formRef = useRef<HTMLFormElement>(null);
  useEffect(() => {
    if (state.sent || state.error || state.matches?.length) formRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [state]);
  const field = (name: string, label: string, extra: Record<string, string | number> = {}, optional = false) => (
    <label className="flex flex-col gap-2">
      <span className={labelText}>
        {label}
        {optional && <span className={hint}> (optional)</span>}
      </span>
      <input id={`request-${name}`} name={name} defaultValue={v[name] ?? ""} className={input} {...extra} />
    </label>
  );

  return (
    // key: a returned state re-renders the inputs with the values that were sent.
    <form ref={formRef} action={formAction} key={state.attempt ?? 0} className="flex scroll-mt-6 flex-col gap-6">
      {state.sent && (
        <div role="status" className="flex flex-col gap-1 rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-900 dark:border-green-900 dark:bg-green-950 dark:text-green-100">
          <p>
            Thanks. <strong>{state.sent.name}</strong> is waiting for review. You&apos;ll see what happens to it under Your requests.
          </p>
          {isAdmin && (
            <Link href={`/admin/review/requests/${state.sent.id}`} className="w-fit underline">
              Review it now
            </Link>
          )}
        </div>
      )}

      {state.error && (
        <p role="alert" className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900 dark:border-red-900 dark:bg-red-950 dark:text-red-100">
          {state.error}
        </p>
      )}

      {state.matches && state.matches.length > 0 && (
        <section className="rounded-lg border border-amber-300 bg-amber-50 text-sm dark:border-amber-800 dark:bg-amber-950">
          <h2 className="border-b border-amber-200 px-4 py-2.5 font-medium text-amber-950 dark:border-amber-900 dark:text-amber-100">
            We may already have it. Is it one of these?
          </h2>
          <ul className="divide-y divide-amber-200 dark:divide-amber-900">
            {state.matches.map((m) => (
              <li key={m.id} className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-0.5 px-4 py-2.5">
                <span className="flex flex-col">
                  <Link href={`/venue/${m.id}`} className="font-medium text-zinc-950 underline dark:text-zinc-50">
                    {m.name}
                  </Link>
                  <span className="text-zinc-700 dark:text-zinc-300">{[m.address, m.city, m.state].filter(Boolean).join(", ")}</span>
                </span>
                <span className="text-xs text-zinc-600 dark:text-zinc-400">{m.distance_m} m from your pin</span>
              </li>
            ))}
          </ul>
          <label className="flex min-h-11 cursor-pointer items-center gap-2 border-t border-amber-200 px-4 text-zinc-900 dark:border-amber-900 dark:text-zinc-100">
            <input type="checkbox" name="none_match" className="h-4 w-4" />
            None of these is the place: send my request
          </label>
        </section>
      )}

      {field("name", "Name", { required: "required", maxLength: 200, placeholder: "What the place is called" })}

      <fieldset className="flex flex-col gap-2">
        <legend className={`${labelText} mb-2`}>What kind of place?</legend>
        <div className="flex flex-wrap gap-2">
          {kinds.map((k) => (
            <label
              key={k.path}
              className="flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border border-zinc-300 px-3.5 text-sm text-zinc-800 has-[:checked]:border-primary has-[:checked]:bg-primary has-[:checked]:text-white has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-zinc-400 dark:border-zinc-700 dark:text-zinc-200"
            >
              <input type="radio" name="main_category" value={k.path} defaultChecked={v.main_category === k.path} required className="sr-only" />
              {k.name}
            </label>
          ))}
        </div>
      </fieldset>

      <div className="flex flex-col gap-2">
        <span className={labelText}>Where is it?</span>
        <p className="text-sm text-zinc-500 dark:text-zinc-400">
          If you&apos;re there now, use your location. Otherwise type the address below and find it, then click the exact spot.
        </p>
        <PinField
          initial={pin}
          locate
          startAtLastSearch
          addressFieldIds={["request-address", "request-city", "request-state", "request-postal_code"]}
        />
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="sm:col-span-2">{field("address", "Street address", { maxLength: 300 }, true)}</div>
        {field("city", "Town or city", { maxLength: 100 }, true)}
        <div className="grid grid-cols-2 gap-4">
          {field("state", "State", { maxLength: 2, placeholder: "VA" }, true)}
          {field("postal_code", "ZIP", { maxLength: 10 }, true)}
        </div>
        {field("phone", "Phone", { maxLength: 40, type: "tel" }, true)}
        {field("website", "Website", { maxLength: 500, placeholder: "The place's own site" }, true)}
      </div>

      <label className="flex flex-col gap-2">
        <span className={labelText}>
          Anything else? <span className={hint}>(optional)</span>
        </span>
        <textarea
          name="note"
          defaultValue={v.note ?? ""}
          maxLength={1000}
          rows={3}
          placeholder="For example: opened last month, or it's inside the food hall"
          className={input}
        />
      </label>

      <label className="flex cursor-pointer items-start gap-3 text-sm text-zinc-700 dark:text-zinc-300">
        <input type="checkbox" name="own_knowledge" defaultChecked={v.own_knowledge === "on"} required className="mt-0.5 h-4 w-4 shrink-0" />
        <span>
          These details come from my own visit, the place&apos;s sign or menu, or its own website, not copied from Google Maps, Yelp or another app.
        </span>
      </label>

      <div className="flex flex-col gap-2">
        <button
          disabled={pending}
          className="w-full rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
        >
          {pending ? "Sending…" : "Send request"}
        </button>
        <p className="text-xs text-zinc-500 dark:text-zinc-400">
          We check every request before a place is added, and may use the details you send in the directory.
        </p>
      </div>
    </form>
  );
}
