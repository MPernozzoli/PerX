import type {
  PortalAccessibleClaim,
  PortalAuthStartResponse,
  PortalClaimSummary,
  PortalDocument,
  PortalInspectionSchedulingOverview,
  PortalMessageList,
  PortalSession,
  PortalTimelineEvent,
} from "./types";

export type { PortalSession };

const API_BASE =
  process.env.NEXT_PUBLIC_PORTAL_API_BASE_URL ?? "/api/v1/portal";

function authHeaders(session: PortalSession): HeadersInit {
  return {
    "Authorization": `Bearer ${session.token}`,
    "Content-Type": "application/json",
  };
}

async function portalFetch<T>(
  url: string,
  options?: RequestInit,
): Promise<T> {
  const response = await fetch(url, options);
  if (!response.ok) {
    let message = `HTTP ${response.status}`;
    try {
      const body = (await response.json()) as { detail?: string; message?: string };
      message = body.detail ?? body.message ?? message;
    } catch {
      // ignore parse error
    }
    throw new Error(message);
  }
  return response.json() as Promise<T>;
}

// --- Auth ---

export async function startPortalAuth(params: {
  claimReference: string;
  taxCode: string;
  fullName: string;
  phoneNumber: string;
}): Promise<PortalAuthStartResponse> {
  return portalFetch<PortalAuthStartResponse>(`${API_BASE}/auth/start`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(params),
  });
}

export async function exchangePortalToken(token: string): Promise<PortalSession> {
  return portalFetch<PortalSession>(`${API_BASE}/auth/exchange/${encodeURIComponent(token)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
  });
}

export async function requestPortalOtp(params: {
  claimReference: string;
  phoneNumber: string;
  channel: string;
}): Promise<{ masked_destination?: string; delivery_channel?: string; preview_otp_code?: string }> {
  return portalFetch(`${API_BASE}/auth/request-otp`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(params),
  });
}

export async function verifyPortalOtp(params: {
  claimReference: string;
  phoneNumber: string;
  otpCode: string;
  rememberMe: boolean;
}): Promise<PortalSession> {
  return portalFetch<PortalSession>(`${API_BASE}/auth/verify-otp`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(params),
  });
}

// --- Tenant branding ---

export interface PortalTenantBranding {
  primary_color?: string;
  logo_url?: string;
  company_name?: string;
}

export async function getPortalTenantBranding(host?: string): Promise<PortalTenantBranding> {
  const resolvedHost =
    host ?? (typeof window !== "undefined" ? window.location.hostname : "");
  try {
    return await portalFetch<PortalTenantBranding>(
      `${API_BASE}/tenant-branding?host=${encodeURIComponent(resolvedHost)}`,
    );
  } catch {
    return {};
  }
}

// --- Claims ---

export async function listAccessibleClaims(
  session: PortalSession,
): Promise<PortalAccessibleClaim[]> {
  return portalFetch<PortalAccessibleClaim[]>(`${API_BASE}/claims`, {
    headers: authHeaders(session),
  });
}

export async function getPortalClaimSummaryForClaim(
  session: PortalSession,
  claimId: string,
): Promise<PortalClaimSummary> {
  return portalFetch<PortalClaimSummary>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}`,
    { headers: authHeaders(session) },
  );
}

export async function getPortalTimeline(
  session: PortalSession,
  claimId: string,
): Promise<PortalTimelineEvent[]> {
  return portalFetch<PortalTimelineEvent[]>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/timeline`,
    { headers: authHeaders(session) },
  );
}

export async function getPortalDocuments(
  session: PortalSession,
  claimId: string,
): Promise<PortalDocument[]> {
  return portalFetch<PortalDocument[]>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/documents`,
    { headers: authHeaders(session) },
  );
}

export async function listPortalMessages(
  session: PortalSession,
  claimId: string,
): Promise<PortalMessageList> {
  return portalFetch<PortalMessageList>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/messages`,
    { headers: authHeaders(session) },
  );
}

export async function getInspectionSchedulingOverview(
  session: PortalSession,
  claimId: string,
): Promise<PortalInspectionSchedulingOverview> {
  return portalFetch<PortalInspectionSchedulingOverview>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/inspection`,
    { headers: authHeaders(session) },
  );
}
