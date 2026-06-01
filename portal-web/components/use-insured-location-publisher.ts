"use client";

import { useEffect, useRef, useState } from "react";

import { publishVideoperiziaLocationPing } from "@/lib/api";
import type { PortalSession } from "@/lib/types";

type GeolocationStatus = "idle" | "requesting" | "active" | "denied" | "error";

type Options = {
  session: PortalSession;
  enabled: boolean;
  /** Minimum milliseconds between two backend writes. The browser may fire
   * `watchPosition` more often; we throttle so we don't hammer the API. */
  minIntervalMs?: number;
};

/**
 * Pubblica periodicamente la posizione GPS dell'assicurato al backend mentre
 * la videoperizia è attiva. Gestisce consenso, throttling e cleanup.
 */
export function useInsuredLocationPublisher({
  session,
  enabled,
  minIntervalMs = 8000
}: Options) {
  const [status, setStatus] = useState<GeolocationStatus>("idle");
  const [lastError, setLastError] = useState<string | null>(null);
  const watchIdRef = useRef<number | null>(null);
  const lastSentAtRef = useRef<number>(0);

  useEffect(() => {
    if (!enabled) {
      stop();
      return;
    }
    if (typeof navigator === "undefined" || !navigator.geolocation) {
      setStatus("error");
      setLastError("Geolocalizzazione non disponibile sul dispositivo.");
      return;
    }

    setStatus("requesting");
    const id = navigator.geolocation.watchPosition(
      (position) => {
        setStatus("active");
        const now = Date.now();
        if (now - lastSentAtRef.current < minIntervalMs) return;
        lastSentAtRef.current = now;
        publishVideoperiziaLocationPing(session, {
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracy_m: position.coords.accuracy,
          altitude_m: position.coords.altitude ?? null,
          speed_mps: position.coords.speed ?? null,
          heading_deg: position.coords.heading ?? null,
          recorded_at: new Date(position.timestamp).toISOString()
        }).catch((requestError) => {
          // Don't surface — next tick retries. Only log error transitions.
          setLastError(
            requestError instanceof Error ? requestError.message : "Errore invio posizione"
          );
        });
      },
      (geoError) => {
        if (geoError.code === geoError.PERMISSION_DENIED) {
          setStatus("denied");
        } else {
          setStatus("error");
        }
        setLastError(geoError.message);
      },
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 15000 }
    );
    watchIdRef.current = id;

    return () => stop();

    function stop() {
      if (watchIdRef.current !== null && navigator.geolocation) {
        navigator.geolocation.clearWatch(watchIdRef.current);
        watchIdRef.current = null;
      }
    }
  }, [enabled, session, minIntervalMs]);

  return { status, lastError };
}
