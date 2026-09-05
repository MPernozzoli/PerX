export interface PortalSession {
  token: string;
  claimId: string;
  portalAccessId: string;
  expiresAt: string;
}

export interface PortalAuthStartResponse {
  status: string;
  challenge_id?: string;
  delivery_channel?: string;
  masked_destination?: string;
  expires_at?: string;
  preview_magic_link_url?: string;
}

export interface PortalAuthRequestOtpResponse {
  status: string;
  challenge_id?: string;
  delivery_channel?: string;
  masked_destination?: string;
  expires_at?: string;
  preview_otp_code?: string;
}

export interface PortalMacroState {
  code: string;
  label: string;
  description: string;
  needs_action: boolean;
  internal_state?: string;
}

export interface PortalExpert {
  user_id?: string;
  full_name?: string;
  email?: string;
  phone_number?: string;
  job_title?: string;
  is_available_now: boolean;
  is_online: boolean;
  availability_note?: string;
}

export interface PortalRequirement {
  key: string;
  label: string;
  status: string;
  description: string;
}

export interface PortalAppointment {
  id: string;
  title: string;
  starts_at: string;
  ends_at: string;
  location?: string;
  status: string;
}

export interface PortalDocumentCollectionDraftInfo {
  available: boolean;
  status: string;
  current_step?: string;
  updated_at?: string;
  submitted_at?: string;
}

export interface PortalActFlow {
  status: string;
  label: string;
  provider?: string;
  signing_url?: string;
  provider_reference?: string;
  request_id?: string;
  act_document_id?: string;
  signed_document_id?: string;
  countersigned_document_id?: string;
  signed_at?: string;
  countersigned_at?: string;
}

export interface PortalAccessibleClaim {
  claim_id: string;
  tenant_id: string;
  external_ref?: string;
  numero_sinistro?: string;
  compagnia?: string;
  nome_assicurato?: string;
  data_sinistro?: string;
  updated_at?: string;
  macro_state: PortalMacroState;
  has_pending_actions: boolean;
  requested_amount?: number;
  liquidated_amount?: number;
  estimated_damage_amount?: number;
}

export interface PortalClaimSummary {
  claim_id: string;
  tenant_id: string;
  external_ref?: string;
  numero_sinistro?: string;
  compagnia?: string;
  nome_assicurato?: string;
  data_sinistro?: string;
  macro_state: PortalMacroState;
  expert: PortalExpert;
  requirements: PortalRequirement[];
  upcoming_appointment?: PortalAppointment;
  chat_enabled: boolean;
  document_upload_enabled: boolean;
  act_signature_enabled: boolean;
  inspection_scheduling_enabled: boolean;
  requested_amount?: number;
  liquidated_amount?: number;
  estimated_damage_amount?: number;
  act_sent_at?: string;
  act_signed_at?: string;
  contraente_name?: string;
  iban_value_masked?: string;
  iban_required_for_progress: boolean;
  document_collection_draft: PortalDocumentCollectionDraftInfo;
  additional_document_requests: string[];
  act_flow?: PortalActFlow;
}

export interface PortalTimelineEvent {
  id: string;
  event_type: string;
  event_time: string;
  label: string;
  description?: string;
  source: string;
}

export interface PortalDocument {
  id: string;
  file_name: string;
  category?: string;
  status: string;
  uploaded_at: string;
}

export interface PortalMessage {
  id: string;
  author_type: string;
  body_text: string;
  created_at: string;
}

export interface PortalMessageList {
  items: PortalMessage[];
  total: number;
}

export interface PortalInspectionLocation {
  address_line?: string;
  municipality?: string;
  province?: string;
  region?: string;
  latitude?: number;
  longitude?: number;
  confirmed_at?: string;
}

export interface PortalInspectionSlot {
  id: string;
  date: string;
  start_at: string;
  end_at: string;
  label: string;
}

export interface PortalInspectionAvailabilitySlot extends PortalInspectionSlot {
  available_cat_count: number;
  candidate_user_ids: string[];
}

export interface PortalInspectionAvailabilityDay {
  date: string;
  weekday_label: string;
  is_available: boolean;
  slot_count: number;
  slots: PortalInspectionAvailabilitySlot[];
}

export interface PortalInspectionCandidateCat {
  user_id: string;
  full_name: string;
  email?: string;
  phone_number?: string;
  job_title?: string;
  comune?: string;
  provincia?: string;
  regione?: string;
  distance_km?: number;
  is_primary_zone: boolean;
}

export interface PortalInspectionSchedulingOverview {
  enabled: boolean;
  mode: string;
  status: string;
  workflow_stage?: string;
  instructions: string;
  pending_confirmation_message?: string;
  address_confirmed: boolean;
  location: PortalInspectionLocation;
  selected_slots: PortalInspectionSlot[];
  availability_days: PortalInspectionAvailabilityDay[];
  candidate_cats: PortalInspectionCandidateCat[];
  route_review_deadline?: string;
  route_proposal_event_id?: string;
  slot_duration_minutes: number;
  assignment_run_hour: number;
  assigned_expert_name?: string;
  assigned_expert_retained: boolean;
  preparation_items: string[];
}

export interface PortalBankAccountValidation {
  is_valid: boolean;
  normalized_iban: string;
  country_code?: string;
  check_digits?: string;
  cin?: string;
  abi?: string;
  cab?: string;
  account_number?: string;
  reason?: string;
}

export interface PortalBankAccountSubmission {
  id: string;
  status: string;
  submitted_at: string;
  validation: PortalBankAccountValidation;
}

export interface PortalMeDeletionRequest {
  id: string;
  status: "pending" | "confirmed" | "cancelled";
  requested_at: string;
  eligible_from: string;
  scheduled_deletion_at?: string;
  reason?: string;
  processed_at?: string;
}

export type PortalMeNotificationChannel = "email" | "whatsapp" | "sms" | "push";

export interface PortalMeNotificationPrefs {
  channel_email: boolean;
  channel_whatsapp: boolean;
  channel_sms: boolean;
  channel_push: boolean;
  preferred_channel: PortalMeNotificationChannel;
  allow_phone_calls: boolean;
  call_window_start?: string | null;
  call_window_end?: string | null;
  quiet_hours_start?: string | null;
  quiet_hours_end?: string | null;
  documents_via_email: boolean;
  updated_at?: string;
}

export interface PortalMePolicy {
  id: string;
  version: number;
  title?: string;
  summary?: string;
  content_md: string;
  effective_from: string;
}

export interface PortalMeProfile {
  actor_id?: string;
  display_name: string;
  actor_type?: string;
  codice_fiscale_masked?: string;
  partita_iva_masked?: string;
  data_nascita?: string;
  luogo_nascita?: string;
  email?: string;
  phone?: string;
  pec?: string;
}

export interface PortalMeSessionInfo {
  id: string;
  device_label?: string;
  ip_address?: string;
  user_agent?: string;
  created_at: string;
  last_seen_at: string;
  is_current: boolean;
}

export interface PortalVideoperiziaSession {
  id: string;
  claim_id: string;
  livekit_room_name: string;
  state: "scheduled" | "lobby_open" | "live" | "ended" | "aborted";
  lobby_joined_at?: string;
  started_at?: string;
  ended_at?: string;
  perito_user_id?: string;
  insured_disconnected_at?: string;
  created_at: string;
  updated_at: string;
}

export interface PortalVideoperiziaToken {
  token: string;
  livekit_url: string;
  room_name: string;
  identity: string;
  expires_at: string;
  can_publish: boolean;
  can_subscribe: boolean;
  session: PortalVideoperiziaSession;
}
