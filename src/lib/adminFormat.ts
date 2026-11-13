// Small display helpers for the admin screens.

export { formatPhone, websiteHost } from "@/lib/format";

export function place(city: string | null, state: string | null): string {
  return [city, state].filter(Boolean).join(", ");
}
