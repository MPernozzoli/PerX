import {
  mockAuthStartResponse,
  mockAccessibleClaims,
  mockAdditionalDocumentSubmission,
  mockBankSubmission,
  mockClaimSummary,
  mockDocumentCollectionDraft,
  mockDocumentCollectionSubmission,
  mockDocuments,
  mockInspectionSchedulingOverview,
  mockMessages,
  mockSignatureConfirmation,
  mockSignatureRequest,
  mockTimeline,
  mockUploadIntent
} from "@/lib/mocks";
import type {
  PortalAuthRequestOtpResponse,
  PortalAuthStartResponse,
  PortalAccessibleClaim,
  PortalBankAccountSubmission,
  PortalClaimSummary,
  PortalDocument,
  PortalDocumentCollectionDraft,
  PortalDocumentCollectionSubmission,
  PortalInspectionSchedulingOverview,
  PortalMessageList,
  PortalAdditionalDocumentSubmission,
  PortalMeConsent,
  PortalMeDeletionRequest,
  PortalMeNotificationPrefs,
  PortalMePolicy,
  PortalMeProfile,
  PortalMeProfileUpdate,
  PortalMeSessionInfo,
  PortalSession,
  PortalSignatureConfirmation,
  PortalSignatureRequest,
  PortalTimelineEvent,
  PortalUploadIntent
} from "@/lib/types";
import { getBrowserPortalHost } from "@/lib/tenant";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_PORTAL_API_BASE_URL ?? "http://localhost:8000/api/v1/portal";

const USE_MOCKS = process.env.NEXT_PUBLIC_PORTAL_USE_MOCKS === "true";

export type PortalTenantBranding = {
  tenant_name?: string | null;
  icon_data_url?: string | null;
  badge_data_url?: string | null;
  logo_data_url?: string | null;
  primary_color?: string | null;
};

function withClaimId(path: string, claimId?: string): string {
  if (!claimId) {
    return path;
  }
  const separator = path.includes("?") ? "&" : "?";
  return `${path}${separator}claim_id=${encodeURIComponent(claimId)}`;
}

async function request<T>(
  path: string,
  init?: RequestInit,
  session?: PortalSession | null
): Promise<T> {
  const headers = new Headers(init?.headers);
  headers.set("Content-Type", "application/json");
  if (session?.accessToken) {
    headers.set("Authorization", `Bearer ${session.accessToken}`);
  }

  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers,
    cache: "no-store"
  });

  if (!response.ok) {
    let detail = "Richiesta non riuscita";
    try {
      const payload = (await response.json()) as { detail?: string };
      detail = payload.detail ?? detail;
    } catch {
      detail = response.statusText || detail;
    }
    throw new Error(detail);
  }

  return (await response.json()) as T;
}

export async function getPortalTenantBranding(): Promise<PortalTenantBranding> {
  if (USE_MOCKS) {
    return {};
  }
  const portalHost = getBrowserPortalHost();
  const query = portalHost ? `?portal_host=${encodeURIComponent(portalHost)}` : "";
  return request<PortalTenantBranding>(`/tenant/branding${query}`);
}

export async function startPortalAuth(payload: {
  claimReference?: string;
  taxCode?: string;
  fullName?: string;
  phoneNumber?: string;
}): Promise<PortalAuthStartResponse> {
  if (USE_MOCKS) {
    return mockAuthStartResponse;
  }

  return request<PortalAuthStartResponse>("/auth/start", {
    method: "POST",
    body: JSON.stringify({
      claim_reference: payload.claimReference || null,
      tax_code: payload.taxCode || null,
      full_name: payload.fullName || null,
      phone_number: payload.phoneNumber || null,
      channel: "email",
      portal_host: getBrowserPortalHost()
    })
  });
}

