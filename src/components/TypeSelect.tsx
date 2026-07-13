"use client";

import { TYPE_OPTIONS, type EntityType } from "@/lib/entityTypes";

type Props = {
  value: EntityType;
  onChange: (type: EntityType) => void;
};

export default function TypeSelect({ value, onChange }: Props) {
  return (
    <div className="flex flex-col gap-2">
      <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">Type</span>
      <div className="flex flex-wrap gap-2">
        {TYPE_OPTIONS.map((opt) => (
          <button
            key={opt.key}
            type="button"
            onClick={() => onChange(opt.key)}
            aria-pressed={value === opt.key}
            className={`rounded-lg border px-3 py-1.5 text-sm font-medium transition-colors ${
              value === opt.key
                ? "border-primary bg-primary text-white"
                : "border-zinc-300 text-zinc-600 hover:text-zinc-900 dark:border-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-100"
            }`}
          >
            {opt.label}
          </button>
        ))}
      </div>
    </div>
  );
}
