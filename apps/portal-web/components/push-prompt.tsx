"use client";

import { useCallback, useEffect, useState } from "react";

import {
  getPortalVapidPublicKey,
  subscribePortalPush,
  unsubscribePortalPush
} from "@/lib/api";
import { getStoredPortalSession } from "@/lib/session";

type Status =
  | "loading"
  | "unsupported"
  | "denied"
  | "subscribed"
  | "available"
  | "error";

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = atob(base64);
  const output = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; i += 1) {
    output[i] = rawData.charCodeAt(i);
  }
  return output;
}

async function readExistingSubscription(): Promise<PushSubscription | null> {
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) return null;
  const registration = await navigator.serviceWorker.ready;
  return registration.pushManager.getSubscription();
}

export function PushPrompt() {
  const [status, setStatus] = useState<Status>("loading");
  const [error, setError] = useState<string | null>(null);
  const [isPending, setIsPending] = useState(false);

  const refresh = useCallback(async () => {
    if (typeof window === "undefined") return;
    if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
      setStatus("unsupported");
      return;
    }
    if (Notification.permission === "denied") {
      setStatus("denied");
      return;
    }
    const subscription = await readExistingSubscription();
    setStatus(subscription ? "subscribed" : "available");
  }, []);

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (!("serviceWorker" in navigator)) {
      setStatus("unsupported");
      return;
    }
    navigator.serviceWorker
      .register("/sw.js")
      .then(() => refresh())
      .catch((registrationError) => {
        setStatus("error");
        setError(
          registrationError instanceof Error
            ? registrationError.message
            : "Service worker non registrato."
        );
      });
  }, [refresh]);

  async function handleEnable() {
    setIsPending(true);
    setError(null);
    try {
      const session = getStoredPortalSession();
      if (!session) throw new Error("Sessione portale non attiva.");
      const publicKey = await getPortalVapidPublicKey();
      if (!publicKey) throw new Error("Notifiche push non configurate sul server.");

      const permission = await Notification.requestPermission();
      if (permission !== "granted") {
        setStatus(permission === "denied" ? "denied" : "available");
        return;
      }

      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(publicKey)
      });

      const json = subscription.toJSON();
      const p256dh = json.keys?.p256dh ?? "";
      const auth = json.keys?.auth ?? "";
      if (!subscription.endpoint || !p256dh || !auth) {
        throw new Error("Subscription invalida.");
      }

      await subscribePortalPush(session, {
        endpoint: subscription.endpoint,
        p256dh,
        auth,
        userAgent: navigator.userAgent
      });
      setStatus("subscribed");
    } catch (subscribeError) {
      setStatus("error");
      setError(
        subscribeError instanceof Error
          ? subscribeError.message
          : "Impossibile attivare le notifiche."
      );
    } finally {
      setIsPending(false);
    }
  }

  async function handleDisable() {
    setIsPending(true);
    setError(null);
    try {
      const session = getStoredPortalSession();
      const subscription = await readExistingSubscription();
      if (subscription) {
        if (session) {
          await unsubscribePortalPush(session, subscription.endpoint);
        }
        await subscription.unsubscribe();
      }
      setStatus("available");
    } catch (unsubscribeError) {
      setError(
        unsubscribeError instanceof Error
          ? unsubscribeError.message
          : "Impossibile disattivare le notifiche."
      );
    } finally {
      setIsPending(false);
    }
  }

  if (status === "loading" || status === "unsupported") return null;

  return (
    <div className="push-prompt" style={{ padding: 16, border: "1px solid var(--ink-1, #e5e5e5)", borderRadius: 12, marginBottom: 16 }}>
      <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
        <div>
          <strong>Notifiche del portale</strong>
          <p style={{ margin: "4px 0 0", fontSize: 13, color: "var(--ink-3, #555)" }}>
            {status === "subscribed"
              ? "Riceverai una notifica quando l'atto sarà pronto o ci sarà un aggiornamento."
              : status === "denied"
                ? "Le notifiche sono bloccate dal browser. Sbloccale dalle impostazioni del sito per riceverle."
                : "Attiva le notifiche per essere avvisato quando l'atto è pronto."}
          </p>
        </div>
        {status === "available" && (
          <button
            type="button"
            className="btn btn--primary"
            onClick={handleEnable}
            disabled={isPending}
          >
            {isPending ? "Attivazione..." : "Attiva notifiche"}
          </button>
        )}
        {status === "subscribed" && (
          <button
            type="button"
            className="btn btn--ghost"
            onClick={handleDisable}
            disabled={isPending}
          >
            {isPending ? "..." : "Disattiva"}
          </button>
        )}
      </div>
      {error && <p style={{ color: "var(--danger, #c0392b)", marginTop: 8, fontSize: 13 }}>{error}</p>}
    </div>
  );
}
