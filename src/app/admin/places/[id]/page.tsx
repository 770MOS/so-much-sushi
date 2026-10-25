import Link from "next/link";
import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { loadCategories, mainCategories } from "@/lib/adminCategories";
import { formatPhone, websiteHost } from "@/lib/adminFormat";
import TagChecklist from "@/components/admin/TagChecklist";
import { UUID, provenanceLabel, when, type AdminPlace, type HistoryItem, type PlaceMerge } from "@/lib/adminPlace";
import { savePlace, undoMerge } from "../actions";

const control = "min-h-11 w-full rounded-lg border border-neutral-300 bg-white px-2.5 text-[13px]";
const panel = "rounded-xl border border-neutral-200";
const panelHead = "border-b border-neutral-200 bg-neutral-50 px-3.5 py-2 text-xs font-medium text-neutral-600";

function show(v: unknown) {
  if (v === null || v === undefined || v === "") return "nothing";
  if (Array.isArray(v)) return v.length ? v.map((x) => String(x).split(".").pop()!.replace(/_/g, " ")).join(", ") : "none";
  if (typeof v === "object") return JSON.stringify(v);
  return String(v);
}
function describe(h: HistoryItem) {
  if (h.type === "manual_edit") return `${(h.field ?? "field").replace(/_/g, " ")}: ${show(h.old)} → ${show(h.new)}`;
  if (h.type === "merge") return h.status === "pending" ? "Possible duplicate proposed" : h.status === "rejected" ? "Possible duplicate: kept separate" : h.status === "superseded" ? "Possible duplicate: no longer needed" : "Merged with a duplicate";
  if (h.type === "unmerge") return "Merge undone";
  if (h.field === "categories") {
    const tag = String((h.new as { add_category?: string } | null)?.add_category ?? "").split(".").pop()?.replace(/_/g, " ");
    return `Tag suggestion "${tag}": ${h.status}`;
  }
  return `${h.type.replace(/_/g, " ")}${h.field ? ` (${h.field})` : ""}: ${h.status}`;
}