export async function exchangePortalToken(
  token: string,
  rememberMe = false
): Promise<PortalSession> {
  if (USE_MOCKS) {
    return {
      accessToken: "mock-portal-access-token",
      claimId: "claim-mock-001",
      portalAccessId: "portal-access-mock"
    };
  }

  const response = await request<{
    access_token: string;
    claim_id: string;
    portal_access_id: string;
  }>("/auth/exchange", {
    method: "POST",
    body: JSON.stringify({
      token,
      remember_me: rememberMe,
      portal_host: getBrowserPortalHost()
    })
  });

  return {
    accessToken: response.access_token,
    claimId: response.claim_id,
    portalAccessId: response.portal_access_id
  };
}

export async function requestPortalOtp(payload: {
  claimReference: string;
  phoneNumber: string;
  channel?: "sms" | "email";
}): Promise<PortalAuthRequestOtpResponse> {
  if (USE_MOCKS) {
    return {
      status: "otp_sent",
      delivery_channel: payload.channel ?? "sms",
      masked_destination: "***1234",
      expires_at: new Date(Date.now() + 10 * 60_000).toISOString()
    };
  }

  return request<PortalAuthRequestOtpResponse>("/auth/request-otp", {
    method: "POST",
    body: JSON.stringify({
      claim_reference: payload.claimReference,
      phone_number: payload.phoneNumber,
      channel: payload.channel ?? "sms",
      portal_host: getBrowserPortalHost()
    })
  });
}

export async function verifyPortalOtp(payload: {
  claimReference: string;
  phoneNumber: string;
  otpCode: string;
  rememberMe?: boolean;
}): Promise<PortalSession> {
  if (USE_MOCKS) {
    return {
      accessToken: "mock-portal-access-token",
      claimId: "claim-mock-001",
      portalAccessId: "portal-access-mock"
    };
  }

  const response = await request<{
    access_token: string;
    claim_id: string;
    portal_access_id: string;
  }>("/auth/verify-otp", {
    method: "POST",
    body: JSON.stringify({
      claim_reference: payload.claimReference,
      phone_number: payload.phoneNumber,
      otp_code: payload.otpCode,
      remember_me: Boolean(payload.rememberMe),
      portal_host: getBrowserPortalHost()
    })
  });

  return {
    accessToken: response.access_token,
    claimId: response.claim_id,
    portalAccessId: response.portal_access_id
  };
}

export async function getPortalClaimSummary(session: PortalSession): Promise<PortalClaimSummary> {
  return getPortalClaimSummaryForClaim(session);
}

export async function getPortalVapidPublicKey(): Promise<string | null> {
  if (USE_MOCKS) return null;
  const response = await request<{ public_key: string | null }>(
    "/push/vapid-public-key"
  );
  return response.public_key;
}

export async function subscribePortalPush(
  session: PortalSession,
  subscription: { endpoint: string; p256dh: string; auth: string; userAgent?: string | null }
): Promise<{ id: string; status: string }> {
  if (USE_MOCKS) return { id: "mock-sub", status: "active" };
  return request<{ id: string; status: string }>(
    "/push/subscribe",
    {
      method: "POST",
      body: JSON.stringify({
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        user_agent: subscription.userAgent ?? null
      })
    },
    session
  );
}

export async function unsubscribePortalPush(
  session: PortalSession,
  endpoint: string
): Promise<void> {
  if (USE_MOCKS) return;
  await request<{ status: string }>(
    "/push/unsubscribe",
    {
      method: "POST",
      body: JSON.stringify({ endpoint, p256dh: "", auth: "" })
    },
    session
  );
}

export async function listAccessibleClaims(
  session: PortalSession
): Promise<PortalAccessibleClaim[]> {
  if (USE_MOCKS) {
    return mockAccessibleClaims;
  }
  return request<PortalAccessibleClaim[]>("/claims", undefined, session);
}

