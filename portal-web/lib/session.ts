import type { PortalSession } from "@/lib/types";
import { getPortalStorageScope } from "@/lib/tenant";

const STORAGE_KEY = "perx.portal.session";
const ACTIVE_CLAIM_STORAGE_KEY = "perx.portal.active-claim";

function scopedKey(key: string): string {
  return `${key}.${getPortalStorageScope()}`;
}

export function getStoredPortalSession(): PortalSession | null {
  if (typeof window === "undefined") {
    return null;
  }

  const raw = window.localStorage.getItem(scopedKey(STORAGE_KEY));
  if (!raw) {
    return null;
  }

  try {
    return JSON.parse(raw) as PortalSession;
  } catch {
    window.localStorage.removeItem(scopedKey(STORAGE_KEY));
    return null;
  }
}

export function setStoredPortalSession(session: PortalSession): void {
  if (typeof window === "undefined") {
    return;
  }
  window.localStorage.setItem(scopedKey(STORAGE_KEY), JSON.stringify(session));
  window.localStorage.setItem(scopedKey(ACTIVE_CLAIM_STORAGE_KEY), session.claimId);
}

export function clearStoredPortalSession(): void {
  if (typeof window === "undefined") {
    return;
  }
  window.localStorage.removeItem(scopedKey(STORAGE_KEY));
  window.localStorage.removeItem(scopedKey(ACTIVE_CLAIM_STORAGE_KEY));
}

export function getStoredPortalActiveClaimId(): string | null {
  if (typeof window === "undefined") {
    return null;
  }
  return window.localStorage.getItem(scopedKey(ACTIVE_CLAIM_STORAGE_KEY));
}

export function setStoredPortalActiveClaimId(claimId: string): void {
  if (typeof window === "undefined") {
    return;
  }
  window.localStorage.setItem(scopedKey(ACTIVE_CLAIM_STORAGE_KEY), claimId);
}
