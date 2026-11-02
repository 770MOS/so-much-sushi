import Link from "next/link";
import { requireAdmin } from "@/lib/admin";
import { loadCategories, mainCategories } from "@/lib/adminCategories";
import { formatPhone, websiteHost } from "@/lib/adminFormat";
import SelectAll from "@/components/admin/SelectAll";
import SelectedCount from "@/components/admin/SelectedCount";
import StateTownSelect from "@/components/admin/StateTownSelect";
import TagChecklist from "@/components/admin/TagChecklist";
import { bulkEdit } from "./actions";

const PAGE = 50;

type PlaceRow = {
  id: string; name: string; address: string | null; city: string | null; state: string | null;
  postal_code: string | null; phone: string | null; website: string | null; status: string;
  needs_review: boolean; main_category: string; tags: string[]; total: number;
  added_by_hand: boolean; source_records: number; last_checked: string | null;
};
type Option = { value: string; count: number };
type Town = { state: string | null; value: string; count: number };

const th = "whitespace-nowrap border-b border-l border-neutral-200 px-3 py-2 text-left font-medium text-neutral-600 first:border-l-0";
const td = "border-b border-l border-neutral-100 px-3 py-2 align-top first:border-l-0";
const control = "min-h-11 rounded-lg border border-neutral-300 bg-white px-2.5 text-[13px]";
const label = "flex flex-col gap-1 text-xs font-medium text-neutral-600";

const STATUS: Record<string, string> = {
  active: "Open",
  temporarily_closed: "Temporarily closed",
  permanently_closed: "Permanently closed",
  removed: "Removed",
  merged: "Merged",
};

function one(v: string | string[] | undefined) {
  return (Array.isArray(v) ? v[0] : v) || undefined;
}
function many(v: string | string[] | undefined) {
  return v === undefined ? [] : Array.isArray(v) ? v : [v];
}

