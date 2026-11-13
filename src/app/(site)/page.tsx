import { Suspense } from "react";
import ResultsPage from "@/components/results/ResultsPage";

// The results page reads the search from the address, which happens in the browser; the
// boundary lets the rest of the page be prerendered.
export default function Home() {
  return (
    <Suspense fallback={<main className="flex-1" />}>
      <ResultsPage />
    </Suspense>
  );
}
