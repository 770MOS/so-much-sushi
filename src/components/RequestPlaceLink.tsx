import Link from "next/link";

// "Can't find it? Request a place", shown under search results. A typed name is carried over.
export default function RequestPlaceLink({ name }: { name?: string }) {
  const q = name?.trim();
  return (
    <p className="text-center text-sm text-zinc-500 dark:text-zinc-400">
      Can&apos;t find a place?{" "}
      <Link
        href={q ? `/request?name=${encodeURIComponent(q)}` : "/request"}
        className="font-medium text-zinc-700 underline hover:text-zinc-950 dark:text-zinc-300 dark:hover:text-zinc-50"
      >
        Request it
      </Link>
    </p>
  );
}
