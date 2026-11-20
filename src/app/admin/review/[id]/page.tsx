import Link from "next/link";
import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { loadCategories } from "@/lib/adminCategories";
import type { AdminPlace } from "@/lib/adminPlace";
import MergeChooser from "@/components/admin/MergeChooser";
import { keepSeparateSelected, mergeWithChoices } from "../actions";
import type { MergeRow } from "../types";
import { GROUP } from "../groups";

type Proposal = MergeRow & { review_group: string | null; group_position: number | null; group_total: number | null; next_event_id: number | null };

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
  if (!/^\d+$/.test(id)) notFound();
  const { data, error } = await db.rpc("admin_get_merge_proposal", { p_event: Number(id) });
  if (error) throw new Error(error.message);
  const m = ((data ?? []) as Proposal[])[0];
  if (!m) notFound();
  const groupPage = m.review_group ? `/admin/review?group=${m.review_group}` : "/admin/review";

  const [categories, ra, rb] = await Promise.all([
    loadCategories(db),
    db.rpc("admin_get_place", { p_id: m.a_id }),
    db.rpc("admin_get_place", { p_id: m.b_id }),
  ]);
  if (ra.error || rb.error) throw new Error((ra.error ?? rb.error)!.message);
  const a = ra.data as AdminPlace;
  const b = rb.data as AdminPlace;
  // After deciding, the next pair in the same group (or the group's list when this was the last).
  const returnTo = m.next_event_id ? `/admin/review/${m.next_event_id}` : groupPage;

  return (
    <div className="flex max-w-5xl flex-col gap-4 px-4 py-5">
      <div className="flex flex-wrap items-center gap-3">
        <Link href={groupPage} className="inline-flex min-h-11 items-center underline hover:text-orange-700">
          Back to {m.review_group && GROUP[m.review_group] ? `“${GROUP[m.review_group].title}”` : "the list"}
        </Link>
        {m.group_position && (
          <span className="text-neutral-500">
            {Number(m.group_position).toLocaleString("en-US")} of {Number(m.group_total).toLocaleString("en-US")}
          </span>
        )}
      </div>
      {notice && <p role="status" className="rounded-lg border border-orange-200 bg-orange-50 px-3.5 py-2 text-[13px] text-orange-900">{notice}</p>}
      <h1 className="text-lg font-semibold">Are these the same place?</h1>
      <p className="text-[13px] text-neutral-600">
        If they are, pick which value to keep for each field that differs. Place B becomes a pointer to A, and its source records, favorites and list entries move to A.
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
          {m.next_event_id && (
            <Link href={`/admin/review/${m.next_event_id}`} className="inline-flex min-h-11 items-center rounded-lg border border-neutral-300 px-4 text-[13px] font-medium hover:bg-neutral-50">
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
