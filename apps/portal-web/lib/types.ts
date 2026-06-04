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

export interface PortalClaimSummary {
  claim_id: string;
  reference?: string;
  compagnia?: string;
  nome_assicurato?: string;
  data_sinistro?: string;
  expert: PortalExpert;
  macro_state: PortalMacroState;
  requirements: PortalRequirement[];
  chat_enabled?: boolean;
  requested_amount?: number;
  estimated_damage_amount?: number;
  liquidated_amount?: number;
  iban_value_masked?: string;
  iban_status?: string;
  documentation_uploaded?: number;
  documentation_required?: number;
  inspection_mode?: "fieldwork" | "desktop" | "video";
  inspection_status?: string;
  inspection_scheduled_at?: string;
  act_status?: string;
  act_signed_at?: string;
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
  category?: string;
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
  sender?: string;
  read?: boolean;
}

export interface PortalInspectionSchedulingOverview {
  status?: string;
  scheduled_at?: string;
  address?: string;
  inspector_name?: string;
  available_slots?: Array<{ slot_id: string; datetime: string }>;
}
