import Link from "next/link";
import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { loadCategories } from "@/lib/adminCategories";
import type { AdminPlace } from "@/lib/adminPlace";
import MergeChooser from "@/components/admin/MergeChooser";
import { keepSeparateSelected, mergeWithChoices } from "../actions";
import type { MergeRow } from "../types";

const control = "min-h-11 w-full rounded-lg border border-neutral-300 bg-white px-2.5 text-[13px]";

export default async function ReviewOne({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}) {
  const { db } = await requireAdmin();
  const { id } = await params;
  const noticeParam = (await searchParams).notice;
  const notice = Array.isArray(noticeParam) ? noticeParam[0] : noticeParam;
  const { data, error } = await db.rpc("admin_pending_merges");
  if (error) throw new Error(error.message);
  const rows = (data ?? []) as MergeRow[];
  const index = rows.findIndex((r) => String(r.event_id) === id);
  if (index === -1) notFound();
  const m = rows[index];
  const next = rows[index + 1] ?? null;

  const [categories, ra, rb] = await Promise.all([
    loadCategories(db),
    db.rpc("admin_get_place", { p_id: m.a_id }),
    db.rpc("admin_get_place", { p_id: m.b_id }),
  ]);
  if (ra.error || rb.error) throw new Error((ra.error ?? rb.error)!.message);
  const a = ra.data as AdminPlace;
  const b = rb.data as AdminPlace;
  const returnTo = next ? `/admin/review/${next.event_id}` : "/admin/review";

  return (
    <div className="flex max-w-5xl flex-col gap-4 px-4 py-5">
      <div className="flex flex-wrap items-center gap-3">
        <Link href="/admin/review" className="inline-flex min-h-11 items-center underline hover:text-orange-700">
          Back to the list
        </Link>
        <span className="text-neutral-500">
          {index + 1} of {rows.length}
        </span>
      </div>
      {notice && <p role="status" className="rounded-lg border border-orange-200 bg-orange-50 px-3.5 py-2 text-[13px] text-orange-900">{notice}</p>}
      <h1 className="text-lg font-semibold">Are these the same place?</h1>
      <p className="text-[13px] text-neutral-600">
        If they are, pick which value to keep for each field that differs. Place B becomes a pointer to A, and its source records, stars and list entries move to A.
      </p>
      <form className="flex flex-col gap-3">
        <input type="hidden" name="id" value={m.event_id} />
        <input type="hidden" name="a" value={a.id} />
        <input type="hidden" name="b" value={b.id} />
        <input type="hidden" name="return" value={returnTo} />
        <MergeChooser a={a} b={b} categories={categories} />
        <label className="flex max-w-xl flex-col gap-1 text-xs font-medium text-neutral-700">
          Note (optional)
          <input name="note" placeholder="Why, or where you checked" className={control} />
        </label>
        <div className="flex flex-wrap items-center gap-2">
          <button formAction={mergeWithChoices} className="min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-4 text-[13px] font-medium text-white hover:bg-neutral-700">
            Same place: merge B into A
          </button>
          <button formAction={keepSeparateSelected} className="min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-4 text-[13px] font-medium hover:bg-neutral-50">
            Different places
          </button>
          {next && (
            <Link href={`/admin/review/${next.event_id}`} className="inline-flex min-h-11 items-center rounded-lg border border-neutral-300 px-4 text-[13px] font-medium hover:bg-neutral-50">
              Skip
            </Link>
          )}
          <Link href={`/admin/places/${b.id}/merge?with=${a.id}`} className="inline-flex min-h-11 items-center px-2 text-[13px] underline hover:text-orange-700">
            Keep B instead
          </Link>
        </div>
      </form>
    </div>
  );
}
