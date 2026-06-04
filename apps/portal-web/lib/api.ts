import type {
  PortalAccessibleClaim,
  PortalAuthStartResponse,
  PortalBankAccountSubmission,
  PortalClaimSummary,
  PortalDocument,
  PortalInspectionSchedulingOverview,
  PortalMeDeletionRequest,
  PortalMeNotificationPrefs,
  PortalMePolicy,
  PortalMeProfile,
  PortalMeSessionInfo,
  PortalMessage,
  PortalMessageList,
  PortalSession,
  PortalTimelineEvent,
  PortalVideoperiziaSession,
  PortalVideoperiziaToken,
} from "./types";

export type { PortalSession };

export interface PortalTenantBranding {
  primary_color?: string;
  logo_url?: string;
  company_name?: string;
}

const API_BASE =
  process.env.NEXT_PUBLIC_PORTAL_API_BASE_URL ?? "/api/v1/portal";

function authHeaders(session: PortalSession): HeadersInit {
  return {
    Authorization: `Bearer ${session.token}`,
    "Content-Type": "application/json",
  };
}

async function portalFetch<T>(url: string, options?: RequestInit): Promise<T> {
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
  return portalFetch<PortalSession>(
    `${API_BASE}/auth/exchange/${encodeURIComponent(token)}`,
    { method: "POST", headers: { "Content-Type": "application/json" } },
  );
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

export async function listAccessibleClaims(session: PortalSession): Promise<PortalAccessibleClaim[]> {
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

export async function createPortalMessage(
  session: PortalSession,
  params: { bodyText: string },
  claimId: string,
): Promise<PortalMessage> {
  return portalFetch<PortalMessage>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/messages`,
    {
      method: "POST",
      headers: authHeaders(session),
      body: JSON.stringify(params),
    },
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

export async function submitInspectionPreferences(
  session: PortalSession,
  params: {
    selectedSlots: Array<{ date: string; startTime: string; endTime: string; label: string }>;
    notes?: string;
  },
  claimId: string,
): Promise<void> {
  await portalFetch<unknown>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/inspection/preferences`,
    {
      method: "POST",
      headers: authHeaders(session),
      body: JSON.stringify(params),
    },
  );
}

export async function updateInspectionLocation(
  session: PortalSession,
  params: {
    addressLine: string;
    municipality: string;
    province: string;
    region: string;
    latitude: number;
    longitude: number;
  },
  claimId: string,
): Promise<void> {
  await portalFetch<unknown>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/inspection/location`,
    {
      method: "PUT",
      headers: authHeaders(session),
      body: JSON.stringify(params),
    },
  );
}

// --- IBAN ---

export async function submitBankAccount(
  session: PortalSession,
  params: { iban: string },
  claimId: string,
): Promise<PortalBankAccountSubmission> {
  return portalFetch<PortalBankAccountSubmission>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/bank-account`,
    {
      method: "POST",
      headers: authHeaders(session),
      body: JSON.stringify(params),
    },
  );
}

// --- Documents ---

export async function downloadPortalDocument(
  session: PortalSession,
  params: { documentId: string },
  claimId: string,
): Promise<Blob> {
  const response = await fetch(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/documents/${encodeURIComponent(params.documentId)}/download`,
    { headers: { Authorization: `Bearer ${session.token}` } },
  );
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.blob();
}

export async function createUploadIntent(
  session: PortalSession,
  params: { fileName: string; mimeType: string; sizeBytes: number; category: string },
  claimId: string,
): Promise<{ document_id: string; upload_url?: string }> {
  return portalFetch(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/documents/upload-intent`,
    {
      method: "POST",
      headers: authHeaders(session),
      body: JSON.stringify(params),
    },
  );
}

export async function uploadPortalDocumentFile(
  session: PortalSession,
  params: { documentId: string; file: File },
  claimId: string,
): Promise<{ document_id: string; file_name: string; status: string; uploaded_at?: string; storage_path?: string }> {
  const form = new FormData();
  form.append("file", params.file);
  form.append("document_id", params.documentId);
  const response = await fetch(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/documents/${encodeURIComponent(params.documentId)}/upload`,
    {
      method: "PUT",
      headers: { Authorization: `Bearer ${session.token}` },
      body: form,
    },
  );
  if (!response.ok) {
    let message = `HTTP ${response.status}`;
    try {
      const body = (await response.json()) as { detail?: string };
      message = body.detail ?? message;
    } catch { /* ignore */ }
    throw new Error(message);
  }
  return response.json() as Promise<{ document_id: string; file_name: string; status: string }>;
}

export async function getDocumentCollectionDraft(
  session: PortalSession,
  claimId: string,
): Promise<{ draft_json: unknown }> {
  return portalFetch(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/documents/collection-draft`,
    { headers: authHeaders(session) },
  );
}

export async function saveDocumentCollectionDraft(
  session: PortalSession,
  params: { draftJson: unknown },
  claimId: string,
): Promise<void> {
  await portalFetch<unknown>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/documents/collection-draft`,
    {
      method: "PUT",
      headers: authHeaders(session),
      body: JSON.stringify(params),
    },
  );
}

export async function submitDocumentCollection(
  session: PortalSession,
  data: Record<string, unknown>,
  claimId: string,
): Promise<{ status: string; document_count?: number; submitted_at?: string }> {
  return portalFetch(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/documents/collection`,
    {
      method: "POST",
      headers: authHeaders(session),
      body: JSON.stringify(data),
    },
  );
}

