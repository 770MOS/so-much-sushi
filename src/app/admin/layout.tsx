import type { Metadata } from "next";
import Link from "next/link";
import { requireAdmin } from "@/lib/admin";

export const metadata: Metadata = {
  title: "Admin · So Much Sushi",
  robots: { index: false, follow: false },
};

// Which database this deployment talks to, shown so it is never ambiguous.
function environmentLabel() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  if (url.includes("mfngcidhbzjexbxtgbeh")) return "SANDBOX";
  if (url.includes("ajkgveeuurzltttdfhgv")) return "PRODUCTION";
  return "UNKNOWN DATABASE";
}

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const { email } = await requireAdmin();
  const env = environmentLabel();

  return (
    <div className="flex min-h-screen flex-1 flex-col bg-white font-sans text-sm text-neutral-900">
      <header className="flex min-h-13 flex-wrap items-center justify-between gap-3 border-b border-neutral-200 px-4 py-2">
        <div className="flex flex-wrap items-center gap-2.5">
          <span className="inline-block h-5.5 w-5.5 rounded-md bg-orange-700" aria-hidden="true" />
          <Link href="/" className="font-semibold hover:text-orange-700">
            So Much Sushi
          </Link>
          <span className="text-neutral-400">/</span>
          <span className="text-neutral-600">Admin</span>
          <span
            className={`rounded-full border px-2 py-px text-[11px] font-medium tracking-wide ${
              env === "PRODUCTION" ? "border-red-300 bg-red-50 text-red-800" : "border-neutral-300 text-neutral-600"
            }`}
          >
            {env}
          </span>
        </div>
        <span className="text-xs text-neutral-600">{email}</span>
      </header>
      <div className="flex flex-1 flex-col sm:flex-row">
        <nav aria-label="Admin" className="flex flex-col gap-0.5 border-b border-neutral-200 bg-neutral-50 p-2 sm:w-56 sm:shrink-0 sm:border-b-0 sm:border-r">
          <Link href="/admin/review" className="flex min-h-11 items-center rounded-lg px-2.5 font-medium text-neutral-900 hover:bg-neutral-200/70">
            Review queue
          </Link>
          <span className="flex min-h-11 items-center rounded-lg px-2.5 text-neutral-400">All places (coming next)</span>
          <span className="flex min-h-11 items-center rounded-lg px-2.5 text-neutral-400">Categories and tags (coming next)</span>
        </nav>
        <main className="flex min-w-0 flex-1 flex-col">{children}</main>
      </div>
    </div>
  );
}
