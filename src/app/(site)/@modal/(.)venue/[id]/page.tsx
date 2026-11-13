import { getPlaceDetail } from "@/lib/getPlaceDetail";
import PlacePanel from "@/components/place/PlacePanel";

// Opening a place from a page in the app (a result, a map pin, a list row) lands here instead
// of on the full page: the address still changes to /venue/<id>, and the page behind stays as
// it was. Typing or sharing the link, or reloading, goes to ../../../venue/[id]/page.tsx.
export default async function PlacePanelRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const place = await getPlaceDetail(id);
  return <PlacePanel place={place ?? "missing"} />;
}
