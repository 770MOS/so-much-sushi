"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { safeNext } from "@/lib/friends";

export default function AuthCallback() {
  const router = useRouter();
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function completeConfirmation() {
      await Promise.resolve();
      const params = new URLSearchParams(window.location.search);
      const code = params.get("code");
      const supabase = createClient();
      const { error: exchangeError } = code
        ? await supabase.auth.exchangeCodeForSession(code)
        : { error: new Error("Missing code parameter") };

      if (cancelled) return;
      if (exchangeError) setError(true);
      else router.replace(safeNext(params.get("next")) ?? "/");
    }

    completeConfirmation();

    return () => {
      cancelled = true;
    };
  }, [router]);

  return (
    <main className="flex flex-1 flex-col items-center justify-center bg-white px-6 text-center dark:bg-black">
      {error ? (
        <p className="text-zinc-600 dark:text-zinc-400">
          That confirmation link is invalid or has expired.{" "}
          <Link href="/sign-up" className="underline">
            Try signing up again
          </Link>
          .
        </p>
      ) : (
        <p className="text-zinc-600 dark:text-zinc-400">Confirming your email…</p>
      )}
    </main>
  );
}
