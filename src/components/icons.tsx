export function HeartIcon() {
  return (
    <svg viewBox="0 0 24 24" width={14} height={14} fill="currentColor" className="text-rose-400">
      <path d="M12 21s-6.716-4.35-9.428-8.06C.85 10.42 1.2 7.03 3.79 5.3 6.02 3.8 8.94 4.4 10.5 6.3 12.06 4.4 14.98 3.8 17.21 5.3c2.59 1.73 2.94 5.12 1.22 7.64C18.72 16.65 12 21 12 21z" />
    </svg>
  );
}

export function StarIcon({ filled }: { filled: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={20}
      height={20}
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth={1.5}
      className={filled ? "text-amber-400" : "text-zinc-400"}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M12 3.5l2.6 5.27 5.82.85-4.21 4.1.99 5.8L12 16.9l-5.2 2.62.99-5.8-4.21-4.1 5.82-.85L12 3.5z"
      />
    </svg>
  );
}

export function CrosshairIcon() {
  return (
    <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <circle cx="12" cy="12" r="7" strokeLinecap="round" strokeLinejoin="round" />
      <path strokeLinecap="round" d="M12 2v3M12 19v3M2 12h3M19 12h3" />
      <circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none" />
    </svg>
  );
}

export function EyeOffIcon({ filled }: { filled: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={20}
      height={20}
      fill="none"
      stroke="currentColor"
      strokeWidth={filled ? 2 : 1.5}
      className={filled ? "text-zinc-800 dark:text-zinc-100" : "text-zinc-400"}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M3 3l18 18M10.58 10.58a2 2 0 102.83 2.83M9.88 4.24A9.1 9.1 0 0112 4c5 0 9 4.5 10.5 8-.6 1.36-1.5 2.7-2.6 3.85M6.4 6.4C4.13 7.86 2.44 9.94 1.5 12c1.02 2.28 2.7 4.24 4.76 5.6A9.15 9.15 0 0012 20c1.13 0 2.21-.18 3.22-.51"
      />
    </svg>
  );
}

// Password-visibility icons. Distinct from EyeOffIcon above (which takes a
// `filled` prop tied to the hide-restaurant feature's muted/active color
// semantics) - these are a plain two-state pair with no such distinction.
export function EyeIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M1.5 12S5 5 12 5s10.5 7 10.5 7-3.5 7-10.5 7S1.5 12 1.5 12z"
      />
      <circle cx="12" cy="12" r="2.5" />
    </svg>
  );
}

export function EyeSlashIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M3 3l18 18M10.58 10.58a2 2 0 102.83 2.83M9.88 4.24A9.1 9.1 0 0112 4c5 0 9 4.5 10.5 8-.6 1.36-1.5 2.7-2.6 3.85M6.4 6.4C4.13 7.86 2.44 9.94 1.5 12c1.02 2.28 2.7 4.24 4.76 5.6A9.15 9.15 0 0012 20c1.13 0 2.21-.18 3.22-.51"
      />
    </svg>
  );
}

// Sidebar nav icons - plain outline style, matching the stroke-based icons above.
export function StarredNavIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M12 3.5l2.6 5.27 5.82.85-4.21 4.1.99 5.8L12 16.9l-5.2 2.62.99-5.8-4.21-4.1 5.82-.85L12 3.5z"
      />
    </svg>
  );
}

export function ListsNavIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <path strokeLinecap="round" d="M8 6h12M8 12h12M8 18h12" />
      <circle cx="4" cy="6" r="1.25" fill="currentColor" stroke="none" />
      <circle cx="4" cy="12" r="1.25" fill="currentColor" stroke="none" />
      <circle cx="4" cy="18" r="1.25" fill="currentColor" stroke="none" />
    </svg>
  );
}

export function RecommendedNavIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M12 21s-6.716-4.35-9.428-8.06C.85 10.42 1.2 7.03 3.79 5.3 6.02 3.8 8.94 4.4 10.5 6.3 12.06 4.4 14.98 3.8 17.21 5.3c2.59 1.73 2.94 5.12 1.22 7.64C18.72 16.65 12 21 12 21z"
      />
    </svg>
  );
}

export function SearchNavIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <circle cx="10.5" cy="10.5" r="6.5" />
      <path strokeLinecap="round" d="M19.5 19.5l-4.7-4.7" />
    </svg>
  );
}

export function ConnectionsNavIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <circle cx="8.5" cy="8" r="3" />
      <path strokeLinecap="round" d="M2.5 19.5c0-3.31 2.69-6 6-6s6 2.69 6 6" />
      <circle cx="17" cy="8.5" r="2.5" />
      <path strokeLinecap="round" d="M15.5 13.25c2.64.4 4.5 2.63 4.5 5.25" />
    </svg>
  );
}
