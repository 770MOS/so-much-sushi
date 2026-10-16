import { Suspense } from "react";
import Sidebar from "@/components/Sidebar";
import HomeLocationPrompt from "@/components/HomeLocationPrompt";

export default function WithSidebarLayout({
  children,
  modal,
}: {
  children: React.ReactNode;
  modal: React.ReactNode;
}) {
  return (
    <div className="flex flex-1 flex-row">
      {/* Sidebar reads the URL's search params, so it renders in the browser.
          The boundary lets the rest of each page be prerendered; the empty column
          keeps the layout from shifting while the sidebar loads. */}
      <Suspense
        fallback={
          <div aria-hidden="true" className="hidden w-48 shrink-0 border-r border-zinc-200 bg-white dark:border-zinc-800 dark:bg-black md:block" />
        }
      >
        <Sidebar />
      </Suspense>
      <div className="min-w-0 flex-1 pb-16 md:pb-0">{children}</div>
      <HomeLocationPrompt />
      {modal}
    </div>
  );
}
