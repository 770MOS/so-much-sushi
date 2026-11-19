import { useEffect, type RefObject } from "react";

// Safari 26 draws a suggestion list that has just opened, but sometimes leaves the words of rows
// that change while the list is open undrawn until the window is redrawn (switching apps, pressing
// Search). A row repainted as soon as its own look changed (the mouse going over it). So, a frame
// after the list's rows change, this changes the list's background by an amount no one can see
// (#ffffff to #fffffe), which makes Safari repaint the whole box with its rows. `key` is what the
// rows are (null while the list is closed); the lists also rebuild themselves when it changes.
// Found on the tester site 2026-11-19; not reproducible in Chrome or in a page that changed a list
// on a timer.
export function useRepaint(ref: RefObject<HTMLElement | null>, key: string | null) {
  useEffect(() => {
    if (key === null) return;
    let second = 0;
    const first = requestAnimationFrame(() => {
      second = requestAnimationFrame(() => {
        const el = ref.current;
        if (el) el.style.backgroundColor = "#fffffe";
      });
    });
    return () => {
      cancelAnimationFrame(first);
      cancelAnimationFrame(second);
    };
  }, [ref, key]);
}
