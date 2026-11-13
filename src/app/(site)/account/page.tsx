import type { Metadata } from "next";
import AccountHome from "@/components/settings/AccountHome";

export const metadata: Metadata = {
  title: "Account · So Much Sushi",
  robots: { index: false },
};

export default function Account() {
  return <AccountHome />;
}
