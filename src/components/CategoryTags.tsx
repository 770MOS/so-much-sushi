import type { EntityType } from "@/lib/entityTypes";

// Each tag is coloured by its main category, so the kind of place reads at a glance.
// All four colours keep white text above 4.5:1 contrast.
const TAG_COLOURS: Record<Exclude<EntityType, "all">, string> = {
  restaurants: "bg-blue-600",
  drinks: "bg-purple-600",
  coffee: "bg-amber-700",
  markets: "bg-emerald-700",
};

function colourFor(path: string | undefined): string {
  const root = path?.split(".")[0] as Exclude<EntityType, "all"> | undefined;
  return (root && TAG_COLOURS[root]) || "bg-zinc-600";
}

// names and paths come from the database in the same order, main category first.
export default function CategoryTags({
  names,
  paths,
}: {
  names: string[] | null | undefined;
  paths: string[] | null | undefined;
}) {
  if (!names || names.length === 0) return null;
  return (
    <div className="flex flex-wrap gap-1.5">
      {names.map((name, i) => (
        <span
          key={`${name}-${i}`}
          className={`rounded-full px-2 py-0.5 text-xs font-medium text-white ${colourFor(paths?.[i])}`}
        >
          {name}
        </span>
      ))}
    </div>
  );
}
