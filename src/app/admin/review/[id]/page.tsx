import Link from "next/link";
import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { formatPhone, place, websiteHost } from "@/lib/adminFormat";
import Compare from "@/components/admin/Compare";
import { keepSeparateSelected, mergeSelected } from "../actions";
import type { MergeRow } from "../types";

const cell = "border-b border-l border-neutral-100 px-3.5 py-2.5 align-top";

export default async function ReviewOne({ params }: { params: Promise<{ id: string }> }) {
  const { db } = await requireAdmin();
  const { id } = await params;
  const { data, error } = await db.rpc("admin_pending_merges");
  if (error) throw new Error(error.message);
  const rows = (data ?? []) as MergeRow[];
  const index = rows.findIndex((r) => String(r.event_id) === id);
  if (index === -1) notFound();
  const m = rows[index];
  const next = rows[index + 1] ?? null;

  const fields: { label: string; a: string; b: string; compare: React.ReactNode }[] = [
    { label: "Name", a: m.a_name, b: m.b_name, compare: <Compare same={m.a_name === m.b_name} /> },
    {
      label: "Address",
      a: [m.a_address, place(m.a_city, m.a_state)].filter(Boolean).join(", "),
      b: [m.b_address, place(m.b_city, m.b_state)].filter(Boolean).join(", "),
      compare: <span className="font-mono text-xs">{m.distance_m ?? "?"} m apart</span>,
    },
    { label: "Phone", a: formatPhone(m.a_phone), b: formatPhone(m.b_phone), compare: <Compare same={m.same_phone} missing={!m.a_phone || !m.b_phone} /> },
    { label: "Website", a: websiteHost(m.a_website), b: websiteHost(m.b_website), compare: <Compare same={m.same_website} missing={!m.a_website || !m.b_website} /> },
    { label: "Status", a: m.a_status.replace("_", " "), b: m.b_status.replace("_", " "), compare: <Compare same={m.a_status === m.b_status} /> },
  ];

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
      <h1 className="text-lg font-semibold">Are these the same place?</h1>
      <div className="overflow-x-auto rounded-xl border border-neutral-200">
        <table className="w-full min-w-[620px] border-collapse text-[13px]">
          <thead>
            <tr className="bg-neutral-50 text-left">
              <th className="w-28 border-b border-neutral-200 px-3.5 py-2 font-medium text-neutral-600">Field</th>
              <th className="border-b border-l border-neutral-200 px-3.5 py-2 font-medium text-neutral-600">Place A (kept)</th>
              <th className="border-b border-l border-neutral-200 px-3.5 py-2 font-medium text-neutral-600">Place B</th>
              <th className="w-56 border-b border-l border-neutral-200 px-3.5 py-2 font-medium text-neutral-600">Compare</th>
            </tr>
          </thead>
          <tbody>
            {fields.map((f) => (
              <tr key={f.label}>
                <td className="border-b border-neutral-100 px-3.5 py-2.5 align-top text-neutral-500">{f.label}</td>
                <td className={`${cell} ${f.label === "Name" ? "text-[15px] font-semibold" : ""}`}>{f.a || <span className="text-neutral-400">None</span>}</td>
                <td className={`${cell} ${f.label === "Name" ? "text-[15px] font-semibold" : ""}`}>{f.b || <span className="text-neutral-400">None</span>}</td>
                <td className={cell}>{f.compare}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <form className="flex flex-wrap items-center gap-2">
        <input type="hidden" name="id" value={m.event_id} />
        <input type="hidden" name="return" value={next ? `/admin/review/${next.event_id}` : "/admin/review"} />
        <button formAction={mergeSelected} className="min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-4 text-[13px] font-medium text-white hover:bg-neutral-700">
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
        <span className="text-xs text-neutral-600">A merge keeps A&apos;s details, turns B into a redirect and moves saved lists to A.</span>
      </form>
    </div>
  );
}