export async function getPortalClaimSummaryForClaim(
  session: PortalSession,
  claimId?: string
): Promise<PortalClaimSummary> {
  if (USE_MOCKS) {
    if (claimId === "claim-mock-002") {
      return {
        ...mockClaimSummary,
        claim_id: "claim-mock-002",
        external_ref: "PX-2026-00117",
        numero_sinistro: "SIN-880112",
        macro_state: mockAccessibleClaims[1].macro_state,
        requirements: [],
        upcoming_appointment: null,
        inspection_scheduling_enabled: false,
        requested_amount: 1800,
        liquidated_amount: 1450,
        estimated_damage_amount: 1450,
        act_sent_at: "2026-04-02T09:10:00Z",
        act_signed_at: null
      };
    }
    return mockClaimSummary;
  }
  return request<PortalClaimSummary>(withClaimId("/claim", claimId), undefined, session);
}

export async function getPortalTimeline(
  session: PortalSession,
  claimId?: string
): Promise<PortalTimelineEvent[]> {
  if (USE_MOCKS) {
    return mockTimeline;
  }
  return request<PortalTimelineEvent[]>(withClaimId("/claim/timeline", claimId), undefined, session);
}

export async function getInspectionSchedulingOverview(
  session: PortalSession,
  claimId?: string
): Promise<PortalInspectionSchedulingOverview> {
  if (USE_MOCKS) {
    if (claimId === "claim-mock-002") {
      return {
        ...mockInspectionSchedulingOverview,
        enabled: false,
        status: "disabled",
        instructions: "La schedulazione sopralluogo non e attualmente richiesta.",
        availability_days: [],
        selected_slots: [],
        candidate_cats: []
      };
    }
    return mockInspectionSchedulingOverview;
  }
  return request<PortalInspectionSchedulingOverview>(
    withClaimId("/claim/inspection-scheduling", claimId),
    undefined,
    session
  );
}

export async function updateInspectionLocation(
  session: PortalSession,
  payload: {
    addressLine?: string;
    municipality?: string;
    province?: string;
    region?: string;
    latitude?: number;
    longitude?: number;
  },
  claimId?: string
): Promise<PortalInspectionSchedulingOverview> {
  if (USE_MOCKS) {
    return {
      ...mockInspectionSchedulingOverview,
      address_confirmed: true,
      location: {
        ...mockInspectionSchedulingOverview.location,
        address_line: payload.addressLine ?? mockInspectionSchedulingOverview.location.address_line,
        municipality: payload.municipality ?? mockInspectionSchedulingOverview.location.municipality,
        province: payload.province ?? mockInspectionSchedulingOverview.location.province,
        region: payload.region ?? mockInspectionSchedulingOverview.location.region,
        latitude: payload.latitude ?? mockInspectionSchedulingOverview.location.latitude,
        longitude: payload.longitude ?? mockInspectionSchedulingOverview.location.longitude,
        confirmed_at: new Date().toISOString()
      }
    };
  }
  return request<PortalInspectionSchedulingOverview>(
    withClaimId("/claim/inspection-scheduling/location", claimId),
    {
      method: "PUT",
      body: JSON.stringify({
        address_line: payload.addressLine ?? null,
        municipality: payload.municipality ?? null,
        province: payload.province ?? null,
        region: payload.region ?? null,
        latitude: payload.latitude ?? null,
        longitude: payload.longitude ?? null
      })
    },
    session
  );
}

export async function submitInspectionPreferences(
  session: PortalSession,
  payload: {
    selectedSlots: Array<{
      date: string;
      startTime: string;
      endTime: string;
      label?: string;
    }>;
    notes?: string;
    requestedDurationMinutes?: number;
  },
  claimId?: string
): Promise<PortalInspectionSchedulingOverview> {
  if (USE_MOCKS) {
    return {
      ...mockInspectionSchedulingOverview,
      status: "pending_confirmation",
      selected_slots: payload.selectedSlots.map((slot, index) => ({
        id: `selected-${index}`,
        date: slot.date,
        start_at: new Date(`${slot.date}T${slot.startTime}:00`).toISOString(),
        end_at: new Date(`${slot.date}T${slot.endTime}:00`).toISOString(),
        label: slot.label ?? `${slot.startTime} - ${slot.endTime}`
      })),
      pending_confirmation_message:
        "Riceverai un messaggio di conferma del sopralluogo entro le 24 ore precedenti alla data selezionata. Fino a quel messaggio l'appuntamento non e confermato."
    };
  }
  return request<PortalInspectionSchedulingOverview>(
    withClaimId("/claim/inspection-scheduling/preferences", claimId),
    {
      method: "PUT",
      body: JSON.stringify({
        selected_slots: payload.selectedSlots.map((slot) => ({
          date: slot.date,
          start_time: slot.startTime,
          end_time: slot.endTime,
          label: slot.label ?? null
        })),
        notes: payload.notes ?? null,
        requested_duration_minutes: payload.requestedDurationMinutes ?? null
      })
    },
    session
  );
}

