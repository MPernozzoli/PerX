export type PortalAuthStartResponse = {
  status: string;
  challenge_id?: string | null;
  delivery_channel?: string | null;
  masked_destination?: string | null;
  expires_at?: string | null;
  preview_magic_link_url?: string | null;
};

export type PortalAuthRequestOtpResponse = {
  status: string;
  challenge_id?: string | null;
  delivery_channel?: string | null;
  masked_destination?: string | null;
  expires_at?: string | null;
  preview_otp_code?: string | null;
};

export type PortalSession = {
  accessToken: string;
  claimId: string;
  portalAccessId: string;
};

export type PortalMacroState = {
  code: string;
  label: string;
  description: string;
  needs_action: boolean;
  internal_state?: string | null;
};

export type PortalRequirement = {
  key: string;
  label: string;
  status: string;
  description: string;
};

export type PortalAppointment = {
  id: string;
  title: string;
  starts_at: string;
  ends_at: string;
  location?: string | null;
  status: string;
};

export type PortalExpert = {
  user_id?: string | null;
  full_name?: string | null;
  email?: string | null;
  phone_number?: string | null;
  job_title?: string | null;
  is_available_now: boolean;
  is_online: boolean;
  availability_note?: string | null;
};

export type PortalDocumentCollectionDraftInfo = {
  available: boolean;
  status: string;
  current_step?: string | null;
  updated_at?: string | null;
  submitted_at?: string | null;
};

export type PortalActFlow = {
  status: string;
  label: string;
  provider?: string | null;
  signing_url?: string | null;
  provider_reference?: string | null;
  request_id?: string | null;
  act_document_id?: string | null;
  signed_document_id?: string | null;
  countersigned_document_id?: string | null;
  signed_at?: string | null;
  countersigned_at?: string | null;
};

export type PortalClaimSummary = {
  claim_id: string;
  tenant_id: string;
  external_ref?: string | null;
  numero_sinistro?: string | null;
  compagnia?: string | null;
  nome_assicurato?: string | null;
  data_sinistro?: string | null;
  macro_state: PortalMacroState;
  expert: PortalExpert;
  requirements: PortalRequirement[];
  upcoming_appointment?: PortalAppointment | null;
  chat_enabled: boolean;
  document_upload_enabled: boolean;
  act_signature_enabled: boolean;
  inspection_scheduling_enabled: boolean;
  requested_amount?: number | null;
  liquidated_amount?: number | null;
  estimated_damage_amount?: number | null;
  act_sent_at?: string | null;
  act_signed_at?: string | null;
  contraente_name?: string | null;
  iban_value_masked?: string | null;
  iban_required_for_progress: boolean;
  document_collection_draft: PortalDocumentCollectionDraftInfo;
  additional_document_requests: string[];
  act_flow?: PortalActFlow | null;
};

export type PortalAccessibleClaim = {
  claim_id: string;
  tenant_id: string;
  external_ref?: string | null;
  numero_sinistro?: string | null;
  compagnia?: string | null;
  nome_assicurato?: string | null;
  data_sinistro?: string | null;
  updated_at?: string | null;
  macro_state: PortalMacroState;
  has_pending_actions: boolean;
  requested_amount?: number | null;
  liquidated_amount?: number | null;
  estimated_damage_amount?: number | null;
};

export type PortalTimelineEvent = {
  id: string;
  event_type: string;
  event_time: string;
  label: string;
  description?: string | null;
  source: string;
};

export type PortalInspectionLocation = {
  address_line?: string | null;
  municipality?: string | null;
  province?: string | null;
  region?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  confirmed_at?: string | null;
};

export type PortalInspectionSelectedSlot = {
  id: string;
  date: string;
  start_at: string;
  end_at: string;
  label: string;
};

export type PortalInspectionAvailabilitySlot = {
  id: string;
  date: string;
  start_at: string;
  end_at: string;
  label: string;
  available_cat_count: number;
  candidate_user_ids: string[];
};

export type PortalInspectionAvailabilityDay = {
  date: string;
  weekday_label: string;
  is_available: boolean;
  slot_count: number;
  slots: PortalInspectionAvailabilitySlot[];
};

export type PortalInspectionCandidate = {
  user_id: string;
  full_name: string;
  email?: string | null;
  phone_number?: string | null;
  job_title?: string | null;
  comune?: string | null;
  provincia?: string | null;
  regione?: string | null;
  distance_km?: number | null;
  is_primary_zone: boolean;
};

