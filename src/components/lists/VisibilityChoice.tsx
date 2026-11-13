"use client";

import { PUBLIC_NOTE, VISIBILITY, VISIBILITY_ORDER, type Visibility } from "@/lib/lists";
import { VisibilityIcon } from "@/components/lists/VisibilityMenu";

// Who can see a list, as three choices in a form (New list, Edit list).
export default function VisibilityChoice({ value, onChange }: { value: Visibility; onChange: (v: Visibility) => void }) {
  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="mb-1 text-sm font-medium text-zinc-950">Who can see it</legend>
      {VISIBILITY_ORDER.map((v) => (
        <label
          key={v}
          className={`flex cursor-pointer items-start gap-3 rounded-[10px] border px-3.5 py-2.5 ${value === v ? "border-zinc-950" : "border-[#dddddd] hover:border-zinc-400"}`}
        >
          <input type="radio" name="visibility" value={v} checked={value === v} onChange={() => onChange(v)} className="mt-1 accent-zinc-950" />
          <span className="flex flex-col">
            <span className="flex items-center gap-1.5 text-[15px] font-medium text-zinc-950">
              <VisibilityIcon v={v} />
              {VISIBILITY[v].label}
            </span>
            <span className="text-[13px] text-muted">{v === "public" ? PUBLIC_NOTE : VISIBILITY[v].help}</span>
          </span>
        </label>
      ))}
    </fieldset>
  );
}