export async function submitAdditionalDocuments(
  session: PortalSession,
  params: { note?: string; documentIds: string[]; requestedItems: string[] },
  claimId: string,
): Promise<{ status: string; document_count?: number; submitted_at?: string }> {
  return portalFetch(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/documents/additional`,
    {
      method: "POST",
      headers: authHeaders(session),
      body: JSON.stringify(params),
    },
  );
}

// --- Videoperizia ---

export async function getVideoperiziaSession(
  session: PortalSession,
  claimId: string,
): Promise<PortalVideoperiziaSession | null> {
  try {
    return await portalFetch<PortalVideoperiziaSession>(
      `${API_BASE}/claims/${encodeURIComponent(claimId)}/videoperizia`,
      { headers: authHeaders(session) },
    );
  } catch {
    return null;
  }
}

export async function joinVideoperiziaLobby(
  session: PortalSession,
  claimId: string,
): Promise<void> {
  await portalFetch<unknown>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/videoperizia/join`,
    { method: "POST", headers: authHeaders(session) },
  );
}

export async function mintVideoperiziaToken(
  session: PortalSession,
  claimId: string,
): Promise<PortalVideoperiziaToken> {
  return portalFetch<PortalVideoperiziaToken>(
    `${API_BASE}/claims/${encodeURIComponent(claimId)}/videoperizia/token`,
    { method: "POST", headers: authHeaders(session) },
  );
}

export async function publishVideoperiziaLocationPing(
  session: PortalSession,
  coords: { lat: number; lng: number; accuracy?: number },
): Promise<void> {
  try {
    await portalFetch<unknown>(`${API_BASE}/videoperizia/location-ping`, {
      method: "POST",
      headers: authHeaders(session),
      body: JSON.stringify(coords),
    });
  } catch {
    // best-effort — location pings are non-critical
  }
}

// --- Push notifications ---

export async function getPortalVapidPublicKey(): Promise<string> {
  const result = await portalFetch<{ public_key: string }>(`${API_BASE}/push/vapid-key`);
  return result.public_key;
}

export async function subscribePortalPush(
  session: PortalSession,
  subscription: PushSubscription,
): Promise<void> {
  await portalFetch<unknown>(`${API_BASE}/push/subscribe`, {
    method: "POST",
    headers: authHeaders(session),
    body: JSON.stringify(subscription.toJSON()),
  });
}

export async function unsubscribePortalPush(session: PortalSession): Promise<void> {
  await portalFetch<unknown>(`${API_BASE}/push/unsubscribe`, {
    method: "POST",
    headers: authHeaders(session),
  });
}

// --- Me (account / impostazioni) ---

export async function getPortalMeProfile(session: PortalSession): Promise<PortalMeProfile> {
  return portalFetch<PortalMeProfile>(`${API_BASE}/me/profile`, {
    headers: authHeaders(session),
  });
}

export async function updatePortalMeProfile(
  session: PortalSession,
  profile: Partial<PortalMeProfile>,
): Promise<PortalMeProfile> {
  return portalFetch<PortalMeProfile>(`${API_BASE}/me/profile`, {
    method: "PATCH",
    headers: authHeaders(session),
    body: JSON.stringify(profile),
  });
}

export async function getPortalMePolicy(session: PortalSession): Promise<PortalMePolicy> {
  return portalFetch<PortalMePolicy>(`${API_BASE}/me/policy`, {
    headers: authHeaders(session),
  });
}

export async function getPortalMeNotifications(
  session: PortalSession,
): Promise<PortalMeNotificationPrefs> {
  return portalFetch<PortalMeNotificationPrefs>(`${API_BASE}/me/notifications`, {
    headers: authHeaders(session),
  });
}

export async function updatePortalMeNotifications(
  session: PortalSession,
  prefs: Partial<PortalMeNotificationPrefs>,
): Promise<void> {
  await portalFetch<unknown>(`${API_BASE}/me/notifications`, {
    method: "PATCH",
    headers: authHeaders(session),
    body: JSON.stringify(prefs),
  });
}

export async function listPortalMeSessions(
  session: PortalSession,
): Promise<PortalMeSessionInfo[]> {
  return portalFetch<PortalMeSessionInfo[]>(`${API_BASE}/me/sessions`, {
    headers: authHeaders(session),
  });
}

export async function revokePortalMeSession(
  session: PortalSession,
  sessionId: string,
): Promise<void> {
  await portalFetch<unknown>(`${API_BASE}/me/sessions/${encodeURIComponent(sessionId)}`, {
    method: "DELETE",
    headers: authHeaders(session),
  });
}

export async function getActiveDeletionRequest(
  session: PortalSession,
): Promise<PortalMeDeletionRequest | null> {
  try {
    return await portalFetch<PortalMeDeletionRequest>(`${API_BASE}/me/deletion-request`, {
      headers: authHeaders(session),
    });
  } catch {
    return null;
  }
}

export async function createDeletionRequest(
  session: PortalSession,
  reason?: string,
): Promise<PortalMeDeletionRequest> {
  return portalFetch<PortalMeDeletionRequest>(`${API_BASE}/me/deletion-request`, {
    method: "POST",
    headers: authHeaders(session),
    body: JSON.stringify({ reason }),
  });
}

export async function cancelDeletionRequest(
  session: PortalSession,
  requestId: string,
): Promise<void> {
  await portalFetch<unknown>(
    `${API_BASE}/me/deletion-request/${encodeURIComponent(requestId)}/cancel`,
    { method: "POST", headers: authHeaders(session) },
  );
}
