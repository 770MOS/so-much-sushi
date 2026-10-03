import Link from "next/link";
import { requireAdmin } from "@/lib/admin";
import { place, websiteHost } from "@/lib/adminFormat";
import Compare from "@/components/admin/Compare";
import SelectAll from "@/components/admin/SelectAll";
import {
  acceptTagsSelected,
  acceptTickedRejectRest,
  keepSeparateSelected,
  mergeSelected,
  rejectTagsSelected,
} from "./actions";
import type { MergeRow, TagCount, TagRow } from "./types";

const TAG_PAGE = 200;

const th = "whitespace-nowrap border-b border-l border-neutral-200 px-3 py-2 text-left font-medium text-neutral-600 first:border-l-0";
const td = "border-b border-l border-neutral-100 px-3 py-2 align-top first:border-l-0";
const primary = "min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-3.5 text-[13px] font-medium text-white hover:bg-neutral-700";
const secondary = "min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-3.5 text-[13px] font-medium hover:bg-neutral-50";

function one(v: string | string[] | undefined) {
  return Array.isArray(v) ? v[0] : v;
}

export default async function ReviewQueue({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}) {
  const { db } = await requireAdmin();
  const params = await searchParams;
  const type = one(params.type) === "tags" ? "tags" : "merges";
  const tag = one(params.tag) ?? null;
  const notice = one(params.notice);

  const [mergesRes, countsRes] = await Promise.all([db.rpc("admin_pending_merges"), db.rpc("admin_pending_tag_counts")]);
  if (mergesRes.error) throw new Error(mergesRes.error.message);
  if (countsRes.error) throw new Error(countsRes.error.message);
  const merges = (mergesRes.data ?? []) as MergeRow[];
  const counts = ((countsRes.data ?? []) as TagCount[]).map((c) => ({ ...c, pending: Number(c.pending) }));
  const tagTotal = counts.reduce((sum, c) => sum + c.pending, 0);

  let tags: TagRow[] = [];
  if (type === "tags") {
    const res = await db.rpc("admin_pending_tags", { p_tag: tag, p_limit: TAG_PAGE, p_offset: 0 });
    if (res.error) throw new Error(res.error.message);
    tags = (res.data ?? []) as TagRow[];
  }

  const here = type === "tags" ? `/admin/review?type=tags${tag ? `&tag=${encodeURIComponent(tag)}` : ""}` : "/admin/review";
  const tab = (active: boolean) =>
    `flex min-h-11 items-center gap-2 rounded-lg border px-3 text-[13px] ${
      active ? "border-neutral-900 bg-neutral-900 text-white" : "border-neutral-300 bg-white hover:bg-neutral-50"
    }`;

  return (
    <>
      <div className="flex flex-wrap items-center gap-2 border-b border-neutral-200 px-4 py-2.5">
        <h1 className="mr-2 text-base font-semibold">Review queue</h1>
        <Link href="/admin/review" className={tab(type === "merges")}>
          Possible duplicates <span className="font-mono text-xs">{merges.length}</span>
        </Link>
        <Link href="/admin/review?type=tags" className={tab(type === "tags")}>
          Tag suggestions <span className="font-mono text-xs">{tagTotal}</span>
        </Link>
      </div>

      {notice && (
        <p role="status" className="border-b border-neutral-200 bg-orange-50 px-4 py-2 text-[13px] text-orange-900">
          {notice}
        </p>
      )}

      {type === "merges" ? (
        merges.length === 0 ? (
          <p className="px-4 py-10 text-neutral-600">No possible duplicates are waiting.</p>
        ) : (
          <form>
            <input type="hidden" name="return" value={here} />
            <div className="flex flex-wrap items-center gap-2 border-b border-neutral-200 bg-neutral-50 px-4 py-2">
              <button formAction={mergeSelected} className={primary}>
                Same place: merge ticked
              </button>
              <button formAction={keepSeparateSelected} className={secondary}>
                Different places
              </button>
              <span className="text-xs text-neutral-600">
                A merge keeps place A, turns B into a redirect and moves saved lists across. Each merge is recorded separately.
              </span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[980px] border-collapse text-[13px]">
                <thead>
                  <tr className="bg-neutral-50">
                    <th className={th}><SelectAll /></th>
                    <th className={th}>Place A (kept)</th>
                    <th className={th}>Place B</th>
                    <th className={th}>Town</th>
                    <th className={th}>Apart</th>
                    <th className={th}>Phone</th>
                    <th className={th}>Website</th>
                    <th className={th}>Detail</th>
                  </tr>
                </thead>
                <tbody>
                  {merges.map((m) => (
                    <tr key={m.event_id} className="has-[:checked]:bg-orange-50">
                      <td className={td}>
                        <label className="flex min-h-11 min-w-11 cursor-pointer items-center justify-center">
                          <input type="checkbox" name="id" value={m.event_id} aria-label={`Select ${m.a_name}`} className="h-4 w-4 accent-neutral-900" />
                        </label>
                      </td>
                      <td className={td}>
                        <div className="font-medium">{m.a_name}</div>
                        <div className="text-xs text-neutral-500">{m.a_address}</div>
                      </td>
                      <td className={td}>
                        <div className="font-medium">{m.b_name}</div>
                        <div className="text-xs text-neutral-500">{m.b_address}</div>
                      </td>
                      <td className={`${td} whitespace-nowrap text-neutral-600`}>{place(m.a_city, m.a_state)}</td>
                      <td className={`${td} whitespace-nowrap font-mono text-xs`}>{m.distance_m ?? "?"} m</td>
                      <td className={`${td} whitespace-nowrap`}>
                        <Compare same={m.same_phone} missing={!m.a_phone || !m.b_phone} />
                      </td>
                      <td className={td}>
                        <Compare same={m.same_website} missing={!m.a_website || !m.b_website} />
                        <div className="text-xs text-neutral-500">
                          {[...new Set([websiteHost(m.a_website), websiteHost(m.b_website)].filter(Boolean))].join(" · ")}
                        </div>
                      </td>
                      <td className={`${td} whitespace-nowrap`}>
                        <Link href={`/admin/review/${m.event_id}`} className="inline-flex min-h-11 items-center underline hover:text-orange-700">
                          Open
                        </Link>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </form>
        )
      ) : (
        <div className="flex flex-1 flex-col sm:flex-row">
          <nav aria-label="Suggested tags" className="border-b border-neutral-200 p-2 sm:w-60 sm:shrink-0 sm:border-b-0 sm:border-r">
            <Link
              href="/admin/review?type=tags"
              className={`flex min-h-11 items-center justify-between rounded-lg px-2.5 ${tag === null ? "bg-neutral-200/70 font-medium" : "hover:bg-neutral-100"}`}
            >
              All tags <span className="font-mono text-xs">{tagTotal}</span>
            </Link>
            {counts.map((c) => (
              <Link
                key={c.tag_path}
                href={`/admin/review?type=tags&tag=${encodeURIComponent(c.tag_path)}`}
                className={`flex min-h-11 items-center justify-between gap-2 rounded-lg px-2.5 ${tag === c.tag_path ? "bg-neutral-200/70 font-medium" : "hover:bg-neutral-100"}`}
              >
                <span>{c.tag_name ?? c.tag_path}</span>
                <span className="font-mono text-xs">{c.pending}</span>
              </Link>
            ))}
          </nav>
          <div className="min-w-0 flex-1">
            {tags.length === 0 ? (
              <p className="px-4 py-10 text-neutral-600">No tag suggestions are waiting{tag ? " for this tag" : ""}.</p>
            ) : (
              <form>
                <input type="hidden" name="return" value={here} />
                {tags.map((t) => (
                  <input key={t.event_id} type="hidden" name="shown" value={t.event_id} />
                ))}
                <div className="flex flex-wrap items-center gap-2 border-b border-neutral-200 bg-neutral-50 px-4 py-2">
                  <button formAction={acceptTickedRejectRest} className={primary}>
                    Accept ticked, reject the rest
                  </button>
                  <button formAction={acceptTagsSelected} className={secondary}>
                    Accept ticked only
                  </button>
                  <button formAction={rejectTagsSelected} className={secondary}>
                    Reject ticked only
                  </button>
                  <span className="text-xs text-neutral-600">
                    Showing {tags.length}
                    {tags.length === TAG_PAGE ? ` (first ${TAG_PAGE}; more load after these are decided)` : ""}. Untick the wrong guesses.
                  </span>
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[760px] border-collapse text-[13px]">
                    <thead>
                      <tr className="bg-neutral-50">
                        <th className={th}><SelectAll /></th>
                        <th className={th}>Place</th>
                        <th className={th}>Town</th>
                        <th className={th}>Main category</th>
                        <th className={th}>Suggested tag</th>
                        <th className={th}>Matched on</th>
                      </tr>
                    </thead>
                    <tbody>
                      {tags.map((t) => (
                        <tr key={t.event_id} className="has-[:checked]:bg-orange-50">
                          <td className={td}>
                            <label className="flex min-h-11 min-w-11 cursor-pointer items-center justify-center">
                              <input type="checkbox" name="id" value={t.event_id} defaultChecked aria-label={`Select ${t.name}`} className="h-4 w-4 accent-neutral-900" />
                            </label>
                          </td>
                          <td className={td}>
                            <div className="font-medium">{t.name}</div>
                            <div className="text-xs text-neutral-500">{t.address}</div>
                          </td>
                          <td className={`${td} whitespace-nowrap text-neutral-600`}>{place(t.city, t.state)}</td>
                          <td className={`${td} whitespace-nowrap`}>{t.main_category}</td>
                          <td className={`${td} whitespace-nowrap font-medium`}>{t.tag_name ?? t.tag_path}</td>
                          <td className={`${td} font-mono text-xs text-neutral-600`}>{t.keyword}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </form>
            )}
          </div>
        </div>
      )}
    </>
  );
}
