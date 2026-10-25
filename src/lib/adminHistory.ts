// Turns place_history() rows into plain-language timeline entries for the admin place page.

export type HistoryRow = {
  at: string; kind: string; field: string | null; old_value: unknown; new_value: unknown; status: string | null;
  source: string | null; by_whom: string | null; detail: Record<string, unknown> | null;
};

export type TimelineEntry = {
  key: string; at: string; title: string; lines: string[]; who: string | null; tone: "source" | "change" | "decision" | "pending";
};

const FIELD_NAMES: Record<string, string> = {
  name: "name", address: "street address", city: "town", state: "state", postal_code: "ZIP", phone: "phone",
  website: "website", status: "status", location: "map pin", categories: "tags", main_category: "main category",
  needs_review: "review flag", operating_status: "opening status", category: "category",
};
const VERSION_FIELDS = ["name", "address", "city", "state", "postal_code", "phone", "website", "operating_status", "category"] as const;

function fieldName(f: string | null) {
  return f ? FIELD_NAMES[f] ?? f.replace(/_/g, " ") : "a field";
}

function show(v: unknown): string {
  if (v === null || v === undefined || v === "") return "nothing";
  if (typeof v === "string") return v.replace(/_/g, " ");
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  if (Array.isArray(v)) return v.length ? v.map((x) => show(x).split(".").pop()!).join(", ") : "none";
  const o = v as Record<string, unknown>;
  if ("lat" in o && "lng" in o) return `${Number(o.lat).toFixed(5)}, ${Number(o.lng).toFixed(5)}`;
  if ("add_category" in o) return String(o.add_category).split(".").pop()!.replace(/_/g, " ");
  return JSON.stringify(v);
}

function ledgerEntry(r: HistoryRow, i: number): TimelineEntry {
  const d = r.detail ?? {};
  // Automatic notes like "review queue proposal 123" add nothing for a reader.
  const note = typeof d.note === "string" && d.note && !/^review queue proposal \d+$/.test(d.note) ? [`Note: ${d.note}`] : [];
  const onMerged = d.on_merged_place ? ["(recorded on a place later merged into this one)"] : [];
  const base = { key: `e${i}`, at: r.at, who: r.by_whom };
  const change = `${fieldName(r.field)}: ${show(r.old_value)} → ${show(r.new_value)}`;
  const from = r.source ? ` from ${r.source}` : "";

  switch (r.kind) {
    case "manual_edit":
      return { ...base, title: `Edited by hand: ${change}`, lines: [...note, ...onMerged], tone: "decision" };
    case "merge": {
      const other = typeof d.duplicate_name === "string" ? d.duplicate_name : typeof d.name_b === "string" ? d.name_b : "another place";
      const taken = Array.isArray(d.taken_from_duplicate) && d.taken_from_duplicate.length
        ? [`Took ${(d.taken_from_duplicate as string[]).map(fieldName).join(", ")} from it`] : [];
      const undone = d.undone_by ? ["Later undone"] : [];
      const title =
        r.status === "pending" ? `Possible duplicate proposed: ${other}` :
        r.status === "rejected" ? `Possible duplicate kept separate: ${other}` :
        r.status === "superseded" ? `Possible duplicate no longer needed: ${other}` :
        d.source_records ? `Merged in: ${other}` : `Possible duplicate accepted: ${other}`;
      return { ...base, title, lines: [...taken, ...undone, ...note, ...onMerged], tone: r.status === "pending" ? "pending" : "decision" };
    }
    case "unmerge": {
      const other = typeof d.duplicate_name === "string" ? d.duplicate_name : typeof d.survivor_name === "string" ? d.survivor_name : "another place";
      const kept = Array.isArray(d.fields_kept_edited_since) && d.fields_kept_edited_since.length
        ? [`Left as edited: ${(d.fields_kept_edited_since as string[]).map(fieldName).join(", ")}`] : [];
      return { ...base, title: `Merge undone: ${other}`, lines: [...kept, ...note], tone: "decision" };
    }
    case "new_candidate":
      return { ...base, title: d.added_by_hand ? "Added by hand" : `New place${from}`, lines: note, tone: "decision" };
    case "attribute_change": {
      if (r.field === "categories") {
        return { ...base, title: `Tag suggestion "${show(r.new_value)}": ${r.status === "approved" ? "accepted" : r.status ?? ""}`, lines: onMerged, tone: r.status === "pending" ? "pending" : "decision" };
      }
      const title =
        r.status === "auto_applied" ? `Updated automatically${from}: ${change}` :
        r.status === "pending" ? `Proposed${from}: ${change}` :
        r.status === "approved" ? `Accepted${from}: ${change}` :
        r.status === "rejected" ? `Rejected${from}: ${change}` :
        `Closed without action${from}: ${change}`;
      const reason = typeof d.reason === "string" ? [d.reason.charAt(0).toUpperCase() + d.reason.slice(1)] : [];
      return { ...base, title, lines: [...reason, ...onMerged], tone: r.status === "auto_applied" ? "change" : r.status === "pending" ? "pending" : "decision" };
    }
    case "closure_signal":
    case "status_change":
    case "absent": {
      const what = r.kind === "absent" ? "Possibly closed (missing from the source)" : r.kind === "closure_signal" ? "Closure reported" : "Reopening reported";
      const reason = typeof d.reason === "string" ? [d.reason.charAt(0).toUpperCase() + d.reason.slice(1)] : [];
      return { ...base, title: `${what}${from}: ${r.status === "pending" ? "waiting for review" : r.status ?? ""}`, lines: [...reason, ...onMerged], tone: r.status === "pending" ? "pending" : "decision" };
    }
    default:
      return { ...base, title: `${r.kind.replace(/_/g, " ")}${r.field ? ` (${fieldName(r.field)})` : ""}${from}: ${r.status ?? ""}`, lines: [...note, ...onMerged], tone: "change" };
  }
}

