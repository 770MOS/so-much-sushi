import Link from "next/link";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import GroupDecision from "@/components/admin/GroupDecision";
import { ADVICE_LABEL, GROUP, GROUPS, type Advice, type GroupInfo, type GroupKind, type GroupRow } from "./groups";
import { place, websiteHost } from "@/lib/adminFormat";
import Compare from "@/components/admin/Compare";
import SelectAll from "@/components/admin/SelectAll";
import {
  acceptSourceChanges,
  acceptTagsSelected,
  acceptTickedRejectRest,
  declinePinReports,
  declinePlaceRequests,
  keepSeparateSelected,
  mergeSelected,
  rejectSourceChanges,
  rejectTagsSelected,
} from "./actions";
import type { MergeRow, PinReportRow, PlaceRequestRow, SourceChangeRow, TagCount, TagRow } from "./types";
import { metersText, PIN_HOW_SHORT, placedBy } from "@/lib/pins";

const TAG_PAGE = 200;
const ITEM_PAGE = 50;

const ADVICE_CHIP: Record<Advice, string> = {
  accept: "border-emerald-200 bg-emerald-50 text-emerald-800",
  look: "border-amber-200 bg-amber-50 text-amber-900",
  decline: "border-rose-200 bg-rose-50 text-rose-800",
};

const th = "whitespace-nowrap border-b border-l border-neutral-200 px-3 py-2 text-left font-medium text-neutral-600 first:border-l-0";
const td = "border-b border-l border-neutral-100 px-3 py-2 align-top first:border-l-0";
const primary = "min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-3.5 text-[13px] font-medium text-white hover:bg-neutral-700";
const secondary = "min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-3.5 text-[13px] font-medium hover:bg-neutral-50";

const CHANGE_LABEL: Record<string, string> = {
  attribute_change: "Value",
  closure_signal: "Closed?",
  status_change: "Reopened?",
  absent: "Missing",
};

const STATUS_LABEL: Record<string, string> = {
  active: "Open",
  temporarily_closed: "Temporarily closed",
  permanently_closed: "Permanently closed",
};

