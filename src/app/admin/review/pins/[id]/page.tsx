import Link from "next/link";
import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { place } from "@/lib/adminFormat";
import PinReportReview from "@/components/admin/PinReportReview";
import { metersText, PIN_HOW_SHORT, placedBy } from "@/lib/pins";
import { declinePinReports } from "../../actions";
import type { PinReportRow } from "../../types";

const panel = "rounded-xl border border-neutral-200";
const panelHead = "border-b border-neutral-200 bg-neutral-50 px-3.5 py-2 text-xs font-medium text-neutral-600";
const control = "min-h-11 w-full rounded-lg border border-neutral-300 bg-white px-2.5 text-[13px]";
const secondary = "min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-3.5 text-[13px] font-medium hover:bg-neutral-50";

const DECIDED: Record<string, string> = {
  accepted: "Accepted",
  declined: "Declined",
  superseded: "Closed when another report for this place was accepted",
};

const DECLINE_REASONS = ["The pin was already right", "Too far from the place", "Can’t tell which spot is right", "Looks like a mistake"];

function when(iso: string) {
  return new Date(iso).toLocaleString("en-US", { month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" });
}

function pinFrom(q: PinReportRow) {
  const p = q.place;
  if (p.pin_method === "manual") return "placed by hand";
  if (p.pin_method === "user_report") return "from an earlier member report";
  return [p.pin_source, p.pin_contributor].filter(Boolean).join(" · ") || "unknown";
}

export default async function PinReportPage({ params }: { params: Promise<{ id: string }> }) {
  const { db } = await requireAdmin();
  const report = Number((await params).id);
  if (!Number.isInteger(report) || report <= 0) notFound();
  const { data, error } = await db.rpc("admin_get_pin_report", { p_id: report });
  if (error) throw new Error(error.message);
  if (!data) notFound();
  const q = data as PinReportRow;
  const here = `/admin/review/pins/${q.id}`;

  return (
    <div className="flex flex-col gap-4 px-4 py-5">
      <div className="flex flex-wrap items-center gap-3">
        <Link href="/admin/review?type=pins" className="inline-flex min-h-11 items-center underline hover:text-orange-700">
          Pin reports
        </Link>
        <span className="text-neutral-400">/</span>
        <h1 className="text-lg font-semibold">{q.place.name}</h1>
        <Link href={`/admin/places/${q.place.id}`} className="ml-auto inline-flex min-h-11 items-center underline hover:text-orange-700">
          Open the place
        </Link>
      </div>

      <div className="flex flex-col gap-4 xl:flex-row xl:items-start">
        <section className={`${panel} min-w-0 flex-[3]`}>
          <div className={panelHead}>Where the member says it is</div>
          <div className="p-3.5">
            {q.status === "pending" ? (
              <PinReportReview
                id={q.id}
                current={{ lat: q.place.lat, lng: q.place.lng }}
                suggested={{ lat: q.lat, lng: q.lng }}
                others={q.others}
                how={q.how}
              />
            ) : (
              <p className="text-[13px]">
                {DECIDED[q.status] ?? q.status}
                {q.decided_at ? ` · ${when(q.decided_at)}` : ""}
                {q.decided_by ? ` · ${q.decided_by}` : ""}
                {q.decision_note ? ` · “${q.decision_note}”` : ""}
              </p>
            )}
          </div>
        </section>

        <div className="flex min-w-0 flex-[2] flex-col gap-4">
          <section className={panel}>
            <div className={panelHead}>The report</div>
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 p-3.5 text-[13px]">
              <dt className="text-neutral-500">Place</dt>
              <dd>{[q.place.address, place(q.place.city, q.place.state)].filter(Boolean).join(", ") || "No address"}</dd>
              <dt className="text-neutral-500">Pin now</dt>
              <dd>{pinFrom(q)}</dd>
              <dt className="text-neutral-500">Moves it</dt>
              <dd>{metersText(q.distance_m)}</dd>
              <dt className="text-neutral-500">How they know</dt>
              <dd>{PIN_HOW_SHORT[q.how]}</dd>
              <dt className="text-neutral-500">Placed by</dt>
              <dd>{placedBy(q.method, q.accuracy_m)}</dd>
              {q.note && (
                <>
                  <dt className="text-neutral-500">Note</dt>
                  <dd>“{q.note}”</dd>
                </>
              )}
              <dt className="text-neutral-500">Sent by</dt>
              <dd>
                {q.reported_by ?? "Deleted account"}
                {q.reported_by_handle && q.reported_by_handle !== q.reported_by ? ` (@${q.reported_by_handle})` : ""}
                <span className="text-neutral-500"> · sent {q.reports_by_this_person}, {q.accepted_from_this_person} accepted</span>
              </dd>
              <dt className="text-neutral-500">Sent</dt>
              <dd>{when(q.created_at)}</dd>
              <dt className="text-neutral-500">Others</dt>
              <dd>
                {q.others.length === 0
                  ? "No other reports for this place"
                  : q.others.map((o) => `${metersText(o.meters_from_this)} from this one`).join(", ")}
              </dd>
            </dl>
          </section>

          {q.status === "pending" && (
            <form className={panel}>
              <div className={panelHead}>Decline</div>
              <div className="flex flex-col gap-3 p-3.5 text-[13px]">
                <input type="hidden" name="report" value={q.id} />
                <input type="hidden" name="return" value={here} />
                <label className="flex flex-col gap-1">
                  <span className="text-xs font-medium text-neutral-700">Reason</span>
                  <select name="reason" defaultValue="" className={control}>
                    <option value="">No reason given</option>
                    {DECLINE_REASONS.map((r) => (
                      <option key={r}>{r}</option>
                    ))}
                  </select>
                </label>
                <label className="flex flex-col gap-1 text-xs font-medium text-neutral-700">
                  Note (optional, for us only)
                  <input name="note" className={control} />
                </label>
                <button formAction={declinePinReports} className={`${secondary} self-start`}>
                  Decline this report
                </button>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
