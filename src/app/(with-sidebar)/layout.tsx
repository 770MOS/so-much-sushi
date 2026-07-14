import Sidebar from "@/components/Sidebar";
import HomeLocationPrompt from "@/components/HomeLocationPrompt";

export default function WithSidebarLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex flex-1 flex-row">
      <Sidebar />
      <div className="min-w-0 flex-1 pb-16 md:pb-0">{children}</div>
      <HomeLocationPrompt />
    </div>
  );
}
