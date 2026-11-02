import Link from "next/link";
import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { loadCategories } from "@/lib/adminCategories";
import { formatPhone, place, websiteHost } from "@/lib/adminFormat";
import AddPlaceForm from "@/components/admin/AddPlaceForm";
import { approvePlaceRequest, type SimilarPlace } from "@/app/admin/places/actions";
import { declinePlaceRequests, linkPlaceRequest } from "../../actions";
import type { PlaceRequestRow } from "../../types";

const control = "min-h-11 w-full rounded-lg border border-neutral-300 bg-white px-2.5 text-[13px]";
const panel = "rounded-xl border border-neutral-200";
const panelHead = "border-b border-neutral-200 bg-neutral-50 px-3.5 py-2 text-xs font-medium text-neutral-600";
const primary = "min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-3.5 text-[13px] font-medium text-white hover:bg-neutral-700";
const secondary = "min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-3.5 text-[13px] font-medium hover:bg-neutral-50";

const DECIDED: Record<string, string> = {
  added: "Added as a new place",
  already_listed: "Already listed",
  declined: "Declined",
};

const DECLINE_REASONS = [
  "Not a food or drink place",
  "Couldn't confirm it exists",
  "Permanently closed",
  "Asked for more than once",
  "Outside what we list",
];

function when(iso: string) {
  return new Date(iso).toLocaleString("en-US", { month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" });
}

export default async function PlaceRequestPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}) {
  const { db } = await requireAdmin();
  const { id } = await params;
  const request = Number(id);
  if (!Number.isInteger(request) || request <= 0) notFound();
  const noticeParam = (await searchParams).notice;
  const notice = Array.isArray(noticeParam) ? noticeParam[0] : noticeParam;

  const { data, error } = await db.rpc("admin_get_place_request", { p_id: request });
  if (error) throw new Error(error.message);
  if (!data) notFound();
  const q = data as PlaceRequestRow;
  const here = `/admin/review/requests/${q.id}`;

  const header = (
    <div className="flex flex-wrap items-center gap-3">
      <Link href="/admin/review?type=requests" className="inline-flex min-h-11 items-center underline hover:text-orange-700">
        Place requests
      </Link>
      <span className="text-neutral-400">/</span>
      <h1 className="text-lg font-semibold">{q.name}</h1>
    </div>
  );

  if (q.status !== "pending") {
    return (
      <div className="flex flex-col gap-4 px-4 py-5">
        {header}
        <p className="max-w-3xl rounded-lg border border-neutral-200 bg-neutral-50 px-3.5 py-2.5 text-[13px]">
          {DECIDED[q.status] ?? q.status} by {q.decided_by} on {q.decided_at ? when(q.decided_at) : "an unknown date"}.
          {q.decision_note && <> Note: {q.decision_note}.</>}{" "}
          {q.entity_id && (
            <Link href={`/admin/places/${q.entity_id}`} className="underline hover:text-orange-700">
              Open the place
            </Link>
          )}
        </p>
      </div>
    );
  }

  const [categories, similarRes] = await Promise.all([
    loadCategories(db),
    db.rpc("admin_similar_places", { p_lat: q.lat, p_lng: q.lng, p_name: q.name, p_phone: q.phone }),
  ]);
  if (similarRes.error) throw new Error(similarRes.error.message);
  const similar = (similarRes.data ?? []) as SimilarPlace[];

  const initial = {
    values: Object.fromEntries(
      Object.entries({
        name: q.name, address: q.address, city: q.city, state: q.state, postal_code: q.postal_code,
        phone: q.phone, website: q.website, main_category: q.main_category, status: "active",
        lat: String(q.lat), lng: String(q.lng),
      }).filter((e): e is [string, string] => typeof e[1] === "string" && e[1] !== ""),
    ),
  };

  return (
    <div className="flex flex-col gap-5 px-4 py-5">
      {header}
      {notice && (
        <p role="status" className="rounded-lg border border-orange-200 bg-orange-50 px-3.5 py-2 text-[13px] text-orange-900">
          {notice}
        </p>
      )}

      <section className={`${panel} max-w-3xl`}>
        <div className={panelHead}>The request</div>
        <dl className="grid grid-cols-[9rem_1fr] gap-x-4 gap-y-1.5 p-3.5 text-[13px]">
          <dt className="text-neutral-600">Asked by</dt>
          <dd>
            {q.requested_by ?? "A deleted account"}
            {q.requested_by_handle && q.requested_by_handle !== q.requested_by && <span className="text-neutral-500"> @{q.requested_by_handle}</span>}
            <span className="text-neutral-500"> · {when(q.created_at)} · {q.requests_by_this_person} {q.requests_by_this_person === 1 ? "request" : "requests"} from this person</span>
          </dd>
          <dt className="text-neutral-600">Place</dt>
          <dd>
            <span className="font-medium">{q.name}</span> · {q.main_category_name}
          </dd>
          <dt className="text-neutral-600">Address</dt>
          <dd>{[q.address, place(q.city, q.state), q.postal_code].filter(Boolean).join(", ") || <span className="text-neutral-400">Not given</span>}</dd>
          <dt className="text-neutral-600">Phone and website</dt>
          <dd>
            {[formatPhone(q.phone), websiteHost(q.website)].filter(Boolean).join(" · ") || <span className="text-neutral-400">Not given</span>}
          </dd>
          <dt className="text-neutral-600">Their note</dt>
          <dd>{q.note ? `“${q.note}”` : <span className="text-neutral-400">None</span>}</dd>
          <dt className="text-neutral-600">Where it&apos;s from</dt>
          <dd className="text-neutral-700">They confirmed it&apos;s from their own visit, the place&apos;s sign or menu, or its own website.</dd>
        </dl>
      </section>

      <section className={`${panel} max-w-3xl`}>
        <div className={panelHead}>Do we already have it?</div>
        {similar.length === 0 ? (
          <p className="px-3.5 py-3 text-[13px] text-neutral-600">No place nearby has a similar name or the same phone.</p>
        ) : (
          <ul className="divide-y divide-neutral-200 text-[13px]">
            {similar.map((s) => (
              <li key={s.id} className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 px-3.5 py-2">
                <span className="flex flex-col">
                  <Link href={`/admin/places/${s.id}`} target="_blank" className="font-medium underline hover:text-orange-700">
                    {s.name}
                  </Link>
                  <span className="text-neutral-700">
                    {[s.address, s.city, s.state].filter(Boolean).join(", ")}
                    {s.phone ? ` · ${formatPhone(s.phone)}` : ""}
                  </span>
                  <span className="text-xs text-neutral-500">{s.reason} · {s.distance_m} m from the requested pin</span>
                </span>
                <form action={linkPlaceRequest}>
                  <input type="hidden" name="return" value={here} />
                  <input type="hidden" name="request" value={q.id} />
                  <input type="hidden" name="place" value={s.id} />
                  <button className={secondary}>It&apos;s this one</button>
                </form>
              </li>
            ))}
          </ul>
        )}
        <form action={linkPlaceRequest} className="flex flex-wrap items-end gap-2 border-t border-neutral-200 px-3.5 py-3">
          <input type="hidden" name="return" value={here} />
          <input type="hidden" name="request" value={q.id} />
          <label className="flex min-w-72 flex-1 flex-col gap-1 text-xs font-medium text-neutral-700">
            Another place we have (its id, from its admin page address)
            <input name="place" placeholder="e.g. 3f2b…" className={control} />
          </label>
          <button className={secondary}>Link to that place</button>
        </form>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-[15px] font-semibold">Add it as a new place</h2>
        <p className="max-w-3xl text-[13px] text-neutral-600">
          Check the details and the pin, correct anything, then add it. It becomes a place added by hand, so we&apos;re responsible for it and it&apos;s rechecked like the others.
        </p>
        <AddPlaceForm
          categories={categories}
          action={approvePlaceRequest}
          initial={initial}
          hidden={{ request: String(q.id) }}
          submitLabel="Add place"
        />
      </section>

      <section className={`${panel} max-w-3xl`}>
        <div className={panelHead}>Or decline it</div>
        <form action={declinePlaceRequests} className="flex flex-wrap items-end gap-2 p-3.5">
          <input type="hidden" name="return" value={here} />
          <input type="hidden" name="request" value={q.id} />
          <label className="flex flex-col gap-1 text-xs font-medium text-neutral-700">
            Reason
            <select name="reason" defaultValue={DECLINE_REASONS[0]} className={`${control} w-64`}>
              {DECLINE_REASONS.map((r) => (
                <option key={r} value={r}>{r}</option>
              ))}
            </select>
          </label>
          <label className="flex min-w-60 flex-1 flex-col gap-1 text-xs font-medium text-neutral-700">
            Note (optional)
            <input name="note" className={control} />
          </label>
          <button className={primary}>Decline</button>
        </form>
        <p className="px-3.5 pb-3 text-xs text-neutral-500">The person sees &ldquo;Not added&rdquo;. The reason is kept for us only.</p>
      </section>
    </div>
  );
}
