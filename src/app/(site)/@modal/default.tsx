// Renders for the @modal slot whenever the current route isn't the
// intercepted (.)venue/[id] page - both on a hard reload/initial load (per
// Next's parallel-routes convention) and, via the catch-all in
// [...catchAll]/page.tsx, on client-side navigation elsewhere too.
export default function Default() {
  return null;
}
