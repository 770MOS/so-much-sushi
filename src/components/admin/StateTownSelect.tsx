"use client";

import { useRef, useState } from "react";
import { townsInState } from "@/app/admin/places/actions";

type Option = { value: string; count: number };

// State and Town dropdowns for the All places filter. The towns come with the page for the
// state in the address; picking another state loads its towns (every state's towns at once
// would be 35,000 names). A town that is not in the new state is cleared.
export default function StateTownSelect({
  states,
  towns,
  state,
  city,
  controlClass,
  labelClass,
}: {
  states: Option[];
  towns: Option[];
  state?: string;
  city?: string;
  controlClass: string;
  labelClass: string;
}) {
  const [chosenState, setChosenState] = useState(state ?? "");
  const [chosenCity, setChosenCity] = useState(city ?? "");
  const [options, setOptions] = useState<Option[]>(towns);
  const [loading, setLoading] = useState(false);
  const asked = useRef(state ?? "");

  async function pickState(next: string) {
    setChosenState(next);
    asked.current = next;
    if (!next) {
      setOptions([]);
      setChosenCity("");
      return;
    }
    setLoading(true);
    const found = await townsInState(next).catch(() => [] as Option[]);
    if (asked.current !== next) return; // another state was picked meanwhile
    setOptions(found);
    setLoading(false);
    setChosenCity((c) => (c && found.some((t) => t.value === c) ? c : ""));
  }

  // A town in the address without a state (an older link) still shows as chosen.
  const shown = chosenCity && !options.some((t) => t.value === chosenCity) ? [{ value: chosenCity, count: 0 }, ...options] : options;

  return (
    <>
      <label className={labelClass}>
        State
        <select name="state" value={chosenState} className={controlClass} onChange={(e) => pickState(e.target.value)}>
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
        <select
          name="city"
          value={chosenCity}
          onChange={(e) => setChosenCity(e.target.value)}
          disabled={loading || (!chosenState && !chosenCity)}
          className={`${controlClass} max-w-48 disabled:text-neutral-400`}
        >
          <option value="">{loading ? "Loading towns…" : chosenState ? `Any in ${chosenState}` : "Pick a state first"}</option>
          {shown.map((c) => (
            <option key={c.value} value={c.value}>
              {c.count ? `${c.value} (${c.count.toLocaleString("en-US")})` : c.value}
            </option>
          ))}
        </select>
      </label>
    </>
  );
}
