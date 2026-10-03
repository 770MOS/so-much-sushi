"use client";

import { useEffect, useRef, useState } from "react";

// Header checkbox for a review table: ticks or unticks every row checkbox in the
// same form and shows how many are ticked.
export default function SelectAll({ name = "id" }: { name?: string }) {
  const ref = useRef<HTMLInputElement>(null);
  const [count, setCount] = useState<number | null>(null);

  useEffect(() => {
    const form = ref.current?.form;
    if (!form) return;
    const boxes = () => Array.from(form.querySelectorAll<HTMLInputElement>(`input[type=checkbox][name="${name}"]`));
    const sync = () => {
      const all = boxes();
      const ticked = all.filter((b) => b.checked).length;
      setCount(ticked);
      if (ref.current) {
        ref.current.checked = all.length > 0 && ticked === all.length;
        ref.current.indeterminate = ticked > 0 && ticked < all.length;
      }
    };
    sync();
    form.addEventListener("change", sync);
    return () => form.removeEventListener("change", sync);
  }, [name]);

  return (
    <label className="flex min-h-11 min-w-11 cursor-pointer items-center justify-center gap-2">
      <input
        ref={ref}
        type="checkbox"
        aria-label="Select all rows"
        className="h-4 w-4 accent-neutral-900"
        onChange={(e) => {
          const form = e.currentTarget.form;
          if (!form) return;
          form
            .querySelectorAll<HTMLInputElement>(`input[type=checkbox][name="${name}"]`)
            .forEach((b) => (b.checked = e.currentTarget.checked));
          form.dispatchEvent(new Event("change"));
        }}
      />
      <span className="sr-only" aria-live="polite">
        {count === null ? "" : `${count} selected`}
      </span>
    </label>
  );
}