export type PortalInspectionSchedulingOverview = {
  enabled: boolean;
  mode: "inspection" | "video_inspection";
  status: string;
  workflow_stage?: string | null;
  instructions: string;
  pending_confirmation_message?: string | null;
  address_confirmed: boolean;
  location: PortalInspectionLocation;
  selected_slots: PortalInspectionSelectedSlot[];
  availability_days: PortalInspectionAvailabilityDay[];
  candidate_cats: PortalInspectionCandidate[];
  route_review_deadline?: string | null;
  route_proposal_event_id?: string | null;
  slot_duration_minutes: number;
  assignment_run_hour: number;
  assigned_expert_name?: string | null;
  assigned_expert_retained: boolean;
  preparation_items: string[];
};

export type PortalDocument = {
  id: string;
  file_name: string;
  category?: string | null;
  status: string;
  uploaded_at: string;
};

export type PortalVideoperiziaSession = {
  id: string;
  claim_id: string;
  livekit_room_name: string;
  state: "scheduled" | "lobby_open" | "live" | "ended" | "aborted";
  lobby_joined_at?: string | null;
  started_at?: string | null;
  ended_at?: string | null;
  perito_user_id?: string | null;
  created_at: string;
  updated_at: string;
};

export type PortalVideoperiziaLocationPing = {
  id: string;
  session_id: string;
  recorded_at: string;
  latitude: number;
  longitude: number;
  accuracy_m?: number | null;
  altitude_m?: number | null;
  speed_mps?: number | null;
  heading_deg?: number | null;
  source: string;
};

export type PortalVideoperiziaToken = {
  token: string;
  livekit_url: string;
  room_name: string;
  identity: string;
  expires_at: string;
  can_publish: boolean;
  can_subscribe: boolean;
  session: PortalVideoperiziaSession;
};

export type PortalUploadIntent = {
  document_id: string;
  upload_mode: string;
  upload_url?: string | null;
  storage_path: string;
  expires_in: number;
};

export type PortalMessage = {
  id: string;
  author_type: string;
  body_text: string;
  created_at: string;
};

export type PortalMessageList = {
  items: PortalMessage[];
  total: number;
};

export type PortalDocumentCollectionSubmission = {
  id: string;
  status: string;
  submitted_at: string;
};

export type PortalDocumentCollectionDraft = {
  status: string;
  draft_json: Record<string, unknown>;
  updated_at?: string | null;
};

export type PortalIbanValidation = {
  is_valid: boolean;
  normalized_iban: string;
  country_code?: string | null;
  check_digits?: string | null;
  cin?: string | null;
  abi?: string | null;
  cab?: string | null;
  account_number?: string | null;
  reason?: string | null;
};

export type PortalBankAccountSubmission = {
  id: string;
  status: string;
  submitted_at: string;
  validation: PortalIbanValidation;
};

export type PortalAdditionalDocumentSubmission = {
  status: string;
  submitted_at: string;
  document_count: number;
};

export type PortalSignatureRequest = {
  id: string;
  status: string;
  challenge_id?: string | null;
  expires_at?: string | null;
  preview_token?: string | null;
};

export type PortalSignatureConfirmation = {
  id: string;
  status: string;
  signed_at?: string | null;
};

// ============================================================================
// Portal Me — sezione "Impostazioni e privacy"
// ============================================================================

export type PortalMeProfile = {
  actor_id: string | null;
  display_name: string;
  actor_type: string | null;
  codice_fiscale_masked: string | null;
  partita_iva_masked: string | null;
  data_nascita: string | null;
  luogo_nascita: string | null;
  email: string | null;
  phone: string | null;
  pec: string | null;
};

export type PortalMeProfileUpdate = {
  email?: string;
  phone?: string;
};

export type PortalMePolicy = {
  id: string;
  version: number;
  title: string | null;
  summary: string | null;
  content_md: string;
  effective_from: string;
};

export type PortalMeConsent = {
  id: string;
  policy_id: string;
  policy_version: number;
  accepted_at: string;
  consent_type: string;
};

export type PortalMeNotificationChannel = "email" | "whatsapp" | "sms" | "push";

export type PortalMeNotificationPrefs = {
  channel_push: boolean;
  channel_email: boolean;
  channel_whatsapp: boolean;
  channel_sms: boolean;
  preferred_channel: PortalMeNotificationChannel;
  allow_phone_calls: boolean;
  call_window_start: string | null;
  call_window_end: string | null;
  quiet_hours_start: string | null;
  quiet_hours_end: string | null;
  documents_via_email: boolean;
  updated_at?: string | null;
};

export type PortalMeDeletionRequest = {
  id: string;
  requested_at: string;
  eligible_from: string;
  status: string;
  reason: string | null;
  processed_at: string | null;
};

export type PortalMeSessionInfo = {
  id: string;
  device_label: string | null;
  ip_address: string | null;
  user_agent: string | null;
  created_at: string;
  last_seen_at: string;
  is_current: boolean;
};
