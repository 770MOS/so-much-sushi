"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { applyMapStyle } from "@/lib/mapConfig";

// What a list shows at each step, as if someone typed "b", "bi", "bil", "bill", "billings":
// closed, then answers of different lengths, each replacing the last.
const STEPS: string[][] = [
  [],
  ["Bath, ME", "Boise, ID", "Bend, OR"],
  ["Billings, MT", "Billerica, MA", "Billings, MO", "Billings, OK", "Billingsley, AL", "Billington, NY", "Billy, WV", "Bilbo, TX"],
  ["Billings, MT", "Billerica, MA", "Billings, MO", "Billings, OK", "Billingsley, AL"],
  ["Billings, MT", "Billings, MO", "Billings, OK", "Billingsley, AL"],
];
const STEP_MS = 1500;

const BOX = "absolute left-0 right-0 top-full z-40 mt-2 rounded-xl border border-line bg-white py-1 shadow-[0_8px_24px_rgba(0,0,0,0.12)]";
const CLIPPED = `${BOX} overflow-hidden`;
const LAYERED = `${CLIPPED} [transform:translateZ(0)] will-change-transform`;
const FLEX_BUTTON = "flex min-h-10 w-full items-baseline gap-2 px-3 py-2 text-left text-[15px] text-zinc-950";

type Variant = { letter: string; name: string; render: (rows: string[], step: number) => ReactNode };

const VARIANTS: Variant[] = [
  {
    letter: "A",
    name: "Old What box",
    render: (rows) => (
      <div className={CLIPPED}>
        {rows.map((r) => (
          <div key={r}>
            <button type="button" className={FLEX_BUTTON}>
              <span>{r}</span>
            </button>
          </div>
        ))}
      </div>
    ),
  },
  {
    letter: "B",
    name: "Old Where box",
    render: (rows) => (
      <ul className={LAYERED}>
        {rows.map((r) => (
          <li key={r}>
            <button type="button" className={FLEX_BUTTON}>
              <span>{r}</span>
            </button>
          </li>
        ))}
      </ul>
    ),
  },
  {
    letter: "C",
    name: "New rows",
    render: (rows) => (
      <ul className={BOX}>
        {rows.map((r) => (
          <li key={r} className="block min-h-10 cursor-pointer px-3 py-2 text-left text-[15px] text-zinc-950">
            {r}
          </li>
        ))}
      </ul>
    ),
  },
  {
    letter: "D",
    name: "No native look",
    render: (rows) => (
      <div className={CLIPPED}>
        {rows.map((r) => (
          <div key={r}>
            <button type="button" className={`${FLEX_BUTTON} appearance-none`}>
              <span>{r}</span>
            </button>
          </div>
        ))}
      </div>
    ),
  },
  {
    letter: "E",
    name: "No flexbox",
    render: (rows) => (
      <div className={CLIPPED}>
        {rows.map((r) => (
          <div key={r}>
            <button type="button" className="block min-h-10 w-full px-3 py-2 text-left text-[15px] text-zinc-950">
              {r}
            </button>
          </div>
        ))}
      </div>
    ),
  },
  {
    letter: "F",
    name: "Not clipped",
    render: (rows) => (
      <div className={BOX}>
        {rows.map((r) => (
          <div key={r}>
            <button type="button" className={FLEX_BUTTON}>
              <span>{r}</span>
            </button>
          </div>
        ))}
      </div>
    ),
  },
  {
    letter: "G",
    name: "Old, rebuilt",
    render: (rows, step) => (
      <div key={step} className={CLIPPED}>
        {rows.map((r) => (
          <div key={r}>
            <button type="button" className={FLEX_BUTTON}>
              <span>{r}</span>
            </button>
          </div>
        ))}
      </div>
    ),
  },
  {
    letter: "H",
    name: "Old, off map",
    render: (rows) => (
      <div className={CLIPPED}>
        {rows.map((r) => (
          <div key={r}>
            <button type="button" className={FLEX_BUTTON}>
              <span>{r}</span>
            </button>
          </div>
        ))}
      </div>
    ),
  },
];

export default function ListsCheck() {
  const mapRef = useRef<HTMLDivElement>(null);
  const [step, setStep] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => setStep((s) => (s + 1) % STEPS.length), STEP_MS);
    return () => clearInterval(timer);
  }, []);

  useEffect(() => {
    if (!mapRef.current) return;
    const map = new maplibregl.Map({ container: mapRef.current, center: [-73.98, 40.758], zoom: 13 });
    applyMapStyle(map, "map");
    return () => map.remove();
  }, []);

  const rows = STEPS[step];
  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="relative z-30 border-b border-line bg-white px-4 pb-3 pt-2">
        <p className="mb-2 text-[13px] text-muted">
          Dropdown check. Step {step + 1} of {STEPS.length}: every list should show{" "}
          {rows.length === 0 ? "nothing (closed)" : `${rows.length} names, starting with ${rows[0]}`}.
        </p>
        <div className="grid grid-cols-8 gap-2">
          {VARIANTS.map((v) => (
            <div key={v.letter} className="relative rounded-lg border border-zinc-300 bg-white px-2 py-1.5">
              <p className="truncate text-[13px] font-medium text-zinc-950">
                {v.letter}. {v.name}
              </p>
              {rows.length > 0 && v.render(rows, step)}
            </div>
          ))}
        </div>
      </div>
      <div className="relative grid min-h-[520px] flex-1 grid-cols-8">
        <div ref={mapRef} className="col-span-7 min-h-[520px]" />
        <div className="bg-white" />
      </div>
    </div>
  );
}
