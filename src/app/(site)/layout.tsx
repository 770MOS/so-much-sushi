import HomeLocationPrompt from "@/components/HomeLocationPrompt";

// The site's pages share the header, footer and phone tab bar from the root
// layout; this group adds the place panel (the @modal slot) and the home-area prompt.
export default function SiteLayout({
  children,
  modal,
}: {
  children: React.ReactNode;
  modal: React.ReactNode;
}) {
  return (
    <div className="flex min-w-0 flex-1 flex-col">
      {children}
      <HomeLocationPrompt />
      {modal}
    </div>
  );
}
