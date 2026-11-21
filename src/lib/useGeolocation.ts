"use client";

import { useState } from "react";
import type { Coords } from "@/lib/lastSearchCoords";
import { noteUserLocation } from "@/lib/userLocation";

export function useGeolocation(manualFallbackHint: string = "Please enter a location manually.") {
  const [locating, setLocating] = useState(false);
  const [geoError, setGeoError] = useState<string | null>(null);

  function requestLocation(): Promise<Coords | null> {
    setGeoError(null);

    if (!("geolocation" in navigator)) {
      setGeoError(`Geolocation isn't supported by your browser. ${manualFallbackHint}`);
      return Promise.resolve(null);
    }

    setLocating(true);
    return new Promise((resolve) => {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          setLocating(false);
          // They've allowed it, so the maps show where they are (the blue dot).
          noteUserLocation({ lat: position.coords.latitude, lng: position.coords.longitude, accuracy: position.coords.accuracy });
          resolve({ lat: position.coords.latitude, lng: position.coords.longitude });
        },
        (err) => {
          setLocating(false);
          if (err.code === err.PERMISSION_DENIED) {
            setGeoError(`Location access was denied. ${manualFallbackHint}`);
          } else {
            setGeoError(`We couldn't determine your location. ${manualFallbackHint}`);
          }
          resolve(null);
        }
      );
    });
  }

  return { locating, geoError, setGeoError, requestLocation };
}
