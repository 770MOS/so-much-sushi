"use client";

import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

export default function SignIn() {
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!email.trim() || loading) return;

    setLoading(true);
    setError(null);

    const supabase = createClient();
    const { error: signInError } = await supabase.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    });

    if (signInError) {
      setError("Something went wrong sending the sign-in link. Please try again.");
    } else {
      setSent(true);
    }

    setLoading(false);
  }

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-white px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-xl flex-col gap-10">
        <div className="flex flex-col gap-2">
          <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">Sign in</h1>
          <p className="text-zinc-600 dark:text-zinc-400">
            Enter your email and we&apos;ll send you a sign-in link.
          </p>
        </div>

        {sent ? (
          <p className="text-zinc-700 dark:text-zinc-300">
            Check your email for a link to sign in.
          </p>
        ) : (
          <form onSubmit={handleSubmit} className="flex flex-col gap-8">
            <div className="flex flex-col gap-2">
              <label
                htmlFor="email"
                className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
              >
                Email
              </label>
              <input
                id="email"
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full rounded-lg border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
              />
            </div>

            {error && <p className="text-sm text-red-600 dark:text-red-400">{error}</p>}

            <button
              type="submit"
              disabled={loading || !email.trim()}
              className="w-full rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
            >
              {loading ? "Sending…" : "Send sign-in link"}
            </button>
          </form>
        )}
      </div>
    </main>
  );
}
