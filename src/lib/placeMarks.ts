"use client";

import { useEffect, useRef } from "react";

// A favorite or Want to try mark changed somewhere on the page (the place panel, a result
// row), so other views of the same place can follow without asking the database again.
// from: which view made the change, so it can ignore its own announcement.
export type MarkChange = { id: string; starred?: boolean; want?: boolean; from?: "results" | "panel" };

const EVENT = "sms:place-mark";

export function announceMark(change: MarkChange) {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent<MarkChange>(EVENT, { detail: change }));
}

export function useMarkChanges(handler: (change: MarkChange) => void) {
  const ref = useRef(handler);
  useEffect(() => {
    ref.current = handler;
  });
  useEffect(() => {
    const listener = (e: Event) => ref.current((e as CustomEvent<MarkChange>).detail);
    window.addEventListener(EVENT, listener);
    return () => window.removeEventListener(EVENT, listener);
  }, []);
}
