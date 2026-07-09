"use client";

import { useEffect, useRef, useState } from "react";

type Props = {
  id?: string;
  value: number;
  onChange: (value: number) => void;
  min: number;
  max: number;
};

// Matches the native range-thumb width assumed by the bubble-position math
// below (Chrome/Safari/Firefox all default close to this for <input
// type="range">) - not something we force via CSS, just the value used to
// approximate where the browser actually draws the thumb.
const THUMB_SIZE = 16;

export default function RadiusSlider({ id, value, onChange, min, max }: Props) {
  const trackRef = useRef<HTMLInputElement>(null);
  const [trackWidth, setTrackWidth] = useState(0);

  useEffect(() => {
    const el = trackRef.current;
    if (!el) return;

    function measure() {
      if (trackRef.current) setTrackWidth(trackRef.current.offsetWidth);
    }
    measure();

    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const percent = max > min ? (value - min) / (max - min) : 0;
  const bubbleLeft = percent * (trackWidth - THUMB_SIZE) + THUMB_SIZE / 2;

  return (
    <div className="relative pt-9">
      {trackWidth > 0 && (
        <div
          className="pointer-events-none absolute top-0 w-max -translate-x-1/2 whitespace-nowrap rounded-md border border-zinc-300 bg-white px-2 py-0.5 text-xs font-semibold text-zinc-900 shadow-sm dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
          style={{ left: bubbleLeft }}
        >
          {value} mi
        </div>
      )}
      <input
        ref={trackRef}
        id={id}
        type="range"
        min={min}
        max={max}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="w-full accent-primary"
      />
    </div>
  );
}
