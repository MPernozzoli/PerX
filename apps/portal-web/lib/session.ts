import type { PortalSession } from "./types";

const SESSION_KEY = "perx_portal_session";
const ACTIVE_CLAIM_KEY = "perx_portal_active_claim_id";

export function setStoredPortalSession(session: PortalSession): void {
  try {
    localStorage.setItem(SESSION_KEY, JSON.stringify(session));
  } catch {
    // localStorage not available (SSR or private mode)
  }
}

export function getStoredPortalSession(): PortalSession | null {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as PortalSession;
  } catch {
    return null;
  }
}

export function clearStoredPortalSession(): void {
  try {
    localStorage.removeItem(SESSION_KEY);
    localStorage.removeItem(ACTIVE_CLAIM_KEY);
  } catch {
    // ignore
  }
}

export function getStoredPortalActiveClaimId(): string | null {
  try {
    return localStorage.getItem(ACTIVE_CLAIM_KEY);
  } catch {
    return null;
  }
}

export function setStoredPortalActiveClaimId(claimId: string): void {
  try {
    localStorage.setItem(ACTIVE_CLAIM_KEY, claimId);
  } catch {
    // ignore
  }
}
