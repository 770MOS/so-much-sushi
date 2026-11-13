// The project's password policy, checked in the browser for instant feedback (Supabase
// enforces the same rules regardless). Used by sign-up and account settings.
const MIN_PASSWORD_LENGTH = 8;
// Project's configured password policy also requires at least one of each
// character class (checked here client-side for instant feedback - the
// server enforces the same policy regardless, so this doesn't loosen
// anything, it just avoids a round trip for an obviously-weak password).
export const PASSWORD_HINT =
  "At least 8 characters, with an uppercase letter, a lowercase letter, a number, and a special character.";

export function passwordMeetsPolicy(password: string) {
  return (
    password.length >= MIN_PASSWORD_LENGTH &&
    /[a-z]/.test(password) &&
    /[A-Z]/.test(password) &&
    /[0-9]/.test(password) &&
    /[^A-Za-z0-9]/.test(password)
  );
}
