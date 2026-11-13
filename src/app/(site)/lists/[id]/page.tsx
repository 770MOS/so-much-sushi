import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getListPage, isHidden } from "@/lib/getListPage";
import { createClient } from "@/lib/supabase/server";
import { placeWord } from "@/lib/lists";
import ListView from "@/components/lists/ListView";

// One list (mocked 2026-11-12): its places in the list-and-map layout. The owner can add
// places, change who can see it, share, edit and remove places. Public lists are open to
// anyone, signed in or not, and to search engines; Friends lists to the owner's friends.

type Params = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { id } = await params;
  const list = await getListPage(id);
  if (!list || isHidden(list)) return { title: "A list · So Much Sushi", robots: { index: false } };
  const n = list.places.length;
  const towns = [...new Set(list.places.map((p) => p.city).filter(Boolean))].slice(0, 3).join(", ");
  return {
    title: `${list.name} — a list by ${list.owner.name} · So Much Sushi`,
    description: list.description ?? `${n} ${placeWord(n)}${towns ? ` in ${towns}` : ""}.`,
    robots: list.visibility === "public" ? undefined : { index: false },
  };
}

export default async function ListPage({ params }: Params) {
  const { id } = await params;
  const list = await getListPage(id);
  if (!list) notFound();

  if (isHidden(list)) {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    return (
      <main className="flex flex-1 flex-col items-center px-6 py-16">
        <div className="flex w-full max-w-sm flex-col gap-3">
          <h1 className="text-2xl font-medium tracking-tight text-zinc-950">This list isn&apos;t shared with you</h1>
          <p className="text-[15px] leading-relaxed text-muted">
            {user
              ? "Its owner keeps it to themselves or shares it only with their friends."
              : "It may be shared only with the owner's friends. Sign in to see it if it's shared with you."}
          </p>
          <div className="mt-3 flex flex-col gap-2">
            {user ? (
              <Link href="/lists" className="flex h-12 items-center justify-center rounded-xl bg-primary text-base font-medium text-white hover:bg-primary-hover">
                Your lists
              </Link>
            ) : (
              <>
                <Link href="/sign-in" className="flex h-12 items-center justify-center rounded-xl bg-primary text-base font-medium text-white hover:bg-primary-hover">
                  Sign in
                </Link>
                <Link href="/sign-up" className="flex h-12 items-center justify-center rounded-xl border border-[#dddddd] text-base font-medium text-zinc-950 hover:bg-zinc-50">
                  Join free
                </Link>
              </>
            )}
          </div>
        </div>
      </main>
    );
  }

  return <ListView key={list.id} initial={list} />;
}
