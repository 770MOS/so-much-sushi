import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getPlaceDetail } from "@/lib/getPlaceDetail";
import { placeKinds } from "@/lib/placeDetail";
import { resultsHref, emptyQuery } from "@/lib/resultsQuery";
import PlaceBody from "@/components/place/PlaceBody";
import PlacePageMap from "@/components/place/PlacePageMap";
import DirectionsMenu from "@/components/place/DirectionsMenu";

// A place's own page: what a shared link, a reload or a search engine opens (opening a place
// from inside the app shows the side panel instead, ../@modal/(.)venue/[id]/page.tsx). The same
// details as the panel, plus a breadcrumb (town › type › cuisine) and a small map with
// Directions. A link to a merged place moves to the place it was merged into.

type Params = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { id } = await params;
  const place = await getPlaceDetail(id);
  if (!place) return { title: "Place not found · So Much Sushi" };
  const { cuisine, type } = placeKinds(place);
  const kind = [cuisine?.name, type?.label].filter(Boolean).join(" · ");
  return {
    title: `${place.name} · So Much Sushi`,
    description: [kind, place.address].filter(Boolean).join(" · "),
  };
}

export default async function PlacePage({ params }: Params) {
  const { id } = await params;
  const place = await getPlaceDetail(id);
  if (!place) notFound();
  if (place.id !== id) redirect(`/venue/${place.id}`);

  const { cuisine, type } = placeKinds(place);
  const town = [place.city, place.state].filter(Boolean).join(", ");
  const crumbs = [
    town ? { label: town, href: resultsHref({ ...emptyQuery(), where: town }) } : null,
    town && type ? { label: type.label, href: resultsHref({ ...emptyQuery(), where: town, kind: type.key }) } : null,
    town && cuisine ? { label: cuisine.name, href: resultsHref({ ...emptyQuery(), where: town, kind: cuisine.path }) } : null,
  ].filter((c): c is { label: string; href: string } => c !== null);

  return (
    <main className="mx-auto flex w-full max-w-[1120px] flex-1 flex-col gap-7 px-5 pb-14 pt-6 md:px-6">
      {crumbs.length > 0 && (
        <nav aria-label="Breadcrumb">
          <ol className="flex flex-wrap items-center gap-1.5 text-sm text-muted">
            {crumbs.map((c, i) => (
              <li key={c.href} className="flex items-center gap-1.5">
                {i > 0 && <span aria-hidden="true">›</span>}
                <Link href={c.href} className="hover:text-zinc-950 hover:underline">
                  {c.label}
                </Link>
              </li>
            ))}
          </ol>
        </nav>
      )}
      <div className="flex flex-wrap gap-x-10 gap-y-8">
        <div className="min-w-0 flex-[1_1_520px]">
          <PlaceBody place={place} layout="page" />
        </div>
        <div className="flex min-w-0 flex-[0_1_440px] flex-col gap-3">
          <PlacePageMap place={place} />
          <div>
            <DirectionsMenu place={place} look="button" align="left" />
          </div>
        </div>
      </div>
    </main>
  );
}
