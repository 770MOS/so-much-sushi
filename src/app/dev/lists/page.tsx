import type { Metadata } from "next";
import ListsCheck from "./ListsCheck";

export const metadata: Metadata = {
  title: "Dropdown check",
  robots: { index: false, follow: false },
};

// A check for Safari: the search boxes' suggestion lists in several builds, side by side over the
// map, their rows changing on their own as if someone were typing (2026-11-19). Open it in Safari
// and see which lists show their words. Temporary: remove once the lists draw reliably.
export default function DevListsPage() {
  return <ListsCheck />;
}
