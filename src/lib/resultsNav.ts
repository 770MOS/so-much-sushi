// Changes to a search made on the results page itself (a filter, the view, the map area, a new
// search from the header) go into the address with the browser's own history, which Next.js's
// router follows (useSearchParams updates; see "Using the native History API" in the Next.js
// docs). Nothing about a search is read on the server, so there's no need to ask it for the page
// again. (Measured on production builds: router.replace and router.push left the address
// unchanged, or went back to the first one, when the page had been opened with a query already
// in it, e.g. a shared search; 2026-11-12 and 2026-11-13.)
//
// While a place panel is open over the results page the address is the place's (/venue/<id>).
// A change to the search then first goes Back to the results (closing the panel the way Back
// and Close do), and changes the address from there.
//
// push: a new entry Back returns from (a new place or area); replace: the same search,
// refined (filters, view, sort).

function onResultsPath() {
  return window.location.pathname === "/";
}

function backToResults(then: () => void) {
  function onPop() {
    window.removeEventListener("popstate", onPop);
    // Next.js handles the same event first (it put its listener in place earlier).
    requestAnimationFrame(() => {
      if (onResultsPath()) then();
    });
  }
  window.addEventListener("popstate", onPop);
  window.history.back();
}

export function replaceResults(href: string) {
  if (onResultsPath()) window.history.replaceState(null, "", href);
  else backToResults(() => window.history.replaceState(null, "", href));
}

export function pushResults(href: string) {
  if (onResultsPath()) window.history.pushState(null, "", href);
  else backToResults(() => window.history.pushState(null, "", href));
}
