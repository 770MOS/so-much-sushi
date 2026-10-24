import Link from "next/link";
import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { loadCategories } from "@/lib/adminCategories";
import { formatPhone } from "@/lib/adminFormat";
import { UUID, type AdminPlace } from "@/lib/adminPlace";
import MergeChooser from "@/components/admin/MergeChooser";
import { mergePlaces } from "../../actions";

type Candidate = { id: string; name: string; address: string | null; city: string | null; state: string | null; phone: string | null; distance_m: number };

const control = "min-h-11 w-full rounded-lg border border-neutral-300 bg-white px-2.5 text-[13px]";
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

function distance(m: number) {
  return m < 1000 ? `${m} m` : `${(m / 1609.34).toFixed(1)} mi`;
}

export default async function MergePlace({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}) {
  const { db } = await requireAdmin();
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const sp = await searchParams;
  const q = (one(sp.q) ?? "").trim();
  const withId = one(sp.with) ?? "";
  const notice = one(sp.notice);

  const res = await db.rpc("admin_get_place", { p_id: id });
  if (res.error) throw new Error(res.error.message);
  const a = res.data as AdminPlace | null;
  if (!a) notFound();

  const header = (
    <div className="flex flex-wrap items-center gap-3">
      <Link href={`/admin/places/${a.id}`} className="inline-flex min-h-11 items-center underline hover:text-orange-700">{a.name}</Link>
      <span className="text-neutral-400">/</span>
      <h1 className="text-lg font-semibold">Merge with another place</h1>
    </div>
  );
  const noticeBox = notice && <p role="status" className="rounded-lg border border-orange-200 bg-orange-50 px-3.5 py-2 text-[13px] text-orange-900">{notice}</p>;

  if (a.status === "merged" || a.status === "removed") {
    return (
      <div className="flex max-w-5xl flex-col gap-4 px-4 py-5">
        {header}
        <p className="text-[13px]">This place is {a.status} and can&apos;t be merged into. Open the place it now points to instead.</p>
      </div>
    );
  }

  // Step 2: both places chosen. Compare and pick values.
  if (UUID.test(withId) && withId !== id) {
    const [categories, rb] = await Promise.all([loadCategories(db), db.rpc("admin_get_place", { p_id: withId })]);
    if (rb.error) throw new Error(rb.error.message);
    const b = rb.data as AdminPlace | null;
    if (!b) notFound();
    return (
      <div className="flex max-w-5xl flex-col gap-4 px-4 py-5">
        {header}
        {noticeBox}
        {b.status === "merged" ? (
          <p className="text-[13px]">
            {b.name} was already merged into another place.{" "}
            {b.merged_into && <Link href={`/admin/places/${id}/merge?with=${b.merged_into}`} className="underline hover:text-orange-700">Compare with that place instead</Link>}
          </p>
        ) : (
          <form action={mergePlaces} className="flex flex-col gap-3">
            <input type="hidden" name="a" value={a.id} />
            <input type="hidden" name="b" value={b.id} />
            <p className="text-[13px] text-neutral-600">
              Pick which value to keep for each field that differs. Place B becomes a pointer to A, and its source records, stars and list entries move to A. You can undo this from either place&apos;s page.
            </p>
            <MergeChooser a={a} b={b} categories={categories} />
            <label className="flex max-w-xl flex-col gap-1 text-xs font-medium text-neutral-700">
              Note (optional)
              <input name="note" placeholder="Why, or where you checked" className={control} />
            </label>
            <div className="flex flex-wrap items-center gap-2">
              <button className="min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-4 text-[13px] font-medium text-white hover:bg-neutral-700">
                Merge B into A
              </button>
              <Link href={`/admin/places/${b.id}/merge?with=${a.id}`} className="inline-flex min-h-11 items-center rounded-lg border border-neutral-300 px-4 text-[13px] font-medium hover:bg-neutral-50">
                Keep B instead
              </Link>
              <Link href={`/admin/places/${a.id}/merge`} className="inline-flex min-h-11 items-center px-2 text-[13px] underline hover:text-orange-700">
                Pick a different place
              </Link>
            </div>
          </form>
        )}
      </div>
    );
  }

  // Step 1: find the other place.
  const { data, error } = await db.rpc("admin_merge_candidates", { p_id: id, p_q: q || null, p_limit: 20 });
  if (error) throw new Error(error.message);
  const candidates = (data ?? []) as Candidate[];
  return (
    <div className="flex max-w-3xl flex-col gap-4 px-4 py-5">
      {header}
      {noticeBox}
      <form className="flex flex-wrap items-end gap-2">
        <label className="flex min-w-64 flex-1 flex-col gap-1 text-xs font-medium text-neutral-700">
          Search by name
          <input name="q" defaultValue={q} placeholder="Leave empty to see places within 300 m" className={control} />
        </label>
        <button className="min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-4 text-[13px] font-medium hover:bg-neutral-50">Search</button>
      </form>
      <div className="rounded-xl border border-neutral-200">
        <div className="border-b border-neutral-200 bg-neutral-50 px-3.5 py-2 text-xs font-medium text-neutral-600">
          {q ? `Places named like "${q}", nearest first` : "Places within 300 m, nearest first"}
        </div>
        {candidates.length === 0 ? (
          <p className="p-3.5 text-[13px] text-neutral-600">No places found.</p>
        ) : (
          <ul className="divide-y divide-neutral-100 text-[13px]">
            {candidates.map((c) => (
              <li key={c.id}>
                <Link href={`/admin/places/${id}/merge?with=${c.id}`} className="flex min-h-11 flex-wrap items-baseline justify-between gap-x-4 gap-y-0.5 px-3.5 py-2.5 hover:bg-neutral-50">
                  <span className="flex flex-col">
                    <span className="font-medium">{c.name}</span>
                    <span className="text-neutral-600">{[c.address, c.city, c.state].filter(Boolean).join(", ")}{c.phone ? ` · ${formatPhone(c.phone)}` : ""}</span>
                  </span>
                  <span className="font-mono text-xs text-neutral-500">{distance(c.distance_m)}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
