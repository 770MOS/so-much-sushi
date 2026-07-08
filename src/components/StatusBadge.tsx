import { closedLabel } from "@/lib/entityStatus";

export default function StatusBadge({ status }: { status: string }) {
  const label = closedLabel(status);
  if (!label) return null;

  const isPermanent = status === "permanently_closed";

  return (
    <span
      className={`inline-flex w-fit items-center rounded-full px-2 py-0.5 text-xs font-medium ${
        isPermanent
          ? "bg-zinc-200 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"
          : "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300"
      }`}
    >
      {label}
    </span>
  );
}
