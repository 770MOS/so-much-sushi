// Client-side navigation to a route that no longer matches @modal's only
// real page ((.)venue/[id]) leaves that slot's last content visible by
// default (Next.js's parallel-routes behavior keeps a slot's subpage
// "active" across soft navigations that don't touch it) - so without this,
// clicking a sidebar link while the venue modal is open would leave it
// stuck open over whatever page you navigated to. Matching this catch-all
// to null clears it instead. See the Next.js parallel-routes docs' own
// "Closing the modal" example, which uses the same pattern.
export default function CatchAll() {
  return null;
}
