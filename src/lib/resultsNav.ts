// Changes to a search made on the results page itself (a filter, the view, the map area) go
// into the address with the browser's own history, which Next.js's router follows
// (useSearchParams updates; see "Using the native History API" in the Next.js docs). Nothing
// about a search is read on the server, so there's no need to ask it for the page again.
// (Measured 2026-11-12 on a production build: router.replace and router.push left the address
// unchanged when the page had been opened with a query already in it, e.g. a shared search.)
//
// push: a new entry Back returns from (a new place or area); replace: the same search,
// refined (filters, view, sort).
export function replaceResults(href: string) {
  window.history.replaceState(null, "", href);
}

export function pushResults(href: string) {
  window.history.pushState(null, "", href);
}