export default async function PlaceEditor({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}) {
  const { db } = await requireAdmin();
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const noticeParam = (await searchParams).notice;
  const notice = Array.isArray(noticeParam) ? noticeParam[0] : noticeParam;

  const [categories, res, mres] = await Promise.all([
    loadCategories(db),
    db.rpc("admin_get_place", { p_id: id }),
    db.rpc("admin_place_merges", { p_id: id }),
  ]);
  if (res.error) throw new Error(res.error.message);
  if (mres.error) throw new Error(mres.error.message);
  const p = res.data as AdminPlace | null;
  if (!p) notFound();
  const merged = p.status === "merged";
  const merges = (mres.data ?? []) as PlaceMerge[];
  const mergedBy = merges.find((m) => m.role === "merged" && !m.undone && m.other_id === p.merged_into);

  const from = (field: string) => provenanceLabel(p.provenance[field]);
  const undoButton = (m: PlaceMerge, label: string) => (
    <form action={undoMerge}>
      <input type="hidden" name="event" value={m.event_id} />
      <input type="hidden" name="here" value={p.id} />
      <button className="min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-3 text-[13px] font-medium hover:bg-neutral-50">{label}</button>
    </form>
  );
  const field = (name: string, text: string, value: string | null, prov: string, extra: Record<string, string | number> = {}) => (
    <label className="flex flex-col gap-1">
      <span className="flex flex-wrap items-baseline justify-between gap-x-3 text-xs">
        <span className="font-medium text-neutral-700">{text}</span>
        <span className="text-neutral-500">{from(prov)}</span>
      </span>
      <input name={name} defaultValue={value ?? ""} disabled={merged} className={control} {...extra} />
    </label>
  );

  return (
    <div className="flex flex-col gap-4 px-4 py-5">
      <div className="flex flex-wrap items-center gap-3">
        <Link href="/admin/places" className="inline-flex min-h-11 items-center underline hover:text-orange-700">All places</Link>
        <span className="text-neutral-400">/</span>
        <h1 className="text-lg font-semibold">{p.name}</h1>
        {p.needs_review && <span className="rounded-full border border-orange-300 bg-orange-50 px-2 py-px text-[11px] text-orange-900">Flagged for review</span>}
        {!merged && p.status !== "removed" && (
          <Link href={`/admin/places/${p.id}/merge`} className="ml-auto inline-flex min-h-11 items-center rounded-lg border border-neutral-300 bg-white px-3 text-[13px] font-medium hover:bg-neutral-50">
            Merge with another place
          </Link>
        )}
      </div>

      {notice && <p role="status" className="rounded-lg border border-orange-200 bg-orange-50 px-3.5 py-2 text-[13px] text-orange-900">{notice}</p>}
      {merged && (
        <p className="rounded-lg border border-neutral-300 bg-neutral-50 px-3.5 py-2 text-[13px]">
          This place was merged into another and can no longer be edited.{" "}
          {p.merged_into && <Link href={`/admin/places/${p.merged_into}`} className="underline hover:text-orange-700">Open the place it was merged into</Link>}
        </p>
      )}
      {merged && mergedBy && (
        <div className="flex flex-wrap items-center gap-3 text-[13px]">
          {undoButton(mergedBy, "Undo this merge")}
          <span className="text-neutral-600">Brings this place back as it was, with its source records, stars and list entries.</span>
        </div>
      )}

      <div className="flex flex-col gap-4 xl:flex-row xl:items-start">
        <form action={savePlace} className={`${panel} min-w-0 flex-[3]`}>
          <input type="hidden" name="id" value={p.id} />
          <div className={panelHead}>Details</div>
          <div className="grid grid-cols-1 gap-3.5 p-3.5 md:grid-cols-2">
            <div className="md:col-span-2">{field("name", "Name", p.name, "name", { required: "required" })}</div>
            <div className="md:col-span-2">{field("address", "Street address", p.address, "address")}</div>
            {field("city", "Town or city", p.city, "address")}
            <div className="grid grid-cols-2 gap-3.5">
              {field("state", "State", p.state, "", { maxLength: 2 })}
              {field("postal_code", "ZIP code", p.postal_code, "", { maxLength: 10 })}
            </div>
            {field("phone", "Phone", p.phone, "phone")}
            {field("website", "Website", p.website, "website")}
            <label className="flex flex-col gap-1">
              <span className="flex flex-wrap items-baseline justify-between gap-x-3 text-xs">
                <span className="font-medium text-neutral-700">Status</span>
                <span className="text-neutral-500">{from("status")}</span>
              </span>
              <select name="status" defaultValue={merged ? "" : p.status} disabled={merged} className={control}>
                <option value="active">Open</option>
                <option value="temporarily_closed">Temporarily closed</option>
                <option value="permanently_closed">Permanently closed</option>
                <option value="removed">Removed (not a food or drink place, or never existed)</option>
              </select>
            </label>
            <label className="flex flex-col gap-1">
              <span className="text-xs font-medium text-neutral-700">Main category</span>
              <select name="main_category" defaultValue={p.main_category} disabled={merged} className={control}>
                {mainCategories(categories).map((m) => (
                  <option key={m.path} value={m.path}>{m.name}</option>
                ))}
              </select>
            </label>
          </div>

          <div className={`${panelHead} border-t`}>
            Tags <span className="font-normal text-neutral-500">· {p.tags.length} set{from("categories") ? ` · ${from("categories")}` : ""}</span>
          </div>
          <div className="max-h-96 overflow-y-auto p-3.5 text-[13px]">
            <TagChecklist categories={categories} selected={p.tags} />
          </div>

          <div className="flex flex-col gap-3 border-t border-neutral-200 p-3.5">
            <label className="flex min-h-11 cursor-pointer items-center gap-2 text-[13px]">
              <input type="checkbox" name="needs_review" defaultChecked={p.needs_review} disabled={merged} className="h-4 w-4 accent-neutral-900" />
              Keep this place flagged for review
            </label>
            <label className="flex flex-col gap-1 text-xs font-medium text-neutral-700">
              Note (optional)
              <input name="note" placeholder="Why you changed it, or where you checked" disabled={merged} className={control} />
            </label>
            <div className="flex flex-wrap items-center gap-3">
              <button disabled={merged} className="min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-4 text-[13px] font-medium text-white hover:bg-neutral-700 disabled:cursor-not-allowed disabled:opacity-50">
                Save changes
              </button>
              <span className="text-xs text-neutral-600">Each changed field is recorded in the history with your email.</span>
            </div>
          </div>
        </form>

        <div className="flex min-w-0 flex-[2] flex-col gap-4">
          <section className={panel}>
            <div className={panelHead}>At a glance</div>
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 p-3.5 text-[13px]">
              <dt className="text-neutral-500">Saved by</dt>
              <dd>{p.saved.stars} {p.saved.stars === 1 ? "star" : "stars"} · on {p.saved.lists} {p.saved.lists === 1 ? "list" : "lists"}</dd>
              <dt className="text-neutral-500">Location</dt>
              <dd className="font-mono text-xs">{p.lat.toFixed(5)}, {p.lng.toFixed(5)}</dd>
              <dt className="text-neutral-500">Last changed</dt>
              <dd>{when(p.updated_at)}</dd>
              <dt className="text-neutral-500">Public page</dt>
              <dd><Link href={`/venue/${p.id}`} className="underline hover:text-orange-700">Open</Link></dd>
            </dl>
          </section>

          <section className={panel}>
            <div className={panelHead}>Source records · {p.source_records.length}</div>
            {p.source_records.length === 0 ? (
              <p className="p-3.5 text-[13px] text-neutral-600">No source record is attached to this place.</p>
            ) : (
              <ul className="divide-y divide-neutral-100 text-[13px]">
                {p.source_records.map((r) => (
                  <li key={r.id} className="flex flex-col gap-0.5 p-3.5">
                    <span className="font-medium">{r.name}</span>
                    <span className="text-neutral-600">{[r.address, formatPhone(r.phone), websiteHost(r.website)].filter(Boolean).join(" · ")}</span>
                    <span className="text-xs text-neutral-500">
                      {[r.source, r.contributor, r.license, r.category?.replace(/_/g, " "),
                        r.confidence !== null ? `confidence ${Number(r.confidence).toFixed(2)}` : null,
                        r.operating_status && r.operating_status !== "open" ? r.operating_status.replace(/_/g, " ") : null]
                        .filter(Boolean).join(" · ")}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </section>

          {merges.some((m) => m.role === "kept") && (
            <section className={panel}>
              <div className={panelHead}>Places merged into this one</div>
              <ul className="divide-y divide-neutral-100 text-[13px]">
                {merges.filter((m) => m.role === "kept").map((m) => (
                  <li key={m.event_id} className="flex flex-wrap items-center justify-between gap-3 p-3.5">
                    <span className="flex flex-col gap-0.5">
                      <Link href={`/admin/places/${m.other_id}`} className="font-medium underline hover:text-orange-700">{m.other_name}</Link>
                      <span className="text-xs text-neutral-500">
                        {[when(m.merged_at), m.merged_by, m.taken.length ? `took ${m.taken.join(", ").replace(/_/g, " ")}` : null, m.undone ? "undone" : null]
                          .filter(Boolean).join(" · ")}
                      </span>
                    </span>
                    {!m.undone && undoButton(m, "Undo")}
                  </li>
                ))}
              </ul>
            </section>
          )}

          <section className={panel}>
            <div className={panelHead}>History</div>
            {p.history.length === 0 ? (
              <p className="p-3.5 text-[13px] text-neutral-600">Nothing has changed since this place was loaded.</p>
            ) : (
              <ul className="divide-y divide-neutral-100 text-[13px]">
                {p.history.map((h) => (
                  <li key={h.id} className="flex flex-col gap-0.5 p-3.5">
                    <span>{describe(h)}</span>
                    {h.note && <span className="text-neutral-600">Note: {h.note}</span>}
                    <span className="text-xs text-neutral-500">{[when(h.at), h.by].filter(Boolean).join(" · ")}</span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      </div>
    </div>
  );
}
