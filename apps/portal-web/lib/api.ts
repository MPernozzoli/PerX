import type {
  PortalAccessibleClaim,
  PortalAuthRequestOtpResponse,
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
  tenant_name?: string | null;
  icon_data_url?: string | null;
  badge_data_url?: string | null;
  logo_data_url?: string | null;
  primary_color?: string | null;
}

export interface PortalUploadIntent {
  document_id: string;
  upload_mode: "signed-url" | "server-proxy";
  upload_url?: string;
  storage_path: string;
  expires_in: number;
}

export interface PortalUploadedDocument {
  document_id: string;
  file_name: string;
  status: string;
  storage_path: string;
  uploaded_at?: string;
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
  if (response.status === 204) {
    return undefined as T;
  }
  const text = await response.text();
  if (!text) {
    return undefined as T;
  }
  return JSON.parse(text) as T;
}

/** Claim-scoped endpoints derive the claim from the session by default;
 * `claimId` is only needed to view a *different* accessible claim. */
function claimUrl(path: string, claimId?: string): string {
  if (!claimId) return `${API_BASE}${path}`;
  const sep = path.includes("?") ? "&" : "?";
  return `${API_BASE}${path}${sep}claim_id=${encodeURIComponent(claimId)}`;
}

function toPortalSession(data: {
  access_token: string;
  expires_in: number;
  claim_id: string;
  portal_access_id: string;
}): PortalSession {
  return {
    token: data.access_token,
    claimId: data.claim_id,
    portalAccessId: data.portal_access_id,
    expiresAt: new Date(Date.now() + data.expires_in * 1000).toISOString(),
  };
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
    body: JSON.stringify({
      claim_reference: params.claimReference,
      tax_code: params.taxCode || undefined,
      full_name: params.fullName || undefined,
      phone_number: params.phoneNumber || undefined,
      channel: "email",
    }),
  });
}

export async function exchangePortalToken(
  token: string,
  rememberMe = false,
): Promise<PortalSession> {
  const data = await portalFetch<{
    access_token: string;
    expires_in: number;
    claim_id: string;
    portal_access_id: string;
  }>(`${API_BASE}/auth/exchange`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token, remember_me: rememberMe }),
  });
  return toPortalSession(data);
}

export async function requestPortalOtp(params: {
  claimReference: string;
  phoneNumber: string;
  channel: string;
}): Promise<PortalAuthRequestOtpResponse> {
  return portalFetch(`${API_BASE}/auth/request-otp`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      claim_reference: params.claimReference,
      phone_number: params.phoneNumber,
      channel: params.channel,
    }),
  });
}

export async function verifyPortalOtp(params: {
  claimReference: string;
  phoneNumber: string;
  otpCode: string;
  rememberMe: boolean;
}): Promise<PortalSession> {
  const data = await portalFetch<{
    access_token: string;
    expires_in: number;
    claim_id: string;
    portal_access_id: string;
  }>(`${API_BASE}/auth/verify-otp`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      claim_reference: params.claimReference,
      phone_number: params.phoneNumber,
      otp_code: params.otpCode,
      remember_me: params.rememberMe,
    }),
  });
  return toPortalSession(data);
}

// --- Tenant branding ---

