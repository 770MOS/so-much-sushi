"use client";

import { useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import Dialog, { primaryButton } from "@/components/lists/Dialog";
import PinFixForm from "@/components/PinFixForm";
import { currentUserIsAdmin } from "@/app/actions/account";
import { movePin } from "@/app/actions/pins";
import { metersText } from "@/lib/pins";

type Existing = { id: number; lat: number; lng: number; created_at: string } | null;

function sentence(message: string) {
  return message.charAt(0).toUpperCase() + message.slice(1).replace(/\.?$/, ".");
}

// "Pin in the wrong spot" on a place (2026-11-15). Admins move the pin there and then; members
// suggest a spot, which waits in the review queue until an admin accepts it.
export default function PinFixDialog({
  place,
  onClose,
  onMoved,
}: {
  place: { id: string; name: string; lat: number; lng: number };
  onClose: () => void;
  onMoved: (lat: number, lng: number) => void;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [admin, setAdmin] = useState<boolean | null>(null);
  const [existing, setExisting] = useState<Existing>(null);
  const [done, setDone] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [isAdmin, mine] = await Promise.all([
        currentUserIsAdmin().catch(() => false),
        supabase.rpc("my_pin_report", { p_place: place.id }),
      ]);
      if (cancelled) return;
      setExisting((mine.data as Existing) ?? null);
      setAdmin(isAdmin);
    })();
    return () => {
      cancelled = true;
    };
  }, [supabase, place.id]);

  const title = admin ? "Move the pin" : "Suggest a better spot for the pin";

  return (
    <Dialog title={admin === null ? "Pin in the wrong spot" : title} onClose={onClose} wide>
      {done ? (
        <div className="mt-3 flex flex-col gap-4">
          <p className="text-[15px] leading-relaxed text-zinc-950">{done}</p>
          <button type="button" onClick={onClose} className={`${primaryButton} self-start`}>
            Done
          </button>
        </div>
      ) : admin === null ? (
        <p className="mt-3 text-[15px] text-muted">Loading…</p>
      ) : (
        <div className="mt-2 flex flex-col gap-4">
          <p className="text-[15px] leading-relaxed text-muted">
            {admin
              ? `Drag the pin onto ${place.name}’s front door. It’s saved right away and kept when sources update.`
              : `Drag the pin onto ${place.name}’s front door, or put it where you’re standing if you’re there. We check every suggestion before the pin moves.`}
          </p>
          {!admin && existing && (
            <p className="rounded-[10px] bg-zinc-50 px-3.5 py-2.5 text-sm text-zinc-950">
              You suggested a spot on{" "}
              {new Date(existing.created_at).toLocaleDateString("en-US", { month: "short", day: "numeric" })}, and it’s waiting
              for review. Sending a new one replaces it.
            </p>
          )}
          <PinFixForm
            current={{ lat: place.lat, lng: place.lng }}
            start={!admin && existing ? { lat: existing.lat, lng: existing.lng } : undefined}
            member={!admin}
            look="site"
            submitLabel={admin ? "Save pin" : "Send suggestion"}
            onCancel={onClose}
            onSubmit={async (v) => {
              if (admin) {
                const res = await movePin({ placeId: place.id, lat: v.lat, lng: v.lng, how: v.how, method: v.method, accuracy: v.accuracy, note: v.note });
                if (res.error) return res.error;
                onMoved(v.lat, v.lng);
                setDone(`Pin moved ${metersText(res.moved ?? 0)}. It’s kept even when sources update, and the place’s history shows the move.`);
                return null;
              }
              const { error } = await supabase.rpc("submit_pin_report", {
                p_place: place.id,
                p_lat: v.lat,
                p_lng: v.lng,
                p_how: v.how,
                p_method: v.method,
                p_accuracy: v.method === "gps" ? v.accuracy : null,
                p_note: v.note || null,
                p_agree: v.agree,
              });
              if (error) return sentence(error.message);
              setDone("Thanks! We’ll check your suggestion and move the pin if it’s right.");
              return null;
            }}
          />
        </div>
      )}
    </Dialog>
  );
}
