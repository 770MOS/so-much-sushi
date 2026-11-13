"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

// "Add Jamie as a friend" on an invite page, for someone signed in.
export default function InviteAccept({ code, firstName }: { code: string; firstName: string }) {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);

  async function accept() {
    setBusy(true);
    setError(false);
    const { data, error: err } = await supabase.rpc("accept_invite", { code });
    if (err || !data) {
      setBusy(false);
      setError(true);
      return;
    }
    const handle = (data as { handle: string | null }).handle;
    router.push(handle ? `/u/${handle}` : "/friends");
  }

  return (
    <div className="flex flex-col gap-2">
      <button
        type="button"
        onClick={accept}
        disabled={busy}
        className="flex h-12 items-center justify-center rounded-xl bg-primary text-base font-medium text-white hover:bg-primary-hover disabled:opacity-50"
      >
        {busy ? "Adding…" : `Add ${firstName} as a friend`}
      </button>
      {error && <p className="text-sm text-red-700">That didn&apos;t work. The link may have been replaced; ask for a new one.</p>}
    </div>
  );
}
