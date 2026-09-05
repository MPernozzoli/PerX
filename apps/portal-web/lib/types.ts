export interface PortalSession {
  claimId: string;
  token: string;
  expiresAt?: string;
}

export interface PortalAuthStartResponse {
  status: string;
  masked_destination?: string;
  preview_magic_link_url?: string;
}

export interface PortalAccessibleClaim {
  claim_id: string;
  reference: string;
  description?: string;
  status?: string;
}

export interface PortalExpert {
  full_name?: string;
  job_title?: string;
  email?: string;
  phone_number?: string;
  is_available_now?: boolean;
  availability_note?: string;
}

export interface PortalMacroState {
  label: string;
  description: string;
  internal_state: string;
}

export interface PortalRequirement {
  key: string;
  label: string;
  description: string;
}

export interface PortalActFlow {
  label: string;
  provider?: string;
  signed_at?: string;
  countersigned_at?: string;
  signing_url?: string;
  countersigned_document_id?: string;
}

export interface PortalAdditionalDocumentRequest {
  id?: string;
  label?: string;
  description?: string;
  category?: string;
  [key: string]: unknown;
}

export interface PortalClaimSummary {
  claim_id: string;
  reference?: string;
  external_ref?: string;
  numero_sinistro?: string;
  compagnia?: string;
  nome_assicurato?: string;
  contraente_name?: string;
  data_sinistro?: string;
  expert: PortalExpert;
  macro_state: PortalMacroState;
  requirements: PortalRequirement[];
  additional_document_requests: string[];
  chat_enabled?: boolean;
  requested_amount?: number;
  estimated_damage_amount?: number;
  liquidated_amount?: number;
  iban_value_masked?: string;
  iban_status?: string;
  documentation_uploaded?: number;
  documentation_required?: number;
  documentation_mode?: "collection" | "additional";
  inspection_mode?: "fieldwork" | "desktop" | "video";
  inspection_status?: string;
  inspection_scheduled_at?: string;
  inspection_scheduling_enabled?: boolean;
  act_status?: string;
  act_sent_at?: string;
  act_signed_at?: string;
  act_flow?: PortalActFlow;
}

export interface PortalTimelineEvent {
  id: string;
  label: string;
  event_time: string;
  description?: string;
}

export interface PortalDocument {
  id: string;
  name: string;
  file_name: string;
  category?: string;
  status?: string;
  uploaded_at?: string;
  url?: string;
  required?: boolean;
  uploaded?: boolean;
}

export interface PortalMessageList {
  items: PortalMessage[];
  total?: number;
}

export interface PortalMessage {
  id: string;
  created_at: string;
  body: string;
  body_text?: string;
  author_type?: string;
  sender?: string;
  read?: boolean;
}

export interface PortalInspectionSlot {
  slot_id?: string;
  date: string;
  label: string;
  start_at?: string;
  end_at?: string;
}

export interface PortalInspectionAvailabilityDay {
  date: string;
  label: string;
  slots: PortalInspectionSlot[];
}

export interface PortalInspectionLocation {
  confirmed_at?: string;
  address_line?: string;
  latitude?: number;
  longitude?: number;
  municipality?: string;
  province?: string;
  region?: string;
}

export interface PortalInspectionCandidateCat {
  id?: string;
  name?: string;
  [key: string]: unknown;
}

export interface PortalInspectionSchedulingOverview {
  enabled?: boolean;
  preparation_items: string[];
  address_confirmed?: boolean;
  instructions?: string;
  pending_confirmation_message?: string;
  route_review_deadline?: string;
  availability_days: PortalInspectionAvailabilityDay[];
  selected_slots: PortalInspectionSlot[];
  candidate_cats: PortalInspectionCandidateCat[];
  location: PortalInspectionLocation;
  status?: string;
  scheduled_at?: string;
  inspector_name?: string;
}

export interface PortalBankAccountValidation {
  is_valid: boolean;
  normalized_iban: string;
  abi?: string;
  cab?: string;
}

export interface PortalBankAccountSubmission {
  iban: string;
  status: string;
  submitted_at?: string;
  verified_at?: string;
  masked_iban?: string;
  validation: PortalBankAccountValidation;
}

export interface PortalMeDeletionRequest {
  id: string;
  status: "pending" | "confirmed" | "cancelled";
  requested_at: string;
  scheduled_deletion_at?: string;
  reason?: string;
}

export type PortalMeNotificationChannel = "email" | "sms" | "push";

export interface PortalMeNotificationPrefs {
  channels: PortalMeNotificationChannel[];
  claim_updates?: boolean;
  inspection_reminders?: boolean;
  document_requests?: boolean;
  messages?: boolean;
}

export interface PortalMePolicy {
  id?: string;
  version?: number;
  title?: string;
  summary?: string;
  content_md?: string;
  effective_from?: string;
  policy_number?: string;
  product_name?: string;
  company?: string;
  start_date?: string;
  end_date?: string;
  insured_name?: string;
  coverage_summary?: string;
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
  session_id: string;
  created_at: string;
  last_seen_at?: string;
  user_agent?: string;
  device_label?: string;
  ip_address?: string;
  is_current?: boolean;
}

export interface PortalVideoperiziaSession {
  session_id: string;
  state: "scheduled" | "lobby_open" | "live" | "ended" | "aborted";
  scheduled_at?: string;
  started_at?: string;
  ended_at?: string;
  room_name?: string;
}

export interface PortalVideoperiziaToken {
  token: string;
  room_name: string;
  server_url?: string;
  livekit_url?: string;
  can_publish?: boolean;
}
