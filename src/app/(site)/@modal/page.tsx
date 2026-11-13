// The results page ("/") has no panel of its own: navigating to it (the logo, the Search tab,
// a new search) clears an open place panel. [...catchAll]/page.tsx does the same for every
// other page; a catch-all doesn't match "/" itself.
export default function NoPanel() {
  return null;
}
