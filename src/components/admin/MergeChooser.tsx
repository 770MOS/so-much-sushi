// Side-by-side comparison of two places with a "keep" choice for every field.
// Renders inside a <form>; the chosen fields arrive as keep_<field> = "a" | "b".
import type { Category } from "@/lib/adminCategories";
import { formatPhone, websiteHost } from "@/lib/adminFormat";
import { MERGE_FIELDS, metresBetween, provenanceLabel, statusLabel, type AdminPlace, type MergeField } from "@/lib/adminPlace";

const cell = "border-b border-l border-neutral-100 px-3.5 py-2.5 align-top";

const LABELS: Record<MergeField, string> = {
  name: "Name", address: "Address", phone: "Phone", website: "Website", location: "Map pin",
  main_category: "Main category", status: "Status",
};
const PROVENANCE_FIELD: Record<MergeField, string> = {
  name: "name", address: "address", phone: "phone", website: "website", location: "location",
  main_category: "categories", status: "status",
};

function valueOf(p: AdminPlace, f: MergeField, categories: Category[]): string {
  switch (f) {
    case "name": return p.name;
    case "address": {
      const line2 = [p.city, [p.state, p.postal_code?.slice(0, 5)].filter(Boolean).join(" ")].filter(Boolean).join(", ");
      return [p.address, line2].filter(Boolean).join(", ");
    }
    case "phone": return formatPhone(p.phone);
    case "website": return p.website ? websiteHost(p.website) : "";
    case "location": return `${p.lat.toFixed(5)}, ${p.lng.toFixed(5)}`;
    case "main_category": return categories.find((c) => c.path === p.main_category)?.name ?? p.main_category;
    case "status": return statusLabel(p.status);
  }
}

// Raw values decide whether the two sides are the same and which side is empty.
function rawOf(p: AdminPlace, f: MergeField): string {
  switch (f) {
    case "address": return [p.address, p.city, p.state, p.postal_code].filter(Boolean).join("|");
    case "phone": return (p.phone ?? "").replace(/\D/g, "").replace(/^1(?=\d{10}$)/, "");
    case "website": return websiteHost(p.website);
    case "location": return `${p.lat.toFixed(5)},${p.lng.toFixed(5)}`;
    default: return String(p[f] ?? "");
  }
}

function tagNames(p: AdminPlace, categories: Category[]) {
  return p.tags.map((t) => categories.find((c) => c.path === t)?.name ?? t.split(".").pop()!.replace(/_/g, " "));
}

export default function MergeChooser({ a, b, categories }: { a: AdminPlace; b: AdminPlace; categories: Category[] }) {
  const distance = metresBetween(a, b);
  const tagsA = tagNames(a, categories);
  const tagsB = tagNames(b, categories);
  return (
    <div className="overflow-x-auto rounded-xl border border-neutral-200">
      <table className="w-full min-w-[680px] border-collapse text-[13px]">
        <thead>
          <tr className="bg-neutral-50 text-left">
            <th className="w-32 border-b border-neutral-200 px-3.5 py-2 font-medium text-neutral-600">Field</th>
            <th className="border-b border-l border-neutral-200 px-3.5 py-2 font-medium text-neutral-600">Place A (kept)</th>
            <th className="border-b border-l border-neutral-200 px-3.5 py-2 font-medium text-neutral-600">Place B (merged in)</th>
          </tr>
        </thead>
        <tbody>
          {MERGE_FIELDS.map((f) => {
            const rawA = rawOf(a, f);
            const rawB = rawOf(b, f);
            const same = rawA === rawB;
            // Default: keep A, unless A has nothing and B does.
            const pickB = !rawA && !!rawB;
            const side = (p: AdminPlace, key: "a" | "b", checked: boolean) => {
              const shown = valueOf(p, f, categories);
              const prov = provenanceLabel(p.provenance[PROVENANCE_FIELD[f]]);
              return (
                <td className={`${cell} ${f === "name" ? "text-[15px] font-semibold" : ""}`}>
                  <label className={`flex gap-2.5 ${same ? "" : "cursor-pointer"}`}>
                    {same ? (
                      key === "a" && <input type="hidden" name={`keep_${f}`} value="a" />
                    ) : (
                      <input type="radio" name={`keep_${f}`} value={key} defaultChecked={checked} className="mt-0.5 h-4 w-4 shrink-0 accent-neutral-900" />
                    )}
                    <span className="flex flex-col gap-0.5">
                      <span>{shown || <span className="font-normal text-neutral-400">None</span>}</span>
                      {f === "location" && key === "b" && <span className="text-xs font-normal text-neutral-500">{distance} m from A</span>}
                      {prov && shown && <span className="text-xs font-normal text-neutral-500">{prov}</span>}
                    </span>
                  </label>
                </td>
              );
            };
            return (
              <tr key={f}>
                <td className="border-b border-neutral-100 px-3.5 py-2.5 align-top text-neutral-500">
                  {LABELS[f]}
                  {same && <span className="block text-xs text-green-700">Same</span>}
                </td>
                {side(a, "a", !pickB)}
                {side(b, "b", pickB)}
              </tr>
            );
          })}
          <tr>
            <td className="px-3.5 py-2.5 align-top text-neutral-500">Tags</td>
            <td className="border-l border-neutral-100 px-3.5 py-2.5 align-top">{tagsA.join(", ") || <span className="text-neutral-400">None</span>}</td>
            <td className="border-l border-neutral-100 px-3.5 py-2.5 align-top">
              {tagsB.join(", ") || <span className="text-neutral-400">None</span>}
              <span className="block text-xs text-neutral-500">Tags from both places are kept.</span>
            </td>
          </tr>
          <tr className="bg-neutral-50 text-xs text-neutral-600">
            <td className="px-3.5 py-2">Saved by</td>
            <td className="border-l border-neutral-100 px-3.5 py-2">{a.saved.stars} stars · {a.saved.lists} lists · {a.source_records.length} source records</td>
            <td className="border-l border-neutral-100 px-3.5 py-2">{b.saved.stars} stars · {b.saved.lists} lists · {b.source_records.length} source records (all move to A)</td>
          </tr>
        </tbody>
      </table>
    </div>
  );
}
