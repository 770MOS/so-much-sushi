import { extractCityState, type CityState, type NominatimAddress } from "@/lib/reverseGeocode";

const TIMEOUT_MS = 5000;

export type ForwardGeocodeResult = CityState & { lat: number; lng: number };

// Forward-geocodes arbitrary location text (ZIP, street address, or plain
// city name - whatever a user might type) and extracts structured
// city/state from the response, so "22201" resolves to
// { city: "Arlington", state: "VA" }, not the raw typed string. Returns
// null if the address can't be found, the request fails, or times out -
// callers should show their own "couldn't find that location" message.
export async function forwardGeocodeCityState(query: string): Promise<ForwardGeocodeResult | null> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const res = await fetch(
      `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=us&addressdetails=1&q=${encodeURIComponent(query)}`,
      { signal: controller.signal }
    );
    if (!res.ok) return null;

    const data = await res.json();
    if (!Array.isArray(data) || data.length === 0) return null;

    const result = data[0];
    const address: NominatimAddress | undefined = result?.address;
    const { city, state } = extractCityState(address);

    return {
      lat: parseFloat(result.lat),
      lng: parseFloat(result.lon),
      city,
      state,
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}
