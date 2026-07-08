"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function AuthCallback() {
  const router = useRouter();
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function completeSignIn() {
      await Promise.resolve();
      const code = new URLSearchParams(window.location.search).get("code");
      const supabase = createClient();
      const { error: exchangeError } = code
        ? await supabase.auth.exchangeCodeForSession(code)
        : { error: new Error("Missing code parameter") };

      if (cancelled) return;
      if (exchangeError) setError(true);
      else router.replace("/");
    }

    completeSignIn();

    return () => {
      cancelled = true;
    };
  }, [router]);

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center justify-center bg-white px-6 text-center dark:bg-black">
      {error ? (
        <p className="text-zinc-600 dark:text-zinc-400">
          That sign-in link is invalid or has expired.{" "}
          <a href="/sign-in" className="underline">
            Try again
          </a>
          .
        </p>
      ) : (
        <p className="text-zinc-600 dark:text-zinc-400">Signing you in…</p>
      )}
    </main>
  );
}
