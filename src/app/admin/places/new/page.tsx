import Link from "next/link";
import { requireAdmin } from "@/lib/admin";
import { loadCategories } from "@/lib/adminCategories";
import AddPlaceForm from "@/components/admin/AddPlaceForm";
import { addPlace } from "../actions";

export default async function NewPlace() {
  const { db } = await requireAdmin();
  const categories = await loadCategories(db);
  return (
    <div className="flex flex-col gap-4 px-4 py-5">
      <div className="flex flex-wrap items-center gap-3">
        <Link href="/admin/places" className="inline-flex min-h-11 items-center underline hover:text-orange-700">All places</Link>
        <span className="text-neutral-400">/</span>
        <h1 className="text-lg font-semibold">Add a place</h1>
      </div>
      <p className="max-w-3xl text-[13px] text-neutral-600">
        For a place no source has yet. Before saving, places nearby with a similar name, or anywhere close with the same phone, are shown so you don&apos;t add one twice.
      </p>
      <AddPlaceForm categories={categories} action={addPlace} />
    </div>
  );
}
