import { notFound } from "next/navigation";
import { getEntityDetail } from "@/lib/getEntityDetail";
import VenueDetail from "@/components/VenueDetail";

// Real, standalone route - what direct navigation (typed URL, a shared
// link, a search engine crawler hitting sitemap.xml) renders. Clicking a
// venue from search results/map popups/list rows instead opens the same
// content as a modal via the intercepted route at
// ../@modal/(.)venue/[id]/page.tsx, which reuses this exact same
// VenueDetail component so the two can never show different content for
// the same entity.
export default async function VenuePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const entity = await getEntityDetail(id);
  if (!entity) notFound();

  return (
    <main className="flex min-h-screen flex-1 justify-center bg-white dark:bg-black">
      <div className="w-full max-w-xl">
        <VenueDetail entity={entity} />
      </div>
    </main>
  );
}
