import type { Metadata } from "next";
import FavoritesPage from "@/components/lists/FavoritesPage";

export const metadata: Metadata = {
  title: "Your favorites · So Much Sushi",
  robots: { index: false },
};

export default function Favorites() {
  return <FavoritesPage />;
}