function changeValue(field: string | null, v: string | null) {
  if (!v) return null;
  return field === "status" ? (STATUS_LABEL[v] ?? v.replace(/_/g, " ")) : v;
}

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
  const requested = one(params.type);
  const type =
    requested === "tags"
      ? "tags"
      : requested === "changes"
        ? "changes"
        : requested === "requests"
          ? "requests"
          : requested === "pins"
            ? "pins"
            : "merges";
  const tag = one(params.tag) ?? null;
  const notice = one(params.notice);
  const kind: GroupKind | null = type === "merges" ? "duplicates" : type === "changes" ? "changes" : null;
  const groupKey = one(params.group) ?? null;
  const info: GroupInfo | null = groupKey && kind && GROUP[groupKey]?.kind === kind ? GROUP[groupKey] : null;
  const page = Math.max(1, Math.floor(Number(one(params.page)) || 1));

  // Possible duplicates and source changes come in groups (counts and examples only); the
  // items load for the one group being looked at, a page at a time.
  const [groupsRes, countsRes, requestsRes, pinsRes, itemsRes] = await Promise.all([
    db.rpc("admin_review_groups"),
    db.rpc("admin_pending_tag_counts"),
    db.rpc("admin_pending_place_requests"),
    db.rpc("admin_pending_pin_reports"),
    info
      ? db.rpc(info.kind === "duplicates" ? "admin_review_duplicates" : "admin_review_changes", {
          p_group: info.key,
          p_limit: ITEM_PAGE,
          p_offset: (page - 1) * ITEM_PAGE,
        })
      : Promise.resolve({ data: [], error: null }),
  ]);
  for (const res of [groupsRes, countsRes, requestsRes, pinsRes, itemsRes]) if (res.error) throw new Error(res.error.message);
  const pins = (pinsRes.data ?? []) as PinReportRow[];
  const requests = (requestsRes.data ?? []) as PlaceRequestRow[];
  const groupRows = ((groupsRes.data ?? []) as GroupRow[]).map((g) => ({ ...g, items: Number(g.items) }));
  const inGroup = new Map(groupRows.map((g) => [g.review_group, g]));
  const duplicateTotal = groupRows.filter((g) => g.kind === "duplicates").reduce((n, g) => n + g.items, 0);
  const changeTotal = groupRows.filter((g) => g.kind === "changes").reduce((n, g) => n + g.items, 0);
  const merges = (info?.kind === "duplicates" ? itemsRes.data ?? [] : []) as (MergeRow & { total: number })[];
  const changes = (info?.kind === "changes" ? itemsRes.data ?? [] : []) as (SourceChangeRow & { total: number })[];
  const itemTotal = Number((merges[0] ?? changes[0])?.total ?? 0);
  const pages = Math.max(1, Math.ceil(itemTotal / ITEM_PAGE));
  // After deciding the last items on a later page, go back a page.
  if (info && page > 1 && itemTotal === 0 && (inGroup.get(info.key)?.items ?? 0) > 0) {
    redirect(`/admin/review?type=${type}&group=${info.key}${notice ? `&notice=${encodeURIComponent(notice)}` : ""}`);
  }
  // Groups listed in our order; any the page doesn't know yet go last.
  const listed = (k: GroupKind) => [
    ...GROUPS.filter((g) => g.kind === k && inGroup.has(g.key)),
    ...groupRows
      .filter((g) => g.kind === k && !GROUP[g.review_group])
      .map((g): GroupInfo => ({ key: g.review_group, kind: k, title: g.review_group, advice: "look", why: "" })),
  ];
  const counts = ((countsRes.data ?? []) as TagCount[]).map((c) => ({ ...c, pending: Number(c.pending) }));
  const tagTotal = counts.reduce((sum, c) => sum + c.pending, 0);

  let tags: TagRow[] = [];
  if (type === "tags") {
    const res = await db.rpc("admin_pending_tags", { p_tag: tag, p_limit: TAG_PAGE, p_offset: 0 });
    if (res.error) throw new Error(res.error.message);
    tags = (res.data ?? []) as TagRow[];
  }

  const here =
    type === "tags"
      ? `/admin/review?type=tags${tag ? `&tag=${encodeURIComponent(tag)}` : ""}`
      : type === "requests"
        ? "/admin/review?type=requests"
        : type === "pins"
          ? "/admin/review?type=pins"
          : `/admin/review?type=${type}${info ? `&group=${info.key}${page > 1 ? `&page=${page}` : ""}` : ""}`;
  const groupLink = (key: string, p = 1) => `/admin/review?type=${type}&group=${key}${p > 1 ? `&page=${p}` : ""}`;
  const tab = (active: boolean) =>
    `flex min-h-11 items-center gap-2 rounded-lg border px-3 text-[13px] ${
      active ? "border-neutral-900 bg-neutral-900 text-white" : "border-neutral-300 bg-white hover:bg-neutral-50"
    }`;

  return (
    <>
      <div className="flex flex-wrap items-center gap-2 border-b border-neutral-200 px-4 py-2.5">
        <h1 className="mr-2 text-base font-semibold">Review queue</h1>
        <Link href="/admin/review" className={tab(type === "merges")}>
          Possible duplicates <span className="font-mono text-xs">{duplicateTotal.toLocaleString("en-US")}</span>
        </Link>
        <Link href="/admin/review?type=tags" className={tab(type === "tags")}>
          Tag suggestions <span className="font-mono text-xs">{tagTotal}</span>
        </Link>
        <Link href="/admin/review?type=changes" className={tab(type === "changes")}>
          Source changes <span className="font-mono text-xs">{changeTotal.toLocaleString("en-US")}</span>
        </Link>
        <Link href="/admin/review?type=requests" className={tab(type === "requests")}>
          Place requests <span className="font-mono text-xs">{requests.length}</span>
        </Link>
        <Link href="/admin/review?type=pins" className={tab(type === "pins")}>
          Pin reports <span className="font-mono text-xs">{pins.length}</span>
        </Link>
      </div>

      {notice && (
        <p role="status" className="border-b border-neutral-200 bg-orange-50 px-4 py-2 text-[13px] text-orange-900">
          {notice}
        </p>
      )}

      {kind && !info ? (
        listed(kind).length === 0 ? (
          <p className="px-4 py-10 text-neutral-600">{kind === "duplicates" ? "No possible duplicates are waiting." : "No changes from source loads are waiting."}</p>
        ) : (
          <>
            <p className="border-b border-neutral-200 bg-neutral-50 px-4 py-2 text-xs text-neutral-600">
              Sorted into groups of the same kind. Decide a whole group at once, or open it to go through it one by one (deciding a few
              one by one first, then the rest together, works too).{kind === "duplicates" ? " Every merge can be undone from the place’s page." : ""}
            </p>
            <ul>
              {listed(kind).map((g) => {
                const row = inGroup.get(g.key)!;
                return (
                  <li key={g.key} className="flex flex-col gap-3 border-b border-neutral-200 px-4 py-4 lg:flex-row lg:items-start">
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <h2 className="font-medium">
                          <Link href={groupLink(g.key)} className="underline decoration-neutral-300 hover:text-orange-700">
                            {g.title}
                          </Link>
                        </h2>
                        <span className={`rounded-full border px-2 py-0.5 text-xs ${ADVICE_CHIP[g.advice]}`}>{ADVICE_LABEL[g.advice]}</span>
                      </div>
                      {g.why && <p className="mt-1 max-w-3xl text-[13px] text-neutral-600">{g.why}</p>}
                      <ul className="mt-1.5 flex flex-col gap-0.5 text-xs text-neutral-500">
                        {row.examples.map((x, i) => (
                          <li key={i} className="truncate">{x}</li>
                        ))}
                      </ul>
                    </div>
                    <div className="flex flex-col gap-2 lg:items-end">
                      <div className="flex items-baseline gap-3">
                        <span className="font-mono text-lg">{row.items.toLocaleString("en-US")}</span>
                        <Link href={groupLink(g.key)} className="inline-flex min-h-11 items-center text-[13px] underline hover:text-orange-700">
                          Go through them
                        </Link>
                      </div>
                      <GroupDecision group={g.key} kind={kind} count={row.items} title={g.title} />
                    </div>
                  </li>
                );
              })}
            </ul>
          </>
        )
      ) : type === "pins" ? (
        pins.length === 0 ? (
          <p className="px-4 py-10 text-neutral-600">No pin reports are waiting.</p>
        ) : (
          <form>
            <input type="hidden" name="return" value={here} />
            <div className="flex flex-wrap items-center gap-2 border-b border-neutral-200 bg-neutral-50 px-4 py-2">
              <button formAction={declinePinReports} className={secondary}>
                Decline ticked
              </button>
              <input name="note" placeholder="Reason (optional)" className="min-h-11 w-56 rounded-lg border border-neutral-300 bg-white px-2.5 text-[13px]" />
              <span className="text-xs text-neutral-600">
                Members’ suggestions for a better spot. Open one to see both spots on a map, then accept (as sent or adjusted) or decline.
              </span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[900px] border-collapse text-[13px]">
                <thead>
                  <tr className="bg-neutral-50">
                    <th className={th}><SelectAll /></th>
                    <th className={th}>Place</th>
                    <th className={th}>Moves the pin</th>
                    <th className={th}>How they know</th>
                    <th className={th}>Sent by</th>
                    <th className={th}>Others agreeing</th>
                    <th className={th}>Sent</th>
                  </tr>
                </thead>
                <tbody>
                  {pins.map((q) => (
                    <tr key={q.id} className="has-[:checked]:bg-orange-50">
                      <td className={td}>
                        <label className="flex min-h-11 min-w-11 cursor-pointer items-center justify-center">
                          <input type="checkbox" name="report" value={q.id} aria-label={`Select the report for ${q.place.name}`} className="h-4 w-4 accent-neutral-900" />
                        </label>
                      </td>
                      <td className={td}>
                        <Link href={`/admin/review/pins/${q.id}`} className="inline-flex min-h-11 items-center font-medium underline decoration-neutral-300 hover:text-orange-700">
                          {q.place.name}
                        </Link>
                        <div className="text-xs text-neutral-500">{[q.place.address, place(q.place.city, q.place.state)].filter(Boolean).join(", ")}</div>
                        {q.note && <div className="max-w-xs text-xs text-neutral-600">“{q.note}”</div>}
                      </td>
                      <td className={td}>
                        {metersText(q.distance_m)}
                        <div className="text-xs text-neutral-500">{placedBy(q.method, q.accuracy_m)}</div>
                      </td>
                      <td className={td}>{PIN_HOW_SHORT[q.how]}</td>
                      <td className={td}>
                        {q.reported_by ?? <span className="text-neutral-400">Deleted account</span>}
                        <div className="text-xs text-neutral-500">
                          Sent {q.reports_by_this_person}, {q.accepted_from_this_person} accepted
                        </div>
                      </td>
                      <td className={td}>
                        {q.others.filter((o) => o.meters_from_this <= 15).length > 0 ? (
                          <span className="font-medium text-orange-800">{q.others.filter((o) => o.meters_from_this <= 15).length} within 15 m</span>
                        ) : q.others.length > 0 ? (
                          <span className="text-neutral-600">{q.others.length} elsewhere</span>
                        ) : (
                          <span className="text-neutral-500">None</span>
                        )}
                      </td>
                      <td className={`${td} whitespace-nowrap text-neutral-600`}>
                        {new Date(q.created_at).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </form>
        )
      ) : type === "requests" ? (
        requests.length === 0 ? (
          <p className="px-4 py-10 text-neutral-600">No place requests are waiting.</p>
        ) : (
          <form>
            <input type="hidden" name="return" value={here} />
            <div className="flex flex-wrap items-center gap-2 border-b border-neutral-200 bg-neutral-50 px-4 py-2">
              <button formAction={declinePlaceRequests} className={secondary}>
                Decline ticked
              </button>
              <input name="note" placeholder="Reason (optional)" className="min-h-11 w-56 rounded-lg border border-neutral-300 bg-white px-2.5 text-[13px]" />
              <span className="text-xs text-neutral-600">
                Missing places people asked for. Open one to add it, link it to a place we have, or decline it.
              </span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[900px] border-collapse text-[13px]">
                <thead>
                  <tr className="bg-neutral-50">
                    <th className={th}><SelectAll /></th>
                    <th className={th}>Requested place</th>
                    <th className={th}>Kind</th>
                    <th className={th}>Where</th>
                    <th className={th}>Asked by</th>
                    <th className={th}>Possible matches</th>
                    <th className={th}>Sent</th>
                  </tr>
                </thead>
                <tbody>
                  {requests.map((q) => (
                    <tr key={q.id} className="has-[:checked]:bg-orange-50">
                      <td className={td}>
                        <label className="flex min-h-11 min-w-11 cursor-pointer items-center justify-center">
                          <input type="checkbox" name="request" value={q.id} aria-label={`Select ${q.name}`} className="h-4 w-4 accent-neutral-900" />
                        </label>
                      </td>
                      <td className={td}>
                        <Link href={`/admin/review/requests/${q.id}`} className="inline-flex min-h-11 items-center font-medium underline decoration-neutral-300 hover:text-orange-700">
                          {q.name}
                        </Link>
                        {q.note && <div className="max-w-xs text-xs text-neutral-600">“{q.note}”</div>}
                      </td>
                      <td className={td}>{q.main_category_name}</td>
                      <td className={td}>
                        {q.address ?? <span className="text-neutral-400">No street given</span>}
                        <div className="text-xs text-neutral-500">{place(q.city, q.state)}</div>
                      </td>
                      <td className={td}>
                        {q.requested_by ?? <span className="text-neutral-400">Deleted account</span>}
                        {q.requested_by_handle && q.requested_by_handle !== q.requested_by && (
                          <div className="text-xs text-neutral-500">@{q.requested_by_handle}</div>
                        )}
                      </td>
                      <td className={td}>
                        {q.possible_matches > 0 ? (
                          <span className="font-medium text-orange-800">{q.possible_matches}</span>
                        ) : (
                          <span className="text-neutral-500">None</span>
                        )}
                      </td>
                      <td className={`${td} whitespace-nowrap text-neutral-600`}>
                        {new Date(q.created_at).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </form>
        )
      ) : type === "changes" && info ? (
        <>
        <GroupHeader info={info} count={inGroup.get(info.key)?.items ?? 0} back="/admin/review?type=changes" />
        {changes.length === 0 ? (
          <p className="px-4 py-10 text-neutral-600">None left in this group.</p>
        ) : (
          <form>
            <input type="hidden" name="return" value={here} />
            <div className="flex flex-wrap items-center gap-2 border-b border-neutral-200 bg-neutral-50 px-4 py-2">
              <button formAction={acceptSourceChanges} className={primary}>
                Apply ticked
              </button>
              <button formAction={rejectSourceChanges} className={secondary}>
                Reject ticked
              </button>
              <span className="text-xs text-neutral-600">
                Found by comparing the latest load with what we have. Values changed by hand are never overwritten without your say.
              </span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[980px] border-collapse text-[13px]">
                <thead>
                  <tr className="bg-neutral-50">
                    <th className={th}><SelectAll /></th>
                    <th className={th}>Place</th>
                    <th className={th}>Change</th>
                    <th className={th}>Now</th>
                    <th className={th}>Proposed</th>
                    <th className={th}>Why</th>
                  </tr>
                </thead>
                <tbody>
                  {changes.map((c) => (
                    <tr key={c.event_id} className="has-[:checked]:bg-orange-50">
                      <td className={td}>
                        <label className="flex min-h-11 min-w-11 cursor-pointer items-center justify-center">
                          <input type="checkbox" name="id" value={c.event_id} aria-label={`Select ${c.name}`} className="h-4 w-4 accent-neutral-900" />
                        </label>
                      </td>
                      <td className={td}>
                        <Link href={`/admin/places/${c.entity_id}`} className="inline-flex min-h-11 items-center font-medium underline decoration-neutral-300 hover:text-orange-700">
                          {c.name}
                        </Link>
                        <div className="text-xs text-neutral-500">{place(c.city, c.state)}</div>
                      </td>
                      <td className={`${td} whitespace-nowrap`}>{CHANGE_LABEL[c.event_type] ?? c.event_type}{c.event_type === "attribute_change" && c.field ? `: ${c.field.replace(/_/g, " ")}` : ""}</td>
                      <td className={td}>{changeValue(c.field, c.current_value) ?? <span className="text-neutral-400">None</span>}</td>
                      <td className={`${td} font-medium`}>{changeValue(c.field, c.proposed_value) ?? <span className="font-normal text-neutral-400">None</span>}</td>
                      <td className={`${td} text-neutral-600`}>
                        {c.reason}
                        {c.release && <div className="text-xs text-neutral-500">Load {c.release}</div>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pager page={page} pages={pages} total={itemTotal} link={(p) => groupLink(info.key, p)} />
          </form>
        )}
        </>
      ) : type === "merges" && info ? (
        <>
        <GroupHeader info={info} count={inGroup.get(info.key)?.items ?? 0} back="/admin/review" />
        {merges.length === 0 ? (
          <p className="px-4 py-10 text-neutral-600">None left in this group.</p>
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
            <Pager page={page} pages={pages} total={itemTotal} link={(p) => groupLink(info.key, p)} />
          </form>
        )}
        </>
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

function GroupHeader({ info, count, back }: { info: GroupInfo; count: number; back: string }) {
  return (
    <div className="flex flex-col gap-2 border-b border-neutral-200 px-4 py-3">
      <Link href={back} className="inline-flex min-h-11 w-fit items-center text-[13px] underline hover:text-orange-700">
        All {info.kind === "duplicates" ? "duplicate" : "change"} groups
      </Link>
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="text-base font-semibold">{info.title}</h2>
        <span className={`rounded-full border px-2 py-0.5 text-xs ${ADVICE_CHIP[info.advice]}`}>{ADVICE_LABEL[info.advice]}</span>
        <span className="font-mono text-sm text-neutral-600">{count.toLocaleString("en-US")} waiting</span>
      </div>
      {info.why && <p className="max-w-3xl text-[13px] text-neutral-600">{info.why}</p>}
      <GroupDecision group={info.key} kind={info.kind} count={count} title={info.title} />
    </div>
  );
}

function Pager({ page, pages, total, link }: { page: number; pages: number; total: number; link: (p: number) => string }) {
  if (pages <= 1) return null;
  const btn = "inline-flex min-h-11 items-center rounded-lg border border-neutral-300 px-3 hover:bg-neutral-50";
  return (
    <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 text-[13px] text-neutral-600">
      <span>
        {((page - 1) * ITEM_PAGE + 1).toLocaleString("en-US")} to {Math.min(page * ITEM_PAGE, total).toLocaleString("en-US")} of {total.toLocaleString("en-US")}
      </span>
      <span className="flex items-center gap-2">
        {page > 1 && <Link href={link(page - 1)} className={btn}>Previous</Link>}
        <span>Page {page} of {pages.toLocaleString("en-US")}</span>
        {page < pages && <Link href={link(page + 1)} className={btn}>Next</Link>}
      </span>
    </div>
  );
}