export async function getPortalDocuments(
  session: PortalSession,
  claimId?: string
): Promise<PortalDocument[]> {
  if (USE_MOCKS) {
    return mockDocuments;
  }
  return request<PortalDocument[]>(withClaimId("/claim/documents", claimId), undefined, session);
}

export async function downloadPortalDocument(
  session: PortalSession,
  payload: { documentId: string },
  claimId?: string
): Promise<Blob> {
  const headers = new Headers();
  if (session.accessToken) {
    headers.set("Authorization", `Bearer ${session.accessToken}`);
  }
  const response = await fetch(
    `${API_BASE_URL}${withClaimId(`/claim/documents/${encodeURIComponent(payload.documentId)}/download`, claimId)}`,
    {
      method: "GET",
      headers,
      cache: "no-store"
    }
  );
  if (!response.ok) {
    let detail = "Download non riuscito";
    try {
      const body = (await response.json()) as { detail?: string };
      detail = body.detail ?? detail;
    } catch {
      detail = response.statusText || detail;
    }
    throw new Error(detail);
  }
  return response.blob();
}

export async function createUploadIntent(
  session: PortalSession,
  payload: { fileName: string; mimeType?: string; sizeBytes?: number; category?: string },
  claimId?: string
): Promise<PortalUploadIntent> {
  if (USE_MOCKS) {
    return mockUploadIntent(payload.fileName);
  }
  return request<PortalUploadIntent>(
    withClaimId("/claim/upload-intents", claimId),
    {
      method: "POST",
      body: JSON.stringify({
        file_name: payload.fileName,
        mime_type: payload.mimeType || null,
        size_bytes: payload.sizeBytes ?? 0,
        category: payload.category || null
      })
    },
    session
  );
}

export async function uploadPortalDocumentFile(
  session: PortalSession,
  payload: {
    documentId: string;
    file: File;
  },
  claimId?: string
): Promise<{
  document_id: string;
  file_name: string;
  status: string;
  storage_path: string;
  uploaded_at: string;
}> {
  if (USE_MOCKS) {
    return {
      document_id: payload.documentId,
      file_name: payload.file.name,
      status: "uploaded",
      storage_path: `/mock/${payload.file.name}`,
      uploaded_at: new Date().toISOString()
    };
  }

  const headers = new Headers();
  if (session.accessToken) {
    headers.set("Authorization", `Bearer ${session.accessToken}`);
  }

  const formData = new FormData();
  formData.append("file", payload.file);

  const response = await fetch(
    `${API_BASE_URL}${withClaimId(`/claim/documents/${encodeURIComponent(payload.documentId)}/upload`, claimId)}`,
    {
      method: "POST",
      headers,
      body: formData,
      cache: "no-store"
    }
  );

  if (!response.ok) {
    let detail = "Upload non riuscito";
    try {
      const body = (await response.json()) as { detail?: string };
      detail = body.detail ?? detail;
    } catch {
      detail = response.statusText || detail;
    }
    throw new Error(detail);
  }

  return (await response.json()) as {
    document_id: string;
    file_name: string;
    status: string;
    storage_path: string;
    uploaded_at: string;
  };
}

