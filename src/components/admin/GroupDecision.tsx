"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { decideGroupBatch } from "@/app/admin/review/actions";
import { VERBS, type GroupKind } from "@/app/admin/review/groups";

const primary = "min-h-11 cursor-pointer rounded-lg bg-neutral-900 px-3.5 text-[13px] font-medium text-white hover:bg-neutral-700 disabled:opacity-50";
const secondary = "min-h-11 cursor-pointer rounded-lg border border-neutral-300 bg-white px-3.5 text-[13px] font-medium hover:bg-neutral-50 disabled:opacity-50";

// "Merge all" / "Keep all separate" (or Apply / Reject) for what is left in a group: asks
// first, then decides it 100 at a time with a running count, and can be stopped between
// batches.
export default function GroupDecision({ group, kind, count, title }: { group: string; kind: GroupKind; count: number; title: string }) {
  const router = useRouter();
  const verbs = VERBS[kind];
  const [asking, setAsking] = useState<null | boolean>(null);
  const [running, setRunning] = useState(false);
  const [done, setDone] = useState(0);
  const [left, setLeft] = useState(count);
  const [message, setMessage] = useState<string | null>(null);
  const stop = useRef(false);
  const n = (x: number) => x.toLocaleString("en-US");

  async function run(accept: boolean) {
    setAsking(null);
    setRunning(true);
    setLeft(count);
    setDone(0);
    setMessage(null);
    stop.current = false;
    let total = 0;
    for (;;) {
      const res = await decideGroupBatch(group, accept).catch((e: Error) => ({ decided: 0, left: 0, error: e.message }));
      if (res.error) {
        setMessage(`Stopped: ${res.error}`);
        break;
      }
      total += res.decided;
      setDone(total);
      setLeft(res.left);
      if (res.left === 0 || res.decided === 0) {
        // The group's row goes once it is empty, so the result shows at the top of the page.
        const url = new URL(window.location.href);
        url.searchParams.set("notice", `${accept ? verbs.accepted : verbs.declined} ${n(total)}: ${title}.`);
        url.searchParams.delete("page");
        setRunning(false);
        router.replace(url.pathname + url.search);
        return;
      }
      if (stop.current) {
        setMessage(`Stopped after ${n(total)}; ${n(res.left)} left.`);
        break;
      }
    }
    setRunning(false);
    router.refresh();
  }

  if (running) {
    return (
      <div role="status" className="flex flex-wrap items-center gap-3 text-[13px]">
        <span className="inline-block h-4 w-4 animate-spin rounded-full border-2 border-neutral-300 border-t-neutral-900" aria-hidden />
        <span>
          {n(done)} done · {n(left)} left
        </span>
        <button type="button" className={secondary} onClick={() => (stop.current = true)}>
          Stop after this batch
        </button>
      </div>
    );
  }
  // Between runs the count comes from the page, which refreshes after each run.
  if (asking !== null) {
    return (
      <div className="flex flex-wrap items-center gap-2 text-[13px]">
        <span>
          {asking ? verbs.accept : verbs.decline} all {n(count)}?
          {kind === "duplicates" && asking ? " Each merge can be undone from the place’s page." : ""}
        </span>
        <button type="button" className={primary} onClick={() => run(asking)}>
          Yes, {(asking ? verbs.accept : verbs.decline).toLowerCase()} all
        </button>
        <button type="button" className={secondary} onClick={() => setAsking(null)}>
          Cancel
        </button>
      </div>
    );
  }
  return (
    <div className="flex flex-wrap items-center gap-2">
      {message && <span role="status" className="text-[13px] text-neutral-700">{message}</span>}
      {count > 0 && (
        <>
          <button type="button" className={primary} onClick={() => setAsking(true)}>
            {verbs.accept} all {n(count)}
          </button>
          <button type="button" className={secondary} onClick={() => setAsking(false)}>
            {verbs.decline} all {n(count)}
          </button>
        </>
      )}
    </div>
  );
}
