import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import PersonView from "@/components/friends/PersonView";
import type { PersonPageData } from "@/lib/friends";

// A person's page (/u/<handle>): a friend's favorites and shared lists, or for anyone else
// their name, how you're connected and their public lists (public.person_page).

type Params = { params: Promise<{ handle: string }> };

const getPerson = cache(async (handle: string): Promise<PersonPageData | null> => {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("person_page", { person_handle: decodeURIComponent(handle) });
  if (error || !data) return null;
  return data as PersonPageData;
});

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { handle } = await params;
  const person = await getPerson(handle);
  return {
    title: person ? `${person.name} · So Much Sushi` : "Not found · So Much Sushi",
    robots: { index: false },
  };
}

export default async function PersonPage({ params }: Params) {
  const { handle } = await params;
  const person = await getPerson(handle);
  if (!person) notFound();
  return <PersonView key={person.id} initial={person} />;
}
