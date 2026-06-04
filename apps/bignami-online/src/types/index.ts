// Bignami Online - Type definitions

export interface User {
  id: string;
  name: string;
  email: string;
  auth_provider: string;
  created_at: string;
}

export interface Studio {
  id: string;
  name: string;
  description: string;
  created_at: string;
}

export interface StudioMember {
  id: string;
  studio_id: string;
  user_id: string;
  role: 'admin' | 'member';
}

export interface Company {
  id: string;
  name: string;
  code: string;
  aliases: string[];
}

export type PolicyType = 'domestica' | 'azienda' | 'agricola';
export type GuaranteeType = string;

export interface Policy {
  id: string;
  company_id: string;
  name: string;
  code: string;
  type: PolicyType;
  description: string;
  tags: string[];
  default_guarantee: GuaranteeType;
  created_at: string;
  company?: Company;
}

export type PolicyStatus = 'draft' | 'published';

export interface PolicyEdition {
  id: string;
  policy_id: string;
  year: number;
  code: string;
  edition_label?: string;
  pdf_url?: string;
  pdf_sha256?: string;
  status: PolicyStatus;
  canonical_group_id?: string;
  policy?: Policy;
}

export interface Coverage {
  id: string;
  policy_edition_id: string;
  guarantee: GuaranteeType;
  overview_text: string;
  definitions: string[];
  common_exclusions: string[];
  common_interpretations: string[];
  common_notes: string[];
  value_type?: ValueType;
  primo_rischio_value?: string;
  page_reference?: string;
  article_number?: string;
}

export type PartyType = 'fabbricato' | 'contenuto' | 'impianti' | 'macchinari' | 'elettronica' | 'altro';
export type InsuranceValueType = 'exact' | 'frontespizio' | 'comune_a_piu_partite' | 'coincide_valore_assicurato';
export type ValueType = 'valore_intero' | 'primo_rischio_assoluto' | 'primo_rischio_assoluto_fino_a';

export interface Section {
  id: string;
  coverage_id: string;
  party: PartyType;
  exact_name?: string;
  definition: string;
  exclusions?: string[]; // Esclusioni comuni della partita
  notes: string[];
  links_to_common_limits: string[];
  value_type?: ValueType;
  primo_rischio_value?: string;
  page_reference?: string;
  article_number?: string;
  definition_page_reference?: string;
  definition_article_number?: string;
  deroga_percentage?: number;
  determinazione?: string[]; // "Valore a Nuovo", "Valore Reale", or empty
  emoji?: string;
}

export interface CoverageItem {
  id: string;    
  coverage_id: string;
  guarantee_name: string;
  exact_name?: string;
  guarantee_group: string;
  order_index: number;
  // New fields for guarantee details
  description?: string;
  value_type?: ValueType;
  primo_rischio_value?: string;
  common_exclusions?: string[]; // Esclusioni comuni della garanzia
  available_parties?: string[]; // IDs delle partite per cui la garanzia è disponibile
  // Legacy fields (kept for backward compatibility)
  maximum_value?: string;
  maximum_page_reference?: string;
  maximum_article_number?: string;
  maximum_applies_to?: string[]; 
  deductible_value?: string;
  deductible_page_reference?: string;
  deductible_article_number?: string;
  deductible_applies_to?: string[]; 
  guarantee_exclusions?: string[]; 
  exclusions_page_reference?: string;
  exclusions_article_number?: string;
  exclusions_apply_to?: string[]; 
  created_at: string;
  // New relations for multiple conditions
  guarantee_maximums?: GuaranteeMaximum[];
  guarantee_deductibles?: GuaranteeDeductible[];
  guarantee_exclusion_groups?: GuaranteeExclusionGroup[];
}

export interface GuaranteeMaximum {
  id: string;
  coverage_item_id: string;
  on_frontespizio: boolean;
  exact_value?: string;
  percentage_of_party?: string;
  minimum_value?: string;
  maximum_value?: string;
  notes?: string;
  page_reference?: string;
  article_number?: string;
  applies_to?: string[]; // Array of section IDs
  created_at: string;
  order_index: number;
}

export interface GuaranteeDeductible {
  id: string;
  coverage_item_id: string;
  exact_value?: string;
  on_frontespizio: boolean;
  percentage?: string;
  minimum_value?: string;
  maximum_value?: string;
  notes?: string;
  page_reference?: string;
  article_number?: string;
  applies_to?: string[]; // Array of section IDs
  created_at: string;
  order_index: number;
}

export interface GuaranteeExclusionGroup {
  id: string;
  coverage_item_id: string;
  exclusions: string[]; // Array of exclusion texts
  page_reference?: string;
  article_number?: string;
  applies_to?: string[]; // Array of section IDs
  created_at: string;
  order_index: number;
}

export interface GuaranteeDamageDefinition {
  id: string;
  coverage_item_id: string;
  definition_type: 'a_nuovo' | 'vsu_si' | 'massimo_doppio' | 'massimo_triplo' | 'valore_stato_uso';
  notes?: string;
  page_reference?: string;
  article_number?: string;
  applies_to?: string[]; // Array of section IDs
  created_at: string;
  order_index: number;
}

export interface CommonLimit {
  id: string;
  coverage_id: string;
  label: string;
  scope: string;
  value: string;
  on_frontespizio: boolean;
  page_reference?: string;
  article_number?: string;
}

export type EditStatus = 'pending' | 'approved' | 'rejected';
export type EditTargetType = 'policy' | 'policy_edition' | 'coverage' | 'section' | 'common_limit' | 'norm_ref' | 'studio_template';
export type Visibility = 'global' | 'studio';

export interface EditHistory {
  id: string;
  target_type: EditTargetType;
  target_id: string;
  user_id: string;
  change_summary: string;
  diff: any;
  created_at: string;
  status: EditStatus;
  visibility: Visibility;
}

export type CommentVisibility = 'public' | 'studio';
export type CommentTargetType = 'policy' | 'policy_edition' | 'coverage' | 'section' | 'norm_ref';

export interface Comment {
  id: string;
  target_type: CommentTargetType;
  target_id: string;
  user_id: string;
  visibility: CommentVisibility;
  body: string;
  created_at: string;
  parent_comment_id?: string;
  resolved: boolean;
}

export interface NormRef {
  id: string;
  code: string;
  article: string;
  comma?: string;
  text: string;
  summary: string;
  tags: string[];
  links: string[];
  last_update: string;
}

export type TemplateKind = 'email' | 'whatsapp' | 'relazione' | 'altro';

export interface StudioTemplate {
  id: string;
  studio_id: string;
  kind: TemplateKind;
  title: string;
  body_template: string;
  tags: string[];
  updated_at: string;
}

// Search and UI types
export interface SearchQuery {
  query: string;
  company?: string;
  policy?: string;
  year?: number;
  yearRange?: [number, number];
  type?: PolicyType;
  guarantee?: GuaranteeType;
}

export interface SearchResult {
  policies: PolicyWithEditions[];
  totalCount: number;
}

export interface PolicyWithEditions extends Policy {
  editions: PolicyEdition[];
  latestEdition?: PolicyEdition;
}

// Recent/Frequent/Bookmarked
export interface UserPolicyInteraction {
  policy_id: string;
  policy_edition_id: string;
  last_viewed: string;
  view_count: number;
  bookmarked: boolean;
}