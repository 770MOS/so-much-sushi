import type { Metadata } from "next";
import HiddenPage from "@/components/lists/HiddenPage";

export const metadata: Metadata = {
  title: "Hidden places · So Much Sushi",
  robots: { index: false },
};

export default function Hidden() {
  return <HiddenPage />;
}
