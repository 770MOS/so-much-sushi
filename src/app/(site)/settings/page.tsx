import type { Metadata } from "next";
import SettingsPage from "@/components/settings/SettingsPage";

export const metadata: Metadata = {
  title: "Account settings · So Much Sushi",
  robots: { index: false },
};

export default function Settings() {
  return <SettingsPage />;
}
