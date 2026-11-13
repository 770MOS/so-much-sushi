import { notFound } from "next/navigation";
import { getEntityDetail } from "@/lib/getEntityDetail";
import VenueDetail from "@/components/VenueDetail";
import VenueModal from "@/components/VenueModal";

// Intercepts client-side navigation to /venue/[id] (from search results,
// map popups, or list rows) and renders the same content as a modal
// instead of a full page transition - the URL still genuinely updates to
// /venue/[id], scroll position/state on the page behind it is preserved.
// A hard navigation (typed URL, shared link, refresh) never hits this file
// at all; it goes straight to ../../../venue/[id]/page.tsx.
export default async function InterceptedVenuePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const entity = await getEntityDetail(id);
  if (!entity) notFound();

  return (
    <VenueModal>
      <VenueDetail entity={entity} />
    </VenueModal>
  );
}
