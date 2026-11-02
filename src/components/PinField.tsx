"use client";

import dynamic from "next/dynamic";
import { useState } from "react";
import type { Pin } from "@/components/MapPicker";

// The map library needs a browser, so the map is loaded on the client only.
const MapPicker = dynamic(() => import("@/components/MapPicker"), {
  ssr: false,
  loading: () => <div className="h-80 w-full rounded-xl border border-neutral-200 bg-neutral-50 dark:border-zinc-800 dark:bg-zinc-900" />,
});

// A map pin as two hidden form fields, "lat" and "lng". The fields are here rather than
// in the map so a pin that was already set (e.g. from a place request) is sent even if
// the form is submitted before the map has loaded.
export default function PinField({
  initial,
  addressFieldIds,
  locate,
  startAtLastSearch,
}: {
  initial: Pin;
  addressFieldIds: string[];
  locate?: boolean;
  startAtLastSearch?: boolean;
}) {
  const [pin, setPin] = useState<Pin>(initial);
  return (
    <>
      <MapPicker pin={pin} onPin={setPin} addressFieldIds={addressFieldIds} locate={locate} startAtLastSearch={startAtLastSearch} />
      <input type="hidden" name="lat" value={pin?.lat ?? ""} />
      <input type="hidden" name="lng" value={pin?.lng ?? ""} />
    </>
  );
}
