import { redirect } from "next/navigation";

// New lists are made from a dialog on the Lists page now; old links open it there.
export default function NewList() {
  redirect("/lists?new=1");
}
