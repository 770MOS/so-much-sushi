// "Same", "Different" or "Missing" for one field of a possible-duplicate pair.
export default function Compare({ same, missing }: { same: boolean | null; missing?: boolean }) {
  if (missing || same === null) return <span className="text-neutral-500">Missing</span>;
  return same ? (
    <span className="inline-flex items-center gap-1.5">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#15803d" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M5 12l5 5l10 -10" />
      </svg>
      Same
    </span>
  ) : (
    <span className="inline-flex items-center gap-1.5">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#b91c1c" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M6 6l12 12" />
        <path d="M18 6l-12 12" />
      </svg>
      Different
    </span>
  );
}
