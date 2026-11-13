import Link from "next/link";
import type { ReactNode } from "react";

// What a visitor sees on the Favorites and Lists pages: what joining gives, with Join free and
// Sign in (the same wording as the join note on the results page, option B).
export default function JoinPanel({ icon, title, body }: { icon: ReactNode; title: string; body: string }) {
  return (
    <main className="flex flex-1 flex-col items-center px-6 py-16">
      <div className="flex w-full max-w-sm flex-col gap-3">
        <div aria-hidden="true">{icon}</div>
        <h1 className="text-2xl font-medium tracking-tight text-zinc-950">{title}</h1>
        <p className="text-[15px] leading-relaxed text-muted">{body}</p>
        <div className="mt-3 flex flex-col gap-2">
          <Link href="/sign-up" className="flex h-12 items-center justify-center rounded-xl bg-primary text-base font-medium text-white hover:bg-primary-hover">
            Join free
          </Link>
          <Link href="/sign-in" className="flex h-12 items-center justify-center rounded-xl border border-[#dddddd] text-base font-medium text-zinc-950 hover:bg-zinc-50">
            Sign in
          </Link>
        </div>
      </div>
    </main>
  );
}
