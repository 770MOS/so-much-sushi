"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import type { User } from "@supabase/supabase-js";
import type { ReactNode } from "react";
import AddToListMenu from "@/components/AddToListMenu";
import StatusBadge from "@/components/StatusBadge";
import { HeartIcon, StarIcon, EyeOffIcon } from "@/components/icons";
import type { MapMarkerEntity } from "@/components/EntityMap";
import type { Recommender, SearchResult, SortMode, ViewMode } from "@/lib/searchTypes";

const EntityMap = dynamic(() => import("@/components/EntityMap"), { ssr: false });

function sortButtonClass(active: boolean) {
  return `rounded-md px-3 py-1 text-sm font-medium transition-colors ${
    active
      ? "bg-primary text-white"
      : "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
  }`;
}

const UNKNOWN_RECOMMENDER: Recommender = { name: "a friend", handle: null };

function RecommenderName({ recommender }: { recommender: Recommender }) {
  const label = recommender.name?.trim() || "a friend";
  if (!recommender.handle) return <>{label}</>;
  return (
    <Link href={`/u/${recommender.handle}`} className="hover:underline">
      {label}
    </Link>
  );
}

function recommendationLabel(
  recommendedBy: Recommender[] | null,
  recommendedCount: number
): ReactNode | null {
  if (!recommendedCount) return null;

  const people = recommendedBy ?? [];
  const first = people[0] ?? UNKNOWN_RECOMMENDER;

  if (recommendedCount === 1) {
    return (
      <>
        Starred by <RecommenderName recommender={first} />
      </>
    );
  }
  if (recommendedCount === 2) {
    const second = people[1] ?? UNKNOWN_RECOMMENDER;
    return (
      <>
        Starred by <RecommenderName recommender={first} /> and{" "}
        <RecommenderName recommender={second} />
      </>
    );
  }
  return (
    <>
      Starred by <RecommenderName recommender={first} /> and {recommendedCount - 1} others
    </>
  );
}

type Props = {
  loading: boolean;
  results: SearchResult[] | null;
  sortedResults: SearchResult[];
  mapMarkerEntities: MapMarkerEntity[];
  viewMode: ViewMode;
  setViewMode: (v: ViewMode) => void;
  sortMode: SortMode;
  setSortMode: (v: SortMode) => void;
  starredIds: Set<string>;
  toggleStar: (id: string) => void;
  hiddenIds: Set<string>;
  toggleHide: (id: string) => void;
  user: User | null;
  extraControls?: ReactNode;
  note?: ReactNode;
  emptyMessage?: string;
};

export default function SearchResultsView({
  loading,
  results,
  sortedResults,
  mapMarkerEntities,
  viewMode,
  setViewMode,
  sortMode,
  setSortMode,
  starredIds,
  toggleStar,
  hiddenIds,
  toggleHide,
  user,
  extraControls,
  note,
  emptyMessage = "No restaurants found nearby. Try a larger radius or a different category.",
}: Props) {
  if (loading) {
    return (
      <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">Searching…</p>
    );
  }

  if (results === null) return null;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
          {results.length} {results.length === 1 ? "result" : "results"}
        </h2>
        <div className="flex items-center gap-2">
          {extraControls}
          <div className="flex gap-1 rounded-lg border border-zinc-300 p-0.5 dark:border-zinc-700">
            <button
              type="button"
              onClick={() => setViewMode("list")}
              className={sortButtonClass(viewMode === "list")}
            >
              List
            </button>
            <button
              type="button"
              onClick={() => setViewMode("map")}
              className={sortButtonClass(viewMode === "map")}
            >
              Map
            </button>
          </div>
          {results.length > 0 && viewMode === "list" && (
            <div className="flex gap-1 rounded-lg border border-zinc-300 p-0.5 dark:border-zinc-700">
              <button
                type="button"
                onClick={() => setSortMode("nearest")}
                className={sortButtonClass(sortMode === "nearest")}
              >
                Nearest
              </button>
              <button
                type="button"
                onClick={() => setSortMode("az")}
                className={sortButtonClass(sortMode === "az")}
              >
                A&ndash;Z
              </button>
            </div>
          )}
        </div>
      </div>

      {note}

      {results.length === 0 ? (
        <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">{emptyMessage}</p>
      ) : viewMode === "map" ? (
        <EntityMap entities={mapMarkerEntities} />
      ) : (
        <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
          {sortedResults.map((r) => {
            const recLabel = recommendationLabel(r.recommended_by, r.recommended_count);
            return (
              <li key={r.id} className="flex items-center justify-between gap-4 py-4">
                <div className="flex flex-col gap-0.5">
                  <span className="font-medium text-zinc-950 dark:text-zinc-50">{r.name}</span>
                  <span className="text-sm text-zinc-500 dark:text-zinc-400">{r.address}</span>
                  {r.categories && r.categories.length > 0 && (
                    <span className="text-xs text-zinc-500 dark:text-zinc-400">
                      {r.categories.join(", ")}
                    </span>
                  )}
                  <StatusBadge status={r.status} />
                  {recLabel && (
                    <span className="flex items-center gap-1 text-xs text-zinc-500 dark:text-zinc-400">
                      <HeartIcon />
                      {recLabel}
                    </span>
                  )}
                </div>
                <div className="flex shrink-0 items-center gap-3">
                  <span className="text-sm text-zinc-500 dark:text-zinc-400">
                    {r.miles.toFixed(1)} mi
                  </span>
                  {user && <AddToListMenu userId={user.id} entityId={r.id} />}
                  <button
                    type="button"
                    onClick={() => toggleStar(r.id)}
                    aria-label={starredIds.has(r.id) ? "Unstar" : "Star"}
                    aria-pressed={starredIds.has(r.id)}
                    className="rounded p-1 transition-colors hover:bg-zinc-200 dark:hover:bg-zinc-800"
                  >
                    <StarIcon filled={starredIds.has(r.id)} />
                  </button>
                  <button
                    type="button"
                    onClick={() => toggleHide(r.id)}
                    aria-label={hiddenIds.has(r.id) ? "Unhide" : "Hide"}
                    aria-pressed={hiddenIds.has(r.id)}
                    className="rounded p-1 transition-colors hover:bg-zinc-200 dark:hover:bg-zinc-800"
                  >
                    <EyeOffIcon filled={hiddenIds.has(r.id)} />
                  </button>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