export default async function AllPlaces({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}) {
  const { db } = await requireAdmin();
  const params = await searchParams;
  const q = one(params.q);
  const state = one(params.state);
  const city = one(params.city);
  const zip = one(params.zip);
  const main = one(params.main);
  const status = one(params.status);
  const flag = one(params.flag); // "review" | "untagged" | "hand" | "unconfirmed" | "stale"
  const tags = many(params.tag);
  const page = Math.max(1, Number(one(params.page)) || 1);
  const notice = one(params.notice);

  const [categories, filtersRes, placesRes] = await Promise.all([
    loadCategories(db),
    db.rpc("admin_place_filters", { p_state: null }),
    db.rpc("admin_search_places", {
      p_q: q ?? null, p_state: state ?? null, p_city: city ?? null, p_zip: zip ?? null,
      p_main: main ?? null, p_tags: tags.length ? tags : null, p_status: status ?? null,
      p_needs_review: flag === "review" ? true : null, p_untagged: flag === "untagged" ? true : null,
      p_origin: flag === "hand" || flag === "unconfirmed" || flag === "stale" ? flag : null,
      p_limit: PAGE, p_offset: (page - 1) * PAGE,
    }),
  ]);
  if (filtersRes.error) throw new Error(filtersRes.error.message);
  if (placesRes.error) throw new Error(placesRes.error.message);
  const filters = filtersRes.data as { states: Option[]; cities: Option[]; towns?: Town[] };
  const rows = (placesRes.data ?? []) as PlaceRow[];
  const total = rows.length ? Number(rows[0].total) : 0;
  const pages = Math.max(1, Math.ceil(total / PAGE));

  const pageLink = (n: number) => {
    const sp = new URLSearchParams();
    for (const [k, v] of Object.entries({ q, state, city, zip, main, status, flag })) if (v) sp.set(k, v);
    tags.forEach((t) => sp.append("tag", t));
    if (n > 1) sp.set("page", String(n));
    const s = sp.toString();
    return `/admin/places${s ? `?${s}` : ""}`;
  };
  const filtered = Boolean(q || state || city || zip || main || status || flag || tags.length);

  return (
    <>
      <form method="get" className="relative flex flex-wrap items-end gap-2 border-b border-neutral-200 px-4 py-2.5">
        <h1 className="mr-2 self-center text-base font-semibold">All places</h1>
        <Link href="/admin/places/new" className="order-last ml-auto inline-flex min-h-11 items-center self-center rounded-lg bg-neutral-900 px-3 text-[13px] font-medium text-white hover:bg-neutral-700">
          Add a place
        </Link>
        <label className={label}>
          Name
          <input type="search" name="q" defaultValue={q} placeholder="Contains…" className={`${control} w-44`} />
        </label>
        <StateTownSelect
          states={filters.states}
          towns={filters.towns ?? []}
          state={state}
          city={city}
          controlClass={control}
          labelClass={label}
        />
        <label className={label}>
          ZIP code
          <input type="text" name="zip" defaultValue={zip} inputMode="numeric" maxLength={5} placeholder="22201" className={`${control} w-24`} />
        </label>
        <label className={label}>
          Main category
          <select name="main" defaultValue={main ?? ""} className={control}>
            <option value="">Any</option>
            {mainCategories(categories).map((m) => (
              <option key={m.path} value={m.path}>{m.name}</option>
            ))}
          </select>
        </label>
        <div className={label}>
          <span id="tags-label">Tags</span>
          <details>
            <summary aria-labelledby="tags-label" className={`${control} flex cursor-pointer list-none items-center gap-2`}>
              {tags.length ? `${tags.length} selected` : "Any"}
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M6 9l6 6l6 -6" /></svg>
            </summary>
            <div className="absolute left-4 top-full z-10 -mt-1 max-h-[60vh] w-[min(40rem,calc(100%-2rem))] overflow-y-auto rounded-xl border border-neutral-200 bg-white p-3 text-[13px] font-normal text-neutral-900 shadow-lg">
              <p className="mb-2 text-xs text-neutral-500">A place is shown if it has any ticked tag, or a tag beneath one.</p>
              <TagChecklist categories={categories} selected={tags} />
            </div>
          </details>
        </div>
        <label className={label}>
          Status
          <select name="status" defaultValue={status ?? ""} className={control}>
            <option value="">All except merged</option>
            {Object.entries(STATUS).map(([v, l]) => (
              <option key={v} value={v}>{l}</option>
            ))}
          </select>
        </label>
        <label className={label}>
          Show only
          <select name="flag" defaultValue={flag ?? ""} className={control}>
            <option value="">Everything</option>
            <option value="review">Flagged for review</option>
            <option value="untagged">No tags yet</option>
            <option value="hand">Added by hand</option>
            <option value="unconfirmed">No source has it</option>
            <option value="stale">No source, not checked in 6 months</option>
          </select>
        </label>
        <button className="min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-3.5 text-[13px] font-medium text-white hover:bg-neutral-700">Apply</button>
        {filtered && (
          <Link href="/admin/places" className="inline-flex min-h-11 items-center px-2 text-[13px] underline hover:text-orange-700">Clear</Link>
        )}
      </form>

      {notice && <p role="status" className="mx-4 mt-3 rounded-lg border border-orange-200 bg-orange-50 px-3.5 py-2 text-[13px] text-orange-900">{notice}</p>}

      {rows.length === 0 ? (
        <p className="px-4 py-10 text-neutral-600">No places match these filters.</p>
      ) : (
        <form action={bulkEdit} className="flex flex-col">
          <input type="hidden" name="return" value={pageLink(page)} />
          {Object.entries({ q, state, city, zip, main, status, flag }).map(([k, v]) => v && <input key={k} type="hidden" name={`f_${k}`} value={v} />)}
          {tags.map((tg) => <input key={tg} type="hidden" name="f_tag" value={tg} />)}
          <div className="relative flex flex-wrap items-end gap-2 border-b border-neutral-200 bg-neutral-50 px-4 py-2.5">
            <div className="mr-2 flex min-h-11 flex-col justify-center">
              <span className="text-xs font-medium text-neutral-600">Bulk edit</span>
              <SelectedCount total={total} />
            </div>
            <label className={label}>
              Main category
              <select name="b_main" defaultValue="" className={control}>
                <option value="">No change</option>
                {mainCategories(categories).map((m) => (
                  <option key={m.path} value={m.path}>{m.name}</option>
                ))}
              </select>
            </label>
            <label className={label}>
              Status
              <select name="b_status" defaultValue="" className={control}>
                <option value="">No change</option>
                {Object.entries(STATUS).filter(([v]) => v !== "merged").map(([v, l]) => (
                  <option key={v} value={v}>{l}</option>
                ))}
              </select>
            </label>
            <label className={label}>
              Review flag
              <select name="b_review" defaultValue="" className={control}>
                <option value="">No change</option>
                <option value="true">Flag for review</option>
                <option value="false">Clear the flag</option>
              </select>
            </label>
            {[["b_add_tag", "Add tags"], ["b_remove_tag", "Remove tags"]].map(([name, text]) => (
              <div key={name} className={label}>
                <span id={`${name}-label`}>{text}</span>
                <details>
                  <summary aria-labelledby={`${name}-label`} className={`${control} flex cursor-pointer list-none items-center gap-2`}>
                    Choose
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M6 9l6 6l6 -6" /></svg>
                  </summary>
                  <div className="absolute left-4 top-full z-10 -mt-1 max-h-[60vh] w-[min(40rem,calc(100%-2rem))] overflow-y-auto rounded-xl border border-neutral-200 bg-white p-3 text-[13px] font-normal text-neutral-900 shadow-lg">
                    <TagChecklist categories={categories} selected={[]} name={name} />
                  </div>
                </details>
              </div>
            ))}
            <label className="flex min-h-11 cursor-pointer items-center gap-2 self-end text-[13px]">
              <input type="checkbox" name="b_checked" className="h-4 w-4 accent-neutral-900" />
              Mark as checked
            </label>
            <label className={label}>
              Note (optional)
              <input name="b_note" placeholder="Why" className={`${control} w-48`} />
            </label>
            {total > rows.length && (
              <label className="flex min-h-11 cursor-pointer items-center gap-2 self-end text-[13px]">
                <input type="checkbox" name="scope" value="all" className="h-4 w-4 accent-neutral-900" />
                All {total.toLocaleString("en-US")} matching, not just this page
              </label>
            )}
            <button className="min-h-11 cursor-pointer self-end rounded-lg bg-neutral-900 px-3.5 text-[13px] font-medium text-white hover:bg-neutral-700">Apply to selected</button>
          </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1040px] border-collapse text-[13px]">
            <thead>
              <tr className="bg-neutral-50">
                <th className={`${th} w-11 px-0`}><SelectAll /></th>
                <th className={th}>Name</th>
                <th className={th}>Address</th>
                <th className={th}>Town</th>
                <th className={th}>State</th>
                <th className={th}>ZIP</th>
                <th className={th}>Main</th>
                <th className={th}>Tags</th>
                <th className={th}>Phone</th>
                <th className={th}>Website</th>
                <th className={th}>Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="hover:bg-neutral-50">
                  <td className={`${td} px-0`}>
                    <label className="flex min-h-11 min-w-11 cursor-pointer items-center justify-center">
                      <input type="checkbox" name="id" value={r.id} aria-label={`Select ${r.name}`} className="h-4 w-4 accent-neutral-900" />
                    </label>
                  </td>
                  <td className={td}>
                    <Link href={`/admin/places/${r.id}`} className="inline-flex min-h-11 items-center font-medium underline decoration-neutral-300 hover:text-orange-700">
                      {r.name}
                    </Link>
                    {r.needs_review && <span className="ml-2 whitespace-nowrap rounded-full border border-orange-300 bg-orange-50 px-1.5 py-px text-[11px] text-orange-900">Review</span>}
                    {r.added_by_hand && <span className="ml-2 whitespace-nowrap rounded-full border border-neutral-300 bg-white px-1.5 py-px text-[11px] text-neutral-700">Hand</span>}
                    {r.source_records === 0 && (
                      <span title={r.last_checked ? `Last checked ${new Date(r.last_checked).toLocaleDateString("en-US")}` : "Never checked"}
                            className="ml-2 whitespace-nowrap rounded-full border border-sky-300 bg-sky-50 px-1.5 py-px text-[11px] text-sky-900">No source</span>
                    )}
                  </td>
                  <td className={td}>{r.address}</td>
                  <td className={`${td} whitespace-nowrap`}>{r.city}</td>
                  <td className={td}>{r.state}</td>
                  <td className={`${td} font-mono text-xs`}>{r.postal_code?.slice(0, 5)}</td>
                  <td className={`${td} whitespace-nowrap`}>{r.main_category}</td>
                  <td className={td}>{r.tags.length ? r.tags.join(", ") : <span className="text-neutral-400">None</span>}</td>
                  <td className={`${td} whitespace-nowrap font-mono text-xs`}>{formatPhone(r.phone)}</td>
                  <td className={td}>{websiteHost(r.website)}</td>
                  <td className={`${td} whitespace-nowrap ${r.status === "active" ? "" : "text-neutral-500"}`}>{STATUS[r.status] ?? r.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        </form>
      )}

      <div className="mt-auto flex flex-wrap items-center justify-between gap-2 border-t border-neutral-200 px-4 py-2 text-xs text-neutral-600">
        <span>
          {total.toLocaleString("en-US")} {total === 1 ? "place" : "places"}
          {total > 0 ? ` · showing ${((page - 1) * PAGE + 1).toLocaleString("en-US")} to ${Math.min(page * PAGE, total).toLocaleString("en-US")}` : ""}
        </span>
        <span className="flex items-center gap-2">
          {page > 1 && <Link href={pageLink(page - 1)} className="inline-flex min-h-11 items-center rounded-lg border border-neutral-300 px-3 hover:bg-neutral-50">Previous</Link>}
          <span>Page {page} of {pages.toLocaleString("en-US")}</span>
          {page < pages && <Link href={pageLink(page + 1)} className="inline-flex min-h-11 items-center rounded-lg border border-neutral-300 px-3 hover:bg-neutral-50">Next</Link>}
        </span>
      </div>
    </>
  );
}
