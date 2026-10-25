"use client";

import { useEffect, useRef, useState } from "react";

// "3 selected" for the row checkboxes in the same form; hides the bulk controls' hint
// once something is ticked or "all matching" is chosen.
export default function SelectedCount({ name = "id", allName = "scope", total }: { name?: string; allName?: string; total: number }) {
  const ref = useRef<HTMLSpanElement>(null);
  const [count, setCount] = useState(0);
  const [all, setAll] = useState(false);

  useEffect(() => {
    const form = ref.current?.closest("form");
    if (!form) return;
    const sync = () => {
      setCount(form.querySelectorAll(`input[type=checkbox][name="${name}"]:checked`).length);
      setAll(!!form.querySelector(`input[type=checkbox][name="${allName}"]:checked`));
    };
    sync();
    form.addEventListener("change", sync);
    return () => form.removeEventListener("change", sync);
  }, [name, allName]);

  return (
    <span ref={ref} aria-live="polite" className="text-[13px] font-medium">
      {all ? `All ${total.toLocaleString("en-US")} matching places` : count ? `${count} selected` : "Tick places to edit them together"}
    </span>
  );
}
