"use client";

import { useSyncExternalStore } from "react";

// Tailwind's md breakpoint: from 768px the results page shows List, Split or Map; below it,
// one view at a time. Used to draw only the layout on screen, so a hidden map isn't loaded.
const QUERY = "(min-width: 768px)";

function subscribe(onChange: () => void) {
  const mq = window.matchMedia(QUERY);
  mq.addEventListener("change", onChange);
  return () => mq.removeEventListener("change", onChange);
}

export function useIsDesktop(): boolean | null {
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(QUERY).matches,
    () => null
  );
}
