import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import Avatar from "@/components/Avatar";
import InviteAccept from "@/components/friends/InviteAccept";
import type { InviteInfo } from "@/lib/friends";

// An invite link (/invite/<code>): who it's from, and a button to become friends. A visitor is
// sent to join or sign in and comes back here afterwards.

type Params = { params: Promise<{ code: string }> };

export const metadata: Metadata = { title: "You're invited · So Much Sushi", robots: { index: false } };

export default async function InvitePage({ params }: Params) {
  const { code } = await params;
  const supabase = await createClient();
  const [{ data }, { data: auth }] = await Promise.all([
    /^[0-9a-f]{16}$/.test(code) ? supabase.rpc("invite_info", { code }) : Promise.resolve({ data: null }),
    supabase.auth.getUser(),
  ]);
  const invite = data as InviteInfo | null;
  const signedIn = Boolean(auth.user);
  const here = `/invite/${code}`;
  const card = "flex w-full max-w-sm flex-col gap-3";

  if (!invite) {
    return (
      <main className="flex flex-1 flex-col items-center px-6 py-16">
        <div className={card}>
          <h1 className="text-2xl font-medium tracking-tight text-zinc-950">This invite link doesn&apos;t work anymore</h1>
          <p className="text-[15px] leading-relaxed text-muted">
            Its owner may have made a new one. Ask them for their current link, or find them by name on the Friends page.
          </p>
          <Link href="/friends" className="mt-3 flex h-12 items-center justify-center rounded-xl bg-primary text-base font-medium text-white hover:bg-primary-hover">
            Go to Friends
          </Link>
        </div>
      </main>
    );
  }

  const first = invite.name.split(/\s+/)[0];
  return (
    <main className="flex flex-1 flex-col items-center px-6 py-16">
      <div className={card}>
        <Avatar name={invite.name} seed={invite.handle} size={56} />
        <h1 className="text-2xl font-medium tracking-tight text-zinc-950">
          {invite.relation === "self" ? "This is your invite link" : `${invite.name} invited you to So Much Sushi`}
        </h1>
        <p className="text-[15px] leading-relaxed text-muted">
          {invite.relation === "self"
            ? "Send it to friends. When they open it and sign in or join, you're friends."
            : invite.relation === "friends"
              ? `You and ${first} are already friends.`
              : `Every place to eat and drink, with nothing paid to the top. Friends see each other's favorites and lists set to Friends.`}
        </p>
        <div className="mt-3 flex flex-col gap-2">
          {invite.relation === "self" ? (
            <Link href="/friends" className="flex h-12 items-center justify-center rounded-xl bg-primary text-base font-medium text-white hover:bg-primary-hover">
              Go to Friends
            </Link>
          ) : invite.relation === "friends" ? (
            <Link
              href={invite.handle ? `/u/${invite.handle}` : "/friends"}
              className="flex h-12 items-center justify-center rounded-xl bg-primary text-base font-medium text-white hover:bg-primary-hover"
            >
              See {first}&apos;s favorites
            </Link>
          ) : signedIn ? (
            <InviteAccept code={code} firstName={first} />
          ) : (
            <>
              <Link
                href={`/sign-up?next=${encodeURIComponent(here)}`}
                className="flex h-12 items-center justify-center rounded-xl bg-primary text-base font-medium text-white hover:bg-primary-hover"
              >
                Join free
              </Link>
              <Link
                href={`/sign-in?next=${encodeURIComponent(here)}`}
                className="flex h-12 items-center justify-center rounded-xl border border-[#dddddd] text-base font-medium text-zinc-950 hover:bg-zinc-50"
              >
                I have an account
              </Link>
            </>
          )}
        </div>
      </div>
    </main>
  );
}
