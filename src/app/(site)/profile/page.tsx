import { redirect } from "next/navigation";

// The old account page; its settings now live on /settings and its favorites on /favorites.
export default function Profile() {
  redirect("/settings");
}
