import type { Metadata } from "next";
import FriendsPage from "@/components/friends/FriendsPage";

export const metadata: Metadata = {
  title: "Friends · So Much Sushi",
  robots: { index: false },
};

export default function Friends() {
  return <FriendsPage />;
}