// Source versions: the first shows what the source said; later ones show only what changed.
function versionEntries(rows: HistoryRow[]): TimelineEntry[] {
  const byRecord = new Map<string, HistoryRow[]>();
  for (const r of rows) {
    const id = `${r.source}|${String(r.detail?.source_record_id ?? "")}`;
    byRecord.set(id, [...(byRecord.get(id) ?? []), r]);
  }
  const out: TimelineEntry[] = [];
  for (const [id, list] of byRecord) {
    list.sort((a, b) => Number(a.detail?.version ?? 0) - Number(b.detail?.version ?? 0));
    list.forEach((r, i) => {
      const v = (r.new_value ?? {}) as Record<string, unknown>;
      const release = r.detail?.from_release ? ` (${r.detail.from_release})` : "";
      if (i === 0) {
        const lines = [
          [v.name, [v.address, v.city, v.state].filter(Boolean).join(", ")].filter(Boolean).join(" · "),
          [v.phone, v.website, v.category].filter(Boolean).map(String).join(" · "),
        ].filter(Boolean) as string[];
        out.push({ key: `${id}|${i}`, at: r.at, title: `First seen in ${r.source}${release}`, lines, who: null, tone: "source" });
      } else {
        const prev = (list[i - 1].new_value ?? {}) as Record<string, unknown>;
        const lines = VERSION_FIELDS.filter((f) => (prev[f] ?? null) !== (v[f] ?? null))
          .map((f) => `${fieldName(f)}: ${show(prev[f])} → ${show(v[f])}`);
        out.push({ key: `${id}|${i}`, at: r.at, title: `${r.source} changed its record${release}`, lines: lines.length ? lines : ["Map pin moved"], who: null, tone: "source" });
      }
    });
  }
  return out;
}

const duplicateOf = (r: HistoryRow) => String((r.old_value as { duplicate?: string } | null)?.duplicate ?? "");

export function buildTimeline(rows: HistoryRow[]): TimelineEntry[] {
  const versions = versionEntries(rows.filter((r) => r.kind === "source version"));
  // An accepted proposal is shown by the merge it led to.
  const merged = new Set(rows.filter((r) => r.kind === "merge" && r.detail?.source_records).map(duplicateOf));
  const ledger = rows
    .filter((r) => r.kind !== "source version")
    .filter((r) => !(r.kind === "merge" && r.status === "approved" && !r.detail?.source_records && merged.has(duplicateOf(r))))
    .map(ledgerEntry);
  return [...ledger, ...versions].sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0));
}
