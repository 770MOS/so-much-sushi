// Small display helpers shared by the site and the admin screens.

// US numbers as (703) 983-1548; anything else (another country, an extension,
// too few digits) is shown as the source gave it.
export function formatPhone(raw: string | null): string {
  if (!raw) return "";
  const digits = raw.replace(/\D/g, "").replace(/^1(?=\d{10}$)/, "");
  if (digits.length !== 10) return raw;
  return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
}

// A tel: link a phone can dial: +1 and ten digits for US numbers, otherwise the
// digits and any leading + as given.
export function phoneHref(raw: string): string {
  const digits = raw.replace(/\D/g, "").replace(/^1(?=\d{10}$)/, "");
  if (digits.length === 10) return `tel:+1${digits}`;
  return `tel:${raw.trim().startsWith("+") ? "+" : ""}${raw.replace(/\D/g, "")}`;
}

export function websiteHost(raw: string | null): string {
  if (!raw) return "";
  try {
    return new URL(raw.includes("://") ? raw : `https://${raw}`).hostname.replace(/^www\./, "");
  } catch {
    return raw;
  }
}
