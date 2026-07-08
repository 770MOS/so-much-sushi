export type EntityStatus = "active" | "temporarily_closed" | "permanently_closed";

export function isNonActive(status: string): boolean {
  return status !== "active";
}

export function closedLabel(status: string): string | null {
  if (status === "temporarily_closed") return "Temporarily closed";
  if (status === "permanently_closed") return "Closed";
  return null;
}
