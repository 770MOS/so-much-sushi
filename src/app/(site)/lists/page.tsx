import { Suspense } from "react";
import type { Metadata } from "next";
import ListsPage from "@/components/lists/ListsPage";

export const metadata: Metadata = {
  title: "Your lists · So Much Sushi",
  robots: { index: false },
};

export default function Lists() {
  return (
    <Suspense fallback={<main className="flex-1" />}>
      <ListsPage />
    </Suspense>
  );
}