export async function submitDocumentCollection(
  session: PortalSession,
  payload: {
    notes?: string;
    photosCount: number;
    items: Array<{
      name: string;
      brand?: string;
      model?: string;
      purchaseYear?: number;
      quantity: number;
    }>;
    metadataJson?: Record<string, unknown>;
  },
  claimId?: string
): Promise<PortalDocumentCollectionSubmission> {
  if (USE_MOCKS) {
    return mockDocumentCollectionSubmission;
  }
  return request<PortalDocumentCollectionSubmission>(
    withClaimId("/claim/document-collection-submissions", claimId),
    {
      method: "POST",
      body: JSON.stringify({
        items: payload.items.map((item) => ({
          name: item.name,
          brand: item.brand || null,
          model: item.model || null,
          purchase_year: item.purchaseYear ?? null,
          quantity: item.quantity
        })),
        notes: payload.notes || null,
        photos_count: payload.photosCount,
        metadata_json: payload.metadataJson ?? null
      })
    },
    session
  );
}

export async function getDocumentCollectionDraft(
  session: PortalSession,
  claimId?: string
): Promise<PortalDocumentCollectionDraft> {
  if (USE_MOCKS) {
    return mockDocumentCollectionDraft;
  }
  return request<PortalDocumentCollectionDraft>(
    withClaimId("/claim/document-collection-draft", claimId),
    undefined,
    session
  );
}

export async function saveDocumentCollectionDraft(
  session: PortalSession,
  payload: { draftJson: Record<string, unknown> },
  claimId?: string
): Promise<PortalDocumentCollectionDraft> {
  if (USE_MOCKS) {
    return {
      ...mockDocumentCollectionDraft,
      draft_json: payload.draftJson,
      updated_at: new Date().toISOString()
    };
  }
  return request<PortalDocumentCollectionDraft>(
    withClaimId("/claim/document-collection-draft", claimId),
    {
      method: "PUT",
      body: JSON.stringify({
        draft_json: payload.draftJson
      })
    },
    session
  );
}

export async function submitBankAccount(
  session: PortalSession,
  payload: { iban: string; accountHolder?: string },
  claimId?: string
): Promise<PortalBankAccountSubmission> {
  if (USE_MOCKS) {
    return mockBankSubmission(payload.iban);
  }
  return request<PortalBankAccountSubmission>(
    withClaimId("/claim/bank-accounts", claimId),
    {
      method: "POST",
      body: JSON.stringify({
        iban: payload.iban,
        account_holder: payload.accountHolder || null
      })
    },
    session
  );
}

export async function submitAdditionalDocuments(
  session: PortalSession,
  payload: {
    note?: string;
    documentIds: string[];
    requestedItems?: string[];
  },
  claimId?: string
): Promise<PortalAdditionalDocumentSubmission> {
  if (USE_MOCKS) {
    return mockAdditionalDocumentSubmission;
  }
  return request<PortalAdditionalDocumentSubmission>(
    withClaimId("/claim/additional-document-submissions", claimId),
    {
      method: "POST",
      body: JSON.stringify({
        note: payload.note ?? null,
        document_ids: payload.documentIds,
        requested_items: payload.requestedItems ?? []
      })
    },
    session
  );
}

export async function listPortalMessages(
  session: PortalSession,
  claimId?: string
): Promise<PortalMessageList> {
  if (USE_MOCKS) {
    return mockMessages;
  }
  return request<PortalMessageList>(withClaimId("/claim/chat/messages", claimId), undefined, session);
}

export async function createPortalMessage(
  session: PortalSession,
  payload: { bodyText: string },
  claimId?: string
): Promise<void> {
  if (USE_MOCKS) {
    return;
  }
  await request(
    withClaimId("/claim/chat/messages", claimId),
    {
      method: "POST",
      body: JSON.stringify({ body_text: payload.bodyText })
    },
    session
  );
}

