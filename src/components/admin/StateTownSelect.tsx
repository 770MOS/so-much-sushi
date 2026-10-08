"use client";

import { useMemo, useState } from "react";

type Option = { value: string; count: number };
type Town = { state: string | null; value: string; count: number };

// State and Town dropdowns for the All places filter. Picking a state narrows the
// town list straight away; a town that is not in the new state is cleared.
export default function StateTownSelect({
  states,
  towns,
  state,
  city,
  controlClass,
  labelClass,
}: {
  states: Option[];
  towns: Town[];
  state?: string;
  city?: string;
  controlClass: string;
  labelClass: string;
}) {
  const [chosenState, setChosenState] = useState(state ?? "");
  const [chosenCity, setChosenCity] = useState(city ?? "");

  const options = useMemo(() => {
    if (chosenState) return towns.filter((t) => t.state === chosenState).map(({ value, count }) => ({ value, count }));
    // No state chosen: one entry per town name, counts added across states.
    const merged = new Map<string, number>();
    for (const t of towns) merged.set(t.value, (merged.get(t.value) ?? 0) + t.count);
    return [...merged].map(([value, count]) => ({ value, count })).sort((a, b) => a.value.localeCompare(b.value));
  }, [towns, chosenState]);

  return (
    <>
      <label className={labelClass}>
        State
        <select
          name="state"
          value={chosenState}
          className={controlClass}
          onChange={(e) => {
            const next = e.target.value;
            setChosenState(next);
            if (next && chosenCity && !towns.some((t) => t.state === next && t.value === chosenCity)) setChosenCity("");
          }}
        >
          <option value="">Any</option>
          {states.map((s) => (
            <option key={s.value} value={s.value}>
              {s.value} ({s.count.toLocaleString("en-US")})
            </option>
          ))}
        </select>
      </label>
      <label className={labelClass}>
        Town or city
        <select name="city" value={chosenCity} onChange={(e) => setChosenCity(e.target.value)} className={`${controlClass} max-w-48`}>
          <option value="">{chosenState ? `Any in ${chosenState}` : "Any"}</option>
          {options.map((c) => (
            <option key={c.value} value={c.value}>
              {c.value} ({c.count.toLocaleString("en-US")})
            </option>
          ))}
        </select>
      </label>
    </>
  );
}