export async function getPortalTenantBranding(host?: string): Promise<PortalTenantBranding> {
  const resolvedHost =
    host ?? (typeof window !== "undefined" ? window.location.hostname : "");
  try {
    return await portalFetch<PortalTenantBranding>(
      `${API_BASE}/tenant/branding?portal_host=${encodeURIComponent(resolvedHost)}`,
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
  return portalFetch<PortalClaimSummary>(claimUrl("/claim", claimId), {
    headers: authHeaders(session),
  });
}

export async function getPortalTimeline(
  session: PortalSession,
  claimId: string,
): Promise<PortalTimelineEvent[]> {
  return portalFetch<PortalTimelineEvent[]>(claimUrl("/claim/timeline", claimId), {
    headers: authHeaders(session),
  });
}

export async function getPortalDocuments(
  session: PortalSession,
  claimId: string,
): Promise<PortalDocument[]> {
  return portalFetch<PortalDocument[]>(claimUrl("/claim/documents", claimId), {
    headers: authHeaders(session),
  });
}

export async function listPortalMessages(
  session: PortalSession,
  claimId: string,
): Promise<PortalMessageList> {
  return portalFetch<PortalMessageList>(claimUrl("/claim/chat/messages", claimId), {
    headers: authHeaders(session),
  });
}

export async function createPortalMessage(
  session: PortalSession,
  params: { bodyText: string },
  claimId: string,
): Promise<PortalMessage> {
  return portalFetch<PortalMessage>(claimUrl("/claim/chat/messages", claimId), {
    method: "POST",
    headers: authHeaders(session),
    body: JSON.stringify({ body_text: params.bodyText }),
  });
}

export async function getInspectionSchedulingOverview(
  session: PortalSession,
  claimId: string,
): Promise<PortalInspectionSchedulingOverview> {
  return portalFetch<PortalInspectionSchedulingOverview>(
    claimUrl("/claim/inspection-scheduling", claimId),
    { headers: authHeaders(session) },
  );
}

export async function submitInspectionPreferences(
  session: PortalSession,
  params: {
    selectedSlots: Array<{ date: string; startTime: string; endTime: string; label: string }>;
    notes?: string;
    requestedDurationMinutes?: number;
  },
  claimId: string,
): Promise<PortalInspectionSchedulingOverview> {
  return portalFetch<PortalInspectionSchedulingOverview>(
    claimUrl("/claim/inspection-scheduling/preferences", claimId),
    {
      method: "PUT",
      headers: authHeaders(session),
      body: JSON.stringify({
        selected_slots: params.selectedSlots.map((slot) => ({
          date: slot.date,
          start_time: slot.startTime,
          end_time: slot.endTime,
          label: slot.label,
        })),
        notes: params.notes,
        requested_duration_minutes: params.requestedDurationMinutes,
      }),
    },
  );
}

export async function updateInspectionLocation(
  session: PortalSession,
  params: {
    addressLine?: string;
    municipality?: string;
    province?: string;
    region?: string;
    latitude?: number;
    longitude?: number;
  },
  claimId: string,
): Promise<PortalInspectionSchedulingOverview> {
  return portalFetch<PortalInspectionSchedulingOverview>(
    claimUrl("/claim/inspection-scheduling/location", claimId),
    {
      method: "PUT",
      headers: authHeaders(session),
      body: JSON.stringify({
        address_line: params.addressLine,
        municipality: params.municipality,
        province: params.province,
        region: params.region,
        latitude: params.latitude,
        longitude: params.longitude,
      }),
    },
  );
}

// --- IBAN ---

export async function submitBankAccount(
  session: PortalSession,
  params: { iban: string; accountHolder?: string },
  claimId: string,
): Promise<PortalBankAccountSubmission> {
  return portalFetch<PortalBankAccountSubmission>(claimUrl("/claim/bank-accounts", claimId), {
    method: "POST",
    headers: authHeaders(session),
    body: JSON.stringify({ iban: params.iban, account_holder: params.accountHolder }),
  });
}

// --- Documents ---

export async function downloadPortalDocument(
  session: PortalSession,
  params: { documentId: string },
  claimId: string,
): Promise<Blob> {
  const response = await fetch(
    claimUrl(`/claim/documents/${encodeURIComponent(params.documentId)}/download`, claimId),
    { headers: { Authorization: `Bearer ${session.token}` } },
  );
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.blob();
}

export async function createUploadIntent(
  session: PortalSession,
  params: { fileName: string; mimeType?: string; sizeBytes?: number; category?: string },
  claimId: string,
): Promise<PortalUploadIntent> {
  return portalFetch<PortalUploadIntent>(claimUrl("/claim/upload-intents", claimId), {
    method: "POST",
    headers: authHeaders(session),
    body: JSON.stringify({
      file_name: params.fileName,
      mime_type: params.mimeType,
      size_bytes: params.sizeBytes ?? 0,
      category: params.category,
    }),
  });
}

/** Confirms a direct-to-storage upload (`upload_mode: "signed-url"`) once the
 * browser has PUT the file straight to the signed URL from createUploadIntent. */
export async function confirmPortalDocumentUpload(
  session: PortalSession,
  params: { documentId: string; fileName: string; mimeType?: string; sizeBytes: number },
  claimId: string,
): Promise<PortalUploadedDocument> {
  return portalFetch<PortalUploadedDocument>(
    claimUrl(`/claim/documents/${encodeURIComponent(params.documentId)}/confirm-upload`, claimId),
    {
      method: "POST",
      headers: authHeaders(session),
      body: JSON.stringify({
        file_name: params.fileName,
        mime_type: params.mimeType,
        size_bytes: params.sizeBytes,
      }),
    },
  );
}

export async function uploadPortalDocumentFile(
  session: PortalSession,
  params: { documentId: string; file: File },
  claimId: string,
): Promise<PortalUploadedDocument> {
  const form = new FormData();
  form.append("file", params.file);
  const response = await fetch(
    claimUrl(`/claim/documents/${encodeURIComponent(params.documentId)}/upload`, claimId),
    {
      method: "POST",
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
  return response.json() as Promise<PortalUploadedDocument>;
}

/** Uploads a file via the fastest transport createUploadIntent granted us:
 * a direct PUT to storage when a signed URL is available, otherwise the
 * server-proxied multipart upload. */
export async function uploadPortalDocumentViaIntent(
  session: PortalSession,
  intent: PortalUploadIntent,
  file: File,
  claimId: string,
): Promise<PortalUploadedDocument> {
  if (intent.upload_mode === "signed-url" && intent.upload_url) {
    const putResponse = await fetch(intent.upload_url, {
      method: "PUT",
      headers: { "Content-Type": file.type || "application/octet-stream" },
      body: file,
    });
    if (!putResponse.ok) {
      throw new Error(`Caricamento file non riuscito (HTTP ${putResponse.status})`);
    }
    return confirmPortalDocumentUpload(
      session,
      {
        documentId: intent.document_id,
        fileName: file.name,
        mimeType: file.type,
        sizeBytes: file.size,
      },
      claimId,
    );
  }
  return uploadPortalDocumentFile(session, { documentId: intent.document_id, file }, claimId);
}

export async function getDocumentCollectionDraft(
  session: PortalSession,
  claimId: string,
): Promise<{ status: string; draft_json: unknown; updated_at?: string }> {
  return portalFetch(claimUrl("/claim/document-collection-draft", claimId), {
    headers: authHeaders(session),
  });
}

export async function saveDocumentCollectionDraft(
  session: PortalSession,
  params: { draftJson: unknown },
  claimId: string,
): Promise<{ status: string; draft_json: unknown; updated_at?: string }> {
  return portalFetch(claimUrl("/claim/document-collection-draft", claimId), {
    method: "PUT",
    headers: authHeaders(session),
    body: JSON.stringify({ draft_json: params.draftJson }),
  });
}

export async function submitDocumentCollection(
  session: PortalSession,
  params: {
    notes?: string;
    photosCount: number;
    items: Array<{ name: string; brand?: string; model?: string; purchaseYear?: number; quantity?: number }>;
    metadataJson?: Record<string, unknown>;
    locationLatitude?: number;
    locationLongitude?: number;
  },
  claimId: string,
): Promise<{ id: string; status: string; submitted_at: string }> {
  return portalFetch(claimUrl("/claim/document-collection-submissions", claimId), {
    method: "POST",
    headers: authHeaders(session),
    body: JSON.stringify({
      items: params.items.map((item) => ({
        name: item.name,
        brand: item.brand,
        model: item.model,
        purchase_year: item.purchaseYear,
        quantity: item.quantity ?? 1,
      })),
      notes: params.notes,
      location_latitude: params.locationLatitude,
      location_longitude: params.locationLongitude,
      photos_count: params.photosCount,
      metadata_json: params.metadataJson,
    }),
  });
}

export async function submitAdditionalDocuments(
  session: PortalSession,
  params: { note?: string; documentIds: string[]; requestedItems: string[] },
  claimId: string,
): Promise<{ status: string; submitted_at: string; document_count: number }> {
  return portalFetch(claimUrl("/claim/additional-document-submissions", claimId), {
    method: "POST",
    headers: authHeaders(session),
    body: JSON.stringify({
      note: params.note,
      document_ids: params.documentIds,
      requested_items: params.requestedItems,
    }),
  });
}

// --- Videoperizia ---
// Session-scoped: the active claim already comes from the portal session, so
// none of these take a claimId.

export async function getVideoperiziaSession(
  session: PortalSession,
): Promise<PortalVideoperiziaSession | null> {
  const data = await portalFetch<{ session: PortalVideoperiziaSession | null }>(
    `${API_BASE}/claim/videoperizia/session`,
    { headers: authHeaders(session) },
  );
  return data.session;
}

export async function joinVideoperiziaLobby(
  session: PortalSession,
  params: { userAgent?: string | null },
): Promise<PortalVideoperiziaSession> {
  const data = await portalFetch<{ session: PortalVideoperiziaSession }>(
    `${API_BASE}/claim/videoperizia/lobby`,
    {
      method: "POST",
      headers: authHeaders(session),
      body: JSON.stringify({
        client_meta: params.userAgent ? { user_agent: params.userAgent } : undefined,
      }),
    },
  );
  return data.session;
}

export async function mintVideoperiziaToken(
  session: PortalSession,
): Promise<PortalVideoperiziaToken> {
  return portalFetch<PortalVideoperiziaToken>(`${API_BASE}/claim/videoperizia/token`, {
    method: "POST",
    headers: authHeaders(session),
  });
}

export async function leaveVideoperiziaSession(session: PortalSession): Promise<void> {
  await portalFetch<unknown>(`${API_BASE}/claim/videoperizia/leave`, {
    method: "POST",
    headers: authHeaders(session),
  });
}

export async function publishVideoperiziaLocationPing(
  session: PortalSession,
  coords: {
    latitude: number;
    longitude: number;
    accuracy_m?: number | null;
    altitude_m?: number | null;
    speed_mps?: number | null;
    heading_deg?: number | null;
    recorded_at?: string;
  },
): Promise<void> {
  try {
    await portalFetch<unknown>(`${API_BASE}/claim/videoperizia/location-ping`, {
      method: "POST",
      headers: authHeaders(session),
      body: JSON.stringify(coords),
    });
  } catch {
    // best-effort — location pings are non-critical
  }
}

// --- Push notifications ---

export async function getPortalVapidPublicKey(): Promise<string | null> {
  const result = await portalFetch<{ public_key: string | null }>(
    `${API_BASE}/push/vapid-public-key`,
  );
  return result.public_key;
}

export async function subscribePortalPush(
  session: PortalSession,
  subscription: { endpoint: string; p256dh: string; auth: string; userAgent?: string },
): Promise<void> {
  await portalFetch<unknown>(`${API_BASE}/push/subscribe`, {
    method: "POST",
    headers: authHeaders(session),
    body: JSON.stringify({
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
      user_agent: subscription.userAgent,
    }),
  });
}

export async function unsubscribePortalPush(session: PortalSession, endpoint: string): Promise<void> {
  await portalFetch<unknown>(`${API_BASE}/push/unsubscribe`, {
    method: "POST",
    headers: authHeaders(session),
    body: JSON.stringify({ endpoint }),
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
  profile: { email?: string; phone?: string },
): Promise<PortalMeProfile> {
  return portalFetch<PortalMeProfile>(`${API_BASE}/me/profile`, {
    method: "PATCH",
    headers: authHeaders(session),
    body: JSON.stringify(profile),
  });
}

export async function getPortalMePolicy(session: PortalSession): Promise<PortalMePolicy> {
  return portalFetch<PortalMePolicy>(`${API_BASE}/me/privacy/policy`, {
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
): Promise<PortalMeNotificationPrefs> {
  return portalFetch<PortalMeNotificationPrefs>(`${API_BASE}/me/notifications`, {
    method: "PUT",
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
    return await portalFetch<PortalMeDeletionRequest | null>(`${API_BASE}/me/deletion-request`, {
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
    `${API_BASE}/me/deletion-request/${encodeURIComponent(requestId)}`,
    { method: "DELETE", headers: authHeaders(session) },
  );
}
