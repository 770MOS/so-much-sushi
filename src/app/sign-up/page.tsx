"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { HANDLE_PATTERN, HANDLE_HINT, handleTakenMessage } from "@/lib/handleValidation";

const MIN_PASSWORD_LENGTH = 8;
// Project's configured password policy also requires at least one of each
// character class (checked here client-side for instant feedback - the
// server enforces the same policy regardless, so this doesn't loosen
// anything, it just avoids a round trip for an obviously-weak password).
const PASSWORD_HINT =
  "At least 8 characters, with an uppercase letter, a lowercase letter, a number, and a special character.";

function passwordMeetsPolicy(password: string) {
  return (
    password.length >= MIN_PASSWORD_LENGTH &&
    /[a-z]/.test(password) &&
    /[A-Z]/.test(password) &&
    /[0-9]/.test(password) &&
    /[^A-Za-z0-9]/.test(password)
  );
}

const inputClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50";

export default function SignUp() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [name, setName] = useState("");
  const [handle, setHandle] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (loading) return;

    setError(null);

    const trimmedName = name.trim();
    if (!trimmedName) {
      setError("Please enter your name.");
      return;
    }
    const trimmedHandle = handle.trim().toLowerCase();
    if (!HANDLE_PATTERN.test(trimmedHandle)) {
      setError(`Username doesn't meet the requirements. ${HANDLE_HINT}`);
      return;
    }
    if (!passwordMeetsPolicy(password)) {
      setError(`Password doesn't meet the requirements. ${PASSWORD_HINT}`);
      return;
    }
    if (password !== confirmPassword) {
      setError("Passwords don't match.");
      return;
    }

    setLoading(true);
    const supabase = createClient();

    // signUp() sets profiles.handle via a DB trigger during account
    // creation (see supabase/add_handle_to_signup_trigger.sql), so a
    // collision fails inside that trigger rather than as a normal PostgREST
    // update - the auth-js SDK doesn't parse that error shape into a usable
    // .code the way it does for a direct table update. Pre-checking
    // availability here catches the common case with a proper friendly
    // message and avoids that ambiguity, rather than trying to detect it
    // after the fact.
    const { data: existingHandle } = await supabase
      .from("profiles")
      .select("id")
      .eq("handle", trimmedHandle)
      .maybeSingle();
    if (existingHandle) {
      setLoading(false);
      setError(handleTakenMessage());
      return;
    }

    const { data, error: signUpError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { handle: trimmedHandle, display_name: trimmedName },
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    });
    setLoading(false);

    if (signUpError) {
      if (signUpError.code === "user_already_exists" || signUpError.code === "email_exists") {
        setError("An account with that email already exists. Try signing in instead.");
      } else if (signUpError.code === "weak_password") {
        setError(`Password doesn't meet the requirements. ${PASSWORD_HINT}`);
      } else {
        setError("Something went wrong creating your account. Please try again.");
      }
      return;
    }

    // Supabase responds with a "success" payload (no error) but an empty
    // identities array when the email is already registered and confirmed -
    // done to avoid leaking which emails exist. Same friendly message.
    if (data.user && data.user.identities && data.user.identities.length === 0) {
      setError("An account with that email already exists. Try signing in instead.");
      return;
    }

    if (data.session) {
      // Only happens if email confirmation isn't required for this project;
      // handle it defensively even though "Confirm email" is on today.
      router.push("/");
      router.refresh();
      return;
    }

    setSent(true);
  }

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-white px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-xl flex-col gap-10">
        <div className="flex flex-col gap-2">
          <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">Sign up</h1>
          <p className="text-zinc-600 dark:text-zinc-400">
            Create an account to star places, make lists, and connect with friends.
          </p>
        </div>

        {sent ? (
          <p className="text-zinc-700 dark:text-zinc-300">
            Check your email to confirm your account before signing in.
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
                required
                placeholder="you@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className={inputClass}
              />
            </div>

            <div className="flex flex-col gap-2">
              <label
                htmlFor="name"
                className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
              >
                Name
              </label>
              <input
                id="name"
                type="text"
                required
                maxLength={80}
                placeholder="Your name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                className={inputClass}
              />
            </div>

            <div className="flex flex-col gap-2">
              <label
                htmlFor="handle"
                className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
              >
                Username
              </label>
              <div className="flex items-center gap-1">
                <span className="text-zinc-400">@</span>
                <input
                  id="handle"
                  type="text"
                  required
                  maxLength={20}
                  placeholder="username"
                  value={handle}
                  onChange={(e) => setHandle(e.target.value)}
                  className={inputClass}
                />
              </div>
              <p className="text-xs text-zinc-500 dark:text-zinc-400">{HANDLE_HINT}</p>
            </div>

            <div className="flex flex-col gap-2">
              <label
                htmlFor="password"
                className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
              >
                Password
              </label>
              <input
                id="password"
                type="password"
                required
                placeholder="Create a password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className={inputClass}
              />
              <p className="text-xs text-zinc-500 dark:text-zinc-400">{PASSWORD_HINT}</p>
            </div>

            <div className="flex flex-col gap-2">
              <label
                htmlFor="confirm-password"
                className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
              >
                Confirm password
              </label>
              <input
                id="confirm-password"
                type="password"
                required
                placeholder="Re-enter your password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                className={inputClass}
              />
            </div>

            {error && <p className="text-sm text-red-600 dark:text-red-400">{error}</p>}

            <button
              type="submit"
              disabled={
                loading || !email.trim() || !name.trim() || !handle.trim() || !password || !confirmPassword
              }
              className="w-full rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
            >
              {loading ? "Creating account…" : "Sign up"}
            </button>

            <p className="text-sm text-zinc-500 dark:text-zinc-400">
              Already have an account?{" "}
              <Link
                href="/sign-in"
                className="underline hover:text-zinc-900 dark:hover:text-zinc-100"
              >
                Sign in
              </Link>
            </p>
          </form>
        )}
      </div>
    </main>
  );
}
