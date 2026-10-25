"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import { useActionState } from "react";
import { mainCategories, type Category } from "@/lib/adminCategories";
import { formatPhone } from "@/lib/adminFormat";
import TagChecklist from "@/components/admin/TagChecklist";
import type { AddPlaceState } from "@/app/admin/places/actions";

// The map library needs a browser, so the picker is loaded on the client only.
const MapPicker = dynamic(() => import("@/components/admin/MapPicker"), {
  ssr: false,
  loading: () => <div className="h-80 w-full rounded-xl border border-neutral-200 bg-neutral-50" />,
});

const control = "min-h-11 w-full rounded-lg border border-neutral-300 bg-white px-2.5 text-[13px]";
const panel = "rounded-xl border border-neutral-200";
const panelHead = "border-b border-neutral-200 bg-neutral-50 px-3.5 py-2 text-xs font-medium text-neutral-600";

export default function AddPlaceForm({
  categories,
  action,
}: {
  categories: Category[];
  action: (state: AddPlaceState, formData: FormData) => Promise<AddPlaceState>;
}) {
  const [state, formAction, pending] = useActionState(action, { values: {} });
  const v = state.values;
  const pin = v.lat && v.lng ? { lat: Number(v.lat), lng: Number(v.lng) } : null;
  const field = (name: string, label: string, extra: Record<string, string | number> = {}) => (
    <label className="flex flex-col gap-1">
      <span className="text-xs font-medium text-neutral-700">{label}</span>
      <input id={`add-${name}`} name={name} defaultValue={v[name] ?? ""} className={control} {...extra} />
    </label>
  );

  return (
    // key: a returned state re-renders the inputs with the values that were sent.
    <form action={formAction} key={state.attempt ?? 0} className="flex flex-col gap-4">
      {state.error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 px-3.5 py-2 text-[13px] text-red-900">{state.error}</p>}

      {state.similar && state.similar.length > 0 && (
        <section className="rounded-xl border border-orange-300 bg-orange-50">
          <div className="border-b border-orange-200 px-3.5 py-2 text-[13px] font-medium text-orange-900">
            These places might already be the one you&apos;re adding
          </div>
          <ul className="divide-y divide-orange-200 text-[13px]">
            {state.similar.map((s) => (
              <li key={s.id} className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-0.5 px-3.5 py-2.5">
                <span className="flex flex-col">
                  <Link href={`/admin/places/${s.id}`} target="_blank" className="font-medium underline hover:text-orange-700">{s.name}</Link>
                  <span className="text-neutral-700">{[s.address, s.city, s.state].filter(Boolean).join(", ")}{s.phone ? ` · ${formatPhone(s.phone)}` : ""}</span>
                </span>
                <span className="text-xs text-neutral-600">{s.reason} · {s.distance_m} m away</span>
              </li>
            ))}
          </ul>
          <label className="flex min-h-11 cursor-pointer items-center gap-2 border-t border-orange-200 px-3.5 text-[13px]">
            <input type="checkbox" name="confirm" className="h-4 w-4 accent-neutral-900" />
            None of these is the same place: add it anyway
          </label>
        </section>
      )}

      <div className="flex flex-col gap-4 xl:flex-row xl:items-start">
        <section className={`${panel} min-w-0 flex-[3]`}>
          <div className={panelHead}>Details</div>
          <div className="grid grid-cols-1 gap-3.5 p-3.5 md:grid-cols-2">
            <div className="md:col-span-2">{field("name", "Name", { required: "required" })}</div>
            <div className="md:col-span-2">{field("address", "Street address")}</div>
            {field("city", "Town or city")}
            <div className="grid grid-cols-2 gap-3.5">
              {field("state", "State", { maxLength: 2 })}
              {field("postal_code", "ZIP code", { maxLength: 10 })}
            </div>
            {field("phone", "Phone")}
            {field("website", "Website")}
            <label className="flex flex-col gap-1">
              <span className="text-xs font-medium text-neutral-700">Main category</span>
              <select name="main_category" defaultValue={v.main_category ?? ""} required className={control}>
                <option value="" disabled>Choose one</option>
                {mainCategories(categories).map((m) => (
                  <option key={m.path} value={m.path}>{m.name}</option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1">
              <span className="text-xs font-medium text-neutral-700">Status</span>
              <select name="status" defaultValue={v.status ?? "active"} className={control}>
                <option value="active">Open</option>
                <option value="temporarily_closed">Temporarily closed</option>
                <option value="permanently_closed">Permanently closed</option>
              </select>
            </label>
          </div>
          <div className={`${panelHead} border-t`}>Map pin</div>
          <div className="p-3.5">
            <MapPicker initial={pin} addressFieldIds={["add-address", "add-city", "add-state", "add-postal_code"]} />
          </div>
        </section>

        <section className={`${panel} min-w-0 flex-[2]`}>
          <div className={panelHead}>Tags (optional)</div>
          <div className="max-h-[32rem] overflow-y-auto p-3.5 text-[13px]">
            <TagChecklist categories={categories} selected={state.tags ?? []} />
          </div>
        </section>
      </div>

      <div className="flex flex-col gap-3">
        <label className="flex max-w-xl flex-col gap-1 text-xs font-medium text-neutral-700">
          Note (optional)
          <input name="note" defaultValue={v.note ?? ""} placeholder="How you know about it, or where you checked" className={control} />
        </label>
        <div className="flex flex-wrap items-center gap-3">
          <button disabled={pending} className="min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-4 text-[13px] font-medium text-white hover:bg-neutral-700 disabled:opacity-50">
            {pending ? "Saving…" : "Add place"}
          </button>
          <span className="text-xs text-neutral-600">Everything you enter is recorded as edited by hand, so sources can suggest changes but never overwrite it.</span>
        </div>
      </div>
    </form>
  );
}
