// A person's initial in a soft colour picked from their handle (or name), so the same person
// always gets the same colour. Used on the Friends, friend and list pages.
const COLORS = [
  ["#e7f4ec", "#17603a"],
  ["#e8eefb", "#2c4a9a"],
  ["#fbeef2", "#9c2c4e"],
  ["#fff1e0", "#8a4b00"],
  ["#f1e8fb", "#5b2c8f"],
];

export function avatarColors(seed: string): [string, string] {
  let h = 0;
  for (const c of seed) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  const [bg, fg] = COLORS[h % COLORS.length];
  return [bg, fg];
}

export default function Avatar({ name, seed, size = 40 }: { name: string; seed?: string | null; size?: number }) {
  const [bg, fg] = avatarColors(seed || name);
  return (
    <span
      aria-hidden="true"
      className="flex shrink-0 items-center justify-center rounded-full font-medium"
      style={{ width: size, height: size, background: bg, color: fg, fontSize: Math.round(size * 0.4) }}
    >
      {name.trim().charAt(0).toUpperCase() || "?"}
    </span>
  );
}
