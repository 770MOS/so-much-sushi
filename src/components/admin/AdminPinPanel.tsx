"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import PinFixForm from "@/components/PinFixForm";
import { movePin } from "@/app/actions/pins";
import { metersText } from "@/lib/pins";

// The admin place page's "Map pin" box: where the pin came from, and moving it by hand.
export default function AdminPinPanel({
  placeId,
  lat,
  lng,
  from,
  disabled,
}: {
  placeId: string;
  lat: number;
  lng: number;
  // Where the pin came from, as the page words it ("Edited by hand, …", "Overture … · meta").
  from: string | null;
  disabled: boolean;
}) {
  const router = useRouter();
  const [done, setDone] = useState<string | null>(null);
  const [round, setRound] = useState(0);

  return (
    <section className="rounded-xl border border-neutral-200" id="pin">
      <div className="flex flex-wrap items-baseline justify-between gap-2 border-b border-neutral-200 bg-neutral-50 px-3.5 py-2 text-xs font-medium text-neutral-600">
        <span>Map pin</span>
        {from && <span className="font-normal text-neutral-500">{from}</span>}
      </div>
      <div className="flex flex-col gap-3 p-3.5 text-[13px]">
        <p className="text-neutral-600">
          Drag the pin onto the front door. A moved pin is kept like any hand edit: sources can’t move it again, and a source
          moving the place more than 250 m goes to the review queue.
        </p>
        {done && (
          <p role="status" className="rounded-lg border border-orange-200 bg-orange-50 px-3 py-2 text-orange-900">
            {done}
          </p>
        )}
        {disabled ? (
          <p className="text-neutral-500">This place was merged, so its pin can’t be moved here.</p>
        ) : (
          <PinFixForm
            key={`${round}-${lat}-${lng}`}
            current={{ lat, lng }}
            member={false}
            look="admin"
            submitLabel="Save pin"
            onSubmit={async (v) => {
              const res = await movePin({ placeId, lat: v.lat, lng: v.lng, how: v.how, method: v.method, accuracy: v.accuracy, note: v.note });
              if (res.error) return res.error;
              setDone(`Pin moved ${metersText(res.moved ?? 0)}. It’s in the history below.`);
              setRound((n) => n + 1);
              router.refresh();
              return null;
            }}
          />
        )}
      </div>
    </section>
  );
}
