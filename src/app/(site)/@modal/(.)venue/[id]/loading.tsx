import PlacePanel from "@/components/place/PlacePanel";

// The panel shows at once while the place loads.
export default function Loading() {
  return <PlacePanel place={null} />;
}
