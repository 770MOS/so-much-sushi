"use client";

import { useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

// Whether someone is signed in, for choosing what the page chrome shows (the
// phone tab bar, the footer). Read from the session the browser already holds,
// so it costs no request. undefined until known. Never use this to protect
// anything: the database's own rules do that.
export function useSignedIn(): boolean | undefined {
  const supabase = useMemo(() => createClient(), []);
  const [signedIn, setSignedIn] = useState<boolean | undefined>(undefined);

  useEffect(() => {
    // onAuthStateChange reports the current session straight away
    // (INITIAL_SESSION), then every sign-in and sign-out.
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setSignedIn(Boolean(session?.user));
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  return signedIn;
}

// The signed-in person's id, from the same session: null for a visitor, undefined until known.
export function useUserId(): string | null | undefined {
  const supabase = useMemo(() => createClient(), []);
  const [id, setId] = useState<string | null | undefined>(undefined);

  useEffect(() => {
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setId(session?.user?.id ?? null);
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  return id;
}
