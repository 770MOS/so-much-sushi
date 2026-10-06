import { mainCategories, tagsUnder, type Category } from "@/lib/adminCategories";

// Checkbox list of every tag, grouped under its main category and indented by level.
// Plain form checkboxes (name="tag"), so it works in both the filter and the editor.
export default function TagChecklist({ categories, selected }: { categories: Category[]; selected: string[] }) {
  const chosen = new Set(selected);
  return (
    <div className="flex flex-col gap-3">
      {mainCategories(categories).map((main) => (
        <fieldset key={main.path} className="min-w-0">
          <legend className="px-1 text-xs font-medium text-neutral-500">{main.name}</legend>
          <div className="gap-x-6 sm:columns-2">
            {tagsUnder(categories, main.path).map((tag) => (
              <label
                key={tag.path}
                className="flex min-h-11 cursor-pointer break-inside-avoid items-center gap-2 rounded-md px-1 hover:bg-neutral-100"
                style={{ paddingLeft: `${4 + (tag.depth - 2) * 18}px` }}
              >
                <input type="checkbox" name="tag" value={tag.path} defaultChecked={chosen.has(tag.path)} className="h-4 w-4 shrink-0 accent-neutral-900" />
                <span>{tag.name}</span>
              </label>
            ))}
          </div>
        </fieldset>
      ))}
    </div>
  );
}
