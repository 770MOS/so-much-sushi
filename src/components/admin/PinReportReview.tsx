"use client";

import { useRouter } from "next/navigation";
import PinFixForm from "@/components/PinFixForm";
import { acceptPinReport } from "@/app/admin/review/actions";
import { metersBetween, type PinHow } from "@/lib/pins";

// The pin report screen's map: the pin's current spot (faded), the member's suggestion (the
// movable pin, to adjust before accepting), and other members' suggestions for the same place.
export default function PinReportReview({
  id,
  current,
  suggested,
  others,
  how,
}: {
  id: number;
  current: { lat: number; lng: number };
  suggested: { lat: number; lng: number };
  others: { lat: number; lng: number }[];
  how: PinHow;
}) {
  const router = useRouter();
  return (
    <PinFixForm
      current={current}
      start={suggested}
      member={false}
      look="admin"
      fixedHow={how}
      marks={others.map((o, i) => ({ ...o, label: others.length > 1 ? `Another member ${i + 1}` : "Another member", tone: "other" as const }))}
      submitLabel="Accept and move the pin"
      onSubmit={async (v) => {
        const adjusted = metersBetween(v, suggested) >= 0.5;
        const res = await acceptPinReport({ id, lat: adjusted ? v.lat : null, lng: adjusted ? v.lng : null, note: v.note });
        if (res.error) return res.error;
        router.push(`/admin/review?type=pins&notice=${encodeURIComponent(adjusted ? "Pin moved to your adjusted spot." : "Pin moved to the suggested spot.")}`);
        return null;
      }}
    />
  );
}
