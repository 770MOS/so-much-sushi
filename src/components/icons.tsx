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

// Friends' favorites: a thumbs up in dark green (Tabler's thumb-up). Darker
// than the rose heart so the two differ for colour-blind people too.
export const THUMB_PATH = "M7 11v8a1 1 0 0 1 -1 1h-2a1 1 0 0 1 -1 -1v-7a1 1 0 0 1 1 -1h3a4 4 0 0 0 4 -4v-1a2 2 0 0 1 4 0v5h3a2 2 0 0 1 2 2l-1 5a2 3 0 0 1 -2 2h-7a3 3 0 0 1 -3 -3";

export function FriendsFavoriteIcon({ size = 14 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" className="text-friends" aria-hidden="true">
      <path d={THUMB_PATH} />
    </svg>
  );
}

// Your favorites: a heart in rose (Tabler's heart). A star would read as a
// rating, and the site has no scores.
export const HEART_PATH = "M19.5 12.572l-7.5 7.428l-7.5 -7.428a5 5 0 1 1 7.5 -6.566a5 5 0 1 1 7.5 6.572";

export function FavoriteIcon({ filled, size = 20 }: { filled: boolean; size?: number }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill={filled ? "var(--favorite)" : "none"}
      stroke={filled ? "#b8335a" : "currentColor"}
      strokeWidth={filled ? 1.4 : 1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={filled ? undefined : "text-zinc-500"}
      aria-hidden="true"
    >
      <path d={HEART_PATH} />
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

// Navigation icons (header and phone tab bar) - outline style, from Tabler Icons.
export function FavoritesNavIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="var(--favorite-ink)" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={HEART_PATH} />
    </svg>
  );
}

export function ListsNavIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M9 6h11M9 12h11M9 18h11M5 6v.01M5 12v.01M5 18v.01" />
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

export function FriendsNavIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M9 7m-4 0a4 4 0 1 0 8 0a4 4 0 1 0 -8 0M3 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2M16 3.13a4 4 0 0 1 0 7.75M21 21v-2a4 4 0 0 0 -3 -3.85" />
    </svg>
  );
}

// The site's mark: three rings, the centre one amber (the only amber left in the look).
export function LogoMark({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 30 30" aria-hidden="true">
      <circle cx="15" cy="15" r="14" fill="#141414" />
      <circle cx="15" cy="15" r="9" fill="#ffffff" />
      <circle cx="15" cy="15" r="4.5" fill="#f2a93b" />
    </svg>
  );
}
