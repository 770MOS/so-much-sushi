"use client";

import { useRouter } from "next/navigation";
import { BackArrowIcon, CloseIcon } from "@/components/icons";

// Wraps the intercepted /venue/[id] route's content. Same component either
// way, responsive via Tailwind's md: breakpoint (matching Sidebar.tsx's own
// desktop/mobile split) rather than two separate implementations:
//   - desktop: dimmed backdrop + a right-hand slide-over panel, closed via
//     an X in the corner.
//   - mobile: no real backdrop to speak of (the panel already covers the
//     whole viewport), closed via a back arrow at the top instead - reads
//     as "go back", not "dismiss into blank space".
// Both close the same way: router.back(), which pops the history entry
// the intercepted navigation pushed and returns to whatever was actually
// behind it (matches the Next.js docs' own modal-closing convention).
export default function VenueModal({ children }: { children: React.ReactNode }) {
  const router = useRouter();

  function close() {
    router.back();
  }

  return (
    <div className="fixed inset-0 z-40">
      <div
        className="absolute inset-0 bg-black/40 md:block"
        onClick={close}
        aria-hidden="true"
      />

      <div
        role="dialog"
        aria-modal="true"
        className="absolute inset-0 flex flex-col overflow-y-auto bg-white dark:bg-black md:inset-y-0 md:left-auto md:right-0 md:w-full md:max-w-lg md:shadow-xl"
      >
        <div className="sticky top-0 flex items-center border-b border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-black">
          <button
            type="button"
            onClick={close}
            aria-label="Back"
            className="rounded p-1 text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-900 md:hidden"
          >
            <BackArrowIcon />
          </button>
          <button
            type="button"
            onClick={close}
            aria-label="Close"
            className="ml-auto hidden rounded p-1 text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-900 md:inline-flex"
          >
            <CloseIcon />
          </button>
        </div>

        {children}
      </div>
    </div>
  );
}