export async function createSignatureRequest(
  session: PortalSession,
  payload: { documentId: string },
  claimId?: string
): Promise<PortalSignatureRequest> {
  if (USE_MOCKS) {
    return mockSignatureRequest;
  }
  return request<PortalSignatureRequest>(
    withClaimId("/claim/signature-requests", claimId),
    {
      method: "POST",
      body: JSON.stringify({
        document_id: payload.documentId,
        signature_method: "otp"
      })
    },
    session
  );
}

export async function confirmSignatureRequest(
  session: PortalSession,
  payload: { requestId: string; token: string },
  claimId?: string
): Promise<PortalSignatureConfirmation> {
  if (USE_MOCKS) {
    return mockSignatureConfirmation;
  }
  return request<PortalSignatureConfirmation>(
    withClaimId(`/claim/signature-requests/${payload.requestId}/confirm`, claimId),
    {
      method: "POST",
      body: JSON.stringify({ token: payload.token })
    },
    session
  );
}

// ============================================================================
// Portal Me — Impostazioni e privacy (/api/v1/portal/me/*)
// ============================================================================

export async function getPortalMeProfile(session: PortalSession): Promise<PortalMeProfile> {
  return request<PortalMeProfile>("/me/profile", undefined, session);
}

export async function updatePortalMeProfile(
  session: PortalSession,
  payload: PortalMeProfileUpdate
): Promise<PortalMeProfile> {
  return request<PortalMeProfile>(
    "/me/profile",
    { method: "PATCH", body: JSON.stringify(payload) },
    session
  );
}

export async function getPortalMePolicy(session: PortalSession): Promise<PortalMePolicy> {
  return request<PortalMePolicy>("/me/privacy/policy", undefined, session);
}

export async function listPortalMeConsents(session: PortalSession): Promise<PortalMeConsent[]> {
  return request<PortalMeConsent[]>("/me/privacy/consents", undefined, session);
}

export async function acceptPortalMeConsent(
  session: PortalSession,
  payload: { policyId: string; consentType?: string }
): Promise<PortalMeConsent> {
  return request<PortalMeConsent>(
    "/me/privacy/consents",
    {
      method: "POST",
      body: JSON.stringify({
        policy_id: payload.policyId,
        consent_type: payload.consentType ?? "privacy"
      })
    },
    session
  );
}

export async function getPortalMeNotifications(
  session: PortalSession
): Promise<PortalMeNotificationPrefs> {
  return request<PortalMeNotificationPrefs>("/me/notifications", undefined, session);
}

export async function updatePortalMeNotifications(
  session: PortalSession,
  payload: PortalMeNotificationPrefs
): Promise<PortalMeNotificationPrefs> {
  return request<PortalMeNotificationPrefs>(
    "/me/notifications",
    { method: "PUT", body: JSON.stringify(payload) },
    session
  );
}

export async function getActiveDeletionRequest(
  session: PortalSession
): Promise<PortalMeDeletionRequest | null> {
  return request<PortalMeDeletionRequest | null>("/me/deletion-request", undefined, session);
}

export async function createDeletionRequest(
  session: PortalSession,
  reason?: string
): Promise<PortalMeDeletionRequest> {
  return request<PortalMeDeletionRequest>(
    "/me/deletion-request",
    { method: "POST", body: JSON.stringify({ reason: reason ?? null }) },
    session
  );
}

export async function cancelDeletionRequest(
  session: PortalSession,
  requestId: string
): Promise<void> {
  await request<void>(
    `/me/deletion-request/${encodeURIComponent(requestId)}`,
    { method: "DELETE" },
    session
  );
}

export async function listPortalMeSessions(session: PortalSession): Promise<PortalMeSessionInfo[]> {
  return request<PortalMeSessionInfo[]>("/me/sessions", undefined, session);
}

export async function revokePortalMeSession(
  session: PortalSession,
  sessionId: string
): Promise<void> {
  await request<void>(
    `/me/sessions/${encodeURIComponent(sessionId)}`,
    { method: "DELETE" },
    session
  );
}
