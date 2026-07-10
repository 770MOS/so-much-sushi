export const HANDLE_PATTERN = /^[a-z0-9_]{3,20}$/;
export const HANDLE_HINT = "3-20 characters: lowercase letters, numbers, and underscores only.";

const HANDLE_TAKEN_MESSAGE = "That handle is already taken. Please choose another.";

export function handleTakenMessage(): string {
  return HANDLE_TAKEN_MESSAGE;
}

// Postgres unique_violation, as returned by a direct PostgREST table
// operation (e.g. updating profiles.handle). Note: this does NOT reliably
// detect a handle collision surfaced through supabase.auth.signUp() - that
// path fails inside a DB trigger during account creation, and the auth-js
// SDK doesn't parse that particular error shape into a `.code` the same
// way, so callers on that path should pre-check availability instead of
// relying on this after the fact.
export function isHandleTakenError(error: { code?: string } | null | undefined): boolean {
  return error?.code === "23505";
}
