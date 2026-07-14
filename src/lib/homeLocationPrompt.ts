// Tracks, per-device, whether a given user has already dismissed the
// first-sign-in "set your home location?" prompt - scoped by user id since
// multiple accounts can sign into the same browser. Deliberately permanent
// (localStorage, not sessionStorage): skipping means "don't ask me again on
// this device," not "don't ask for the rest of this session."
const KEY_PREFIX = "sms:homeLocationDismissed:";

export function isHomeLocationPromptDismissed(userId: string): boolean {
  if (typeof window === "undefined") return false;
  try {
    return localStorage.getItem(KEY_PREFIX + userId) === "1";
  } catch {
    return false;
  }
}

export function dismissHomeLocationPrompt(userId: string) {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(KEY_PREFIX + userId, "1");
  } catch {
    // ignore - e.g. private browsing storage restrictions
  }
}
