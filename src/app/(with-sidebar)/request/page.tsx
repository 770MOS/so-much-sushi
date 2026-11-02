import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { isAdmin } from "@/lib/admin";
import RequestPlaceForm, { type PlaceKind } from "@/components/RequestPlaceForm";
import { submitPlaceRequest } from "./actions";

export const metadata: Metadata = {
  title: "Request a place · So Much Sushi",
  robots: { index: false, follow: false },
};

type MyRequest = {
  id: number; name: string; main_category: string; city: string | null; state: string | null; status: string;
  place_id: string | null; created_at: string; decided_at: string | null;
};

const STATUS: Record<string, { label: string; className: string }> = {
  pending: { label: "Waiting for review", className: "text-zinc-600 dark:text-zinc-400" },
  added: { label: "Added", className: "text-green-700 dark:text-green-400" },
  already_listed: { label: "Already listed", className: "text-blue-600 dark:text-blue-400" },
  declined: { label: "Not added", className: "text-zinc-500 dark:text-zinc-500" },
};

// Main categories in the order people think of them; any new ones follow alphabetically.
const KIND_ORDER = ["restaurants", "drinks", "coffee", "markets"];

function shortDate(iso: string) {
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

export default async function RequestPlace({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/sign-in");

  const nameParam = (await searchParams).name;
  const initialName = (Array.isArray(nameParam) ? nameParam[0] : nameParam)?.trim().slice(0, 200) ?? "";

  const [catsRes, mineRes, admin] = await Promise.all([
    supabase.from("categories").select("name, path"),
    supabase.rpc("my_place_requests"),
    isAdmin(user.id),
  ]);
  const kinds: PlaceKind[] = (catsRes.data ?? [])
    .map((c) => ({ path: String(c.path), name: String(c.name) }))
    .filter((c) => !c.path.includes("."))
    .sort((a, b) => {
      const ia = KIND_ORDER.indexOf(a.path), ib = KIND_ORDER.indexOf(b.path);
      if (ia !== ib) return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
      return a.name.localeCompare(b.name);
    });
  const mine = (mineRes.data ?? []) as MyRequest[];

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-white px-6 pt-10 pb-16 dark:bg-black">
      <div className="flex w-full max-w-xl flex-col gap-10">
        <div className="flex flex-col gap-2">
          <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">Request a place</h1>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Know a restaurant, bar, coffee shop, bakery or market that isn&apos;t here? Tell us where it is and we&apos;ll check it and add it.
          </p>
        </div>

        {kinds.length === 0 ? (
          <p className="text-sm text-red-600 dark:text-red-400">Something went wrong loading this page. Please try again.</p>
        ) : (
          <RequestPlaceForm kinds={kinds} initialName={initialName} isAdmin={admin} action={submitPlaceRequest} />
        )}

        {mine.length > 0 && (
          <section className="flex flex-col gap-3">
            <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">Your requests</h2>
            <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
              {mine.map((r) => {
                const status = STATUS[r.status] ?? { label: r.status, className: "" };
                return (
                  <li key={r.id} className="flex items-start justify-between gap-4 py-3">
                    <div className="flex flex-col gap-0.5">
                      {r.place_id ? (
                        <Link href={`/venue/${r.place_id}`} className="w-fit font-medium text-zinc-950 hover:underline dark:text-zinc-50">
                          {r.name}
                        </Link>
                      ) : (
                        <span className="font-medium text-zinc-950 dark:text-zinc-50">{r.name}</span>
                      )}
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">
                        {[r.main_category, [r.city, r.state].filter(Boolean).join(", ")].filter(Boolean).join(" · ")}
                      </span>
                    </div>
                    <div className="flex shrink-0 flex-col items-end gap-0.5 text-right">
                      <span className={`text-sm font-medium ${status.className}`}>{status.label}</span>
                      <span className="text-xs text-zinc-500 dark:text-zinc-400">Sent {shortDate(r.created_at)}</span>
                      {admin && r.status === "pending" && (
                        <Link href={`/admin/review/requests/${r.id}`} className="text-xs underline text-zinc-600 dark:text-zinc-400">
                          Review
                        </Link>
                      )}
                    </div>
                  </li>
                );
              })}
            </ul>
          </section>
        )}
      </div>
    </main>
  );
}
