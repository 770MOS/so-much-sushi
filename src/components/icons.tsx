// The 5 marker-category icons below use path data borrowed directly from
// Tabler Icons (github.com/tabler/tabler-icons, MIT licensed) - specific
// icons: tools-kitchen-2, glass-cocktail, cup, bread, beer. Hand-wrapped as
// inline SVGs matching this file's existing convention rather than adding
// @tabler/icons-react as a dependency - this project has no icon-library
// dependency anywhere else, every icon here is a plain inline SVG.
export function RestaurantTypeIcon() {
  return (
    <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M19 3v12h-5c-.023 -3.681 .184 -7.406 5 -12m0 12v6h-1v-3m-10 -14v17m-3 -17v3a3 3 0 1 0 6 0v-3" />
    </svg>
  );
}

export function BarTypeIcon() {
  return (
    <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M8 21h8" />
      <path d="M12 15v6" />
      <path d="M5 5a7 2 0 1 0 14 0a7 2 0 1 0 -14 0" />
      <path d="M5 5v.388c0 .432 .126 .853 .362 1.206l5 7.509c.633 .951 1.88 1.183 2.785 .517c.191 -.141 .358 -.316 .491 -.517l5 -7.509c.236 -.353 .362 -.774 .362 -1.206v-.388" />
    </svg>
  );
}

export function CoffeeTypeIcon() {
  return (
    <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 11h14v-3h-14l0 3" />
      <path d="M17.5 11l-1.5 10h-8l-1.5 -10" />
      <path d="M6 8v-1a2 2 0 0 1 2 -2h8a2 2 0 0 1 2 2v1" />
      <path d="M15 5v-2" />
    </svg>
  );
}

export function BakeryTypeIcon() {
  return (
    <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M18 4a3 3 0 0 1 2 5.235v8.765a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-8.764a3 3 0 0 1 1.824 -5.231h12.176v-.005" />
    </svg>
  );
}

export function BreweryTypeIcon() {
  return (
    <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M9 21h6a1 1 0 0 0 1 -1v-3.625c0 -1.397 .29 -2.775 .845 -4.025l.31 -.7c.556 -1.25 .845 -2.253 .845 -3.65v-4a1 1 0 0 0 -1 -1h-10a1 1 0 0 0 -1 1v4c0 1.397 .29 2.4 .845 3.65l.31 .7a9.931 9.931 0 0 1 .845 4.025v3.625a1 1 0 0 0 1 1" />
      <path d="M6 8h12" />
    </svg>
  );
}

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

// Location-input dropdown row icons - small inline size, matching
// CrosshairIcon's footprint since they share the same input context.
export function LocationPinIcon() {
  return (
    <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M12 21s7-6.5 7-12a7 7 0 10-14 0c0 5.5 7 12 7 12z"
      />
      <circle cx="12" cy="9" r="2.5" />
    </svg>
  );
}

export function HistoryIcon() {
  return (
    <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <circle cx="12" cy="12" r="8.5" />
      <path strokeLinecap="round" strokeLinejoin="round" d="M12 7.5V12l3 2" />
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

export function DiscoverNavIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <circle cx="12" cy="12" r="9" />
      <path strokeLinecap="round" strokeLinejoin="round" d="M15.5 8.5l-2 5-5 2 2-5 5-2z" />
    </svg>
  );
}

export function BookmarkIcon({ filled }: { filled: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={18}
      height={18}
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth={1.5}
      className={filled ? "text-primary" : "text-zinc-400"}
    >
      <path strokeLinecap="round" strokeLinejoin="round" d="M6 3.75h12v16.5l-6-4-6 4V3.75z" />
    </svg>
  );
}

export function ShareIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <circle cx="18" cy="5" r="2.5" />
      <circle cx="6" cy="12" r="2.5" />
      <circle cx="18" cy="19" r="2.5" />
      <path strokeLinecap="round" d="M8.2 10.7l7.6-4.4M8.2 13.3l7.6 4.4" />
    </svg>
  );
}

export function CloseIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <path strokeLinecap="round" d="M6 6l12 12M18 6L6 18" />
    </svg>
  );
}

export function BackArrowIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M15 5l-7 7 7 7" />
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
