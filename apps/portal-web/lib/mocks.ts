import type {
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
  PortalSignatureConfirmation,
  PortalSignatureRequest,
  PortalTimelineEvent,
  PortalUploadIntent
} from "@/lib/types";

export const mockAuthStartResponse: PortalAuthStartResponse = {
  status: "challenge_created",
  challenge_id: "mock-challenge-001",
  delivery_channel: "email",
  masked_destination: "as***@mail.it",
  expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
  preview_magic_link_url: "/access/mock-token"
};

export const mockClaimSummary: PortalClaimSummary = {
  claim_id: "claim-mock-001",
  tenant_id: "tenant-mock",
  external_ref: "PX-2026-00421",
  numero_sinistro: "SIN-884210",
  compagnia: "Compagnia Demo",
  nome_assicurato: "Mario Rossi",
  data_sinistro: "2026-03-27T11:10:00Z",
  macro_state: {
    code: "attention_needed",
    label: "Documentazione richiesta",
    description: "Per proseguire serve la documentazione fotografica e le coordinate bancarie.",
    needs_action: true,
    internal_state: "SV022"
  },
  expert: {
    user_id: "expert-01",
    full_name: "Dott. Luca Bianchi",
    email: "l.bianchi@perx.demo",
    phone_number: "+39 340 555 1122",
    job_title: "Perito incaricato",
    is_available_now: true,
    is_online: false,
    availability_note: "Disponibilita oggi 09:00 - 18:00"
  },
  requirements: [
    {
      key: "documents",
      label: "Documentazione richiesta",
      status: "pending",
      description: "Servono documenti e fotografie del danno."
    },
    {
      key: "iban",
      label: "Coordinate bancarie",
      status: "missing",
      description: "Inserisci l'IBAN per la fase di liquidazione."
    }
  ],
  upcoming_appointment: {
    id: "appt-1",
    title: "Sopralluogo da confermare",
    starts_at: "2026-04-08T09:30:00Z",
    ends_at: "2026-04-08T10:30:00Z",
    location: "Via Roma 10, Milano",
    status: "tentative"
  },
  chat_enabled: true,
  document_upload_enabled: true,
  act_signature_enabled: true,
  inspection_scheduling_enabled: true,
  requested_amount: 5200,
  liquidated_amount: 0,
  estimated_damage_amount: 4100,
  act_sent_at: null,
  act_signed_at: null,
  contraente_name: "Mario Rossi",
  iban_value_masked: null,
  iban_required_for_progress: true,
  document_collection_draft: {
    available: true,
    status: "draft",
    current_step: "item-details",
    updated_at: new Date().toISOString(),
    submitted_at: null
  },
  additional_document_requests: [
    "Carica una foto aggiuntiva della targhetta identificativa",
    "Allega la relazione del tecnico riparatore"
  ],
  act_flow: {
    status: "pending_external_signature",
    label: "Atto pronto da firmare",
    provider: "Provider Demo",
    signing_url: "https://example.com/sign/demo",
    provider_reference: "provider-ref-demo",
    request_id: "act-flow-demo"
  }
};

export const mockAccessibleClaims: PortalAccessibleClaim[] = [
  {
    claim_id: "claim-mock-001",
    tenant_id: "tenant-mock",
    external_ref: "PX-2026-00421",
    numero_sinistro: "SIN-884210",
    compagnia: "Compagnia Demo",
    nome_assicurato: "Mario Rossi",
    data_sinistro: "2026-03-27T11:10:00Z",
    updated_at: "2026-04-08T10:20:00Z",
    macro_state: {
      code: "attention_needed",
      label: "Documentazione richiesta",
      description: "Per proseguire serve la documentazione fotografica e le coordinate bancarie.",
      needs_action: true,
      internal_state: "SV022"
    },
    has_pending_actions: true,
    requested_amount: 5200,
    liquidated_amount: 0,
    estimated_damage_amount: 4100
  },
  {
    claim_id: "claim-mock-002",
    tenant_id: "tenant-mock",
    external_ref: "PX-2026-00117",
    numero_sinistro: "SIN-880112",
    compagnia: "Compagnia Demo",
    nome_assicurato: "Mario Rossi",
    data_sinistro: "2026-02-03T09:30:00Z",
    updated_at: "2026-04-05T15:10:00Z",
    macro_state: {
      code: "settlement",
      label: "Liquidazione in corso",
      description: "La pratica e in fase di definizione economica.",
      needs_action: false,
      internal_state: "SV031"
    },
    has_pending_actions: false,
    requested_amount: 1800,
    liquidated_amount: 1450,
    estimated_damage_amount: 1450
  }
];

export const mockTimeline: PortalTimelineEvent[] = [
  {
    id: "evt-1",
    event_type: "claim_created",
    event_time: "2026-03-27T12:00:00Z",
    label: "Sinistro acquisito",
    description: "Il sinistro e stato registrato nel sistema.",
    source: "system"
  },
  {
    id: "evt-2",
    event_type: "portal_access_issued",
    event_time: "2026-03-27T12:14:00Z",
    label: "Accesso portale attivato",
    description: "E stato generato il link di accesso al portale.",
    source: "portal"
  },
  {
    id: "evt-3",
    event_type: "inspection_scheduling_requested",
    event_time: "2026-03-28T09:10:00Z",
    label: "Richiesta fissazione sopralluogo",
    description: "Conferma il punto di incontro e scegli le finestre preferite.",
    source: "system"
  },
  {
    id: "evt-4",
    event_type: "state_changed",
    event_time: "2026-03-28T09:11:00Z",
    label: "Cambio stato",
    description: "SV002 -> SV022",
    source: "manual"
  }
];

export const mockInspectionSchedulingOverview: PortalInspectionSchedulingOverview = {
  enabled: true,
  mode: "inspection",
  status: "selection_required",
  workflow_stage: "automatic_scheduling_in_progress",
  instructions:
    "Conferma l'indirizzo del sopralluogo, posiziona il pin nel punto di incontro con il tecnico e seleziona una o piu fasce da due ore.",
  pending_confirmation_message: null,
  address_confirmed: false,
  location: {
    address_line: "Via Roma 10, Milano",
    municipality: "Milano",
    province: "MI",
    region: "Lombardia",
    latitude: 45.4642,
    longitude: 9.19,
    confirmed_at: null
  },
  selected_slots: [],
  availability_days: [
    {
      date: "2026-04-09",
      weekday_label: "Thursday",
      is_available: true,
      slot_count: 3,
      slots: [
        {
          id: "slot-1",
          date: "2026-04-09",
          start_at: "2026-04-09T08:00:00Z",
          end_at: "2026-04-09T10:00:00Z",
          label: "10:00 - 12:00",
          available_cat_count: 2,
          candidate_user_ids: ["cat-1", "cat-2"]
        },
        {
          id: "slot-2",
          date: "2026-04-09",
          start_at: "2026-04-09T10:00:00Z",
          end_at: "2026-04-09T12:00:00Z",
          label: "12:00 - 14:00",
          available_cat_count: 2,
          candidate_user_ids: ["cat-1", "cat-2"]
        },
        {
          id: "slot-3",
          date: "2026-04-09",
          start_at: "2026-04-09T13:00:00Z",
          end_at: "2026-04-09T15:00:00Z",
          label: "15:00 - 17:00",
          available_cat_count: 1,
          candidate_user_ids: ["cat-2"]
        }
      ]
    },
    {
      date: "2026-04-10",
      weekday_label: "Friday",
      is_available: false,
      slot_count: 0,
      slots: []
    }
  ],
  candidate_cats: [
    {
      user_id: "cat-1",
      full_name: "CAT Milano Centro",
      email: "cat.milano@demo.it",
      phone_number: "+39 333 1111111",
      job_title: "CAT di zona",
      comune: "Milano",
      provincia: "MI",
      regione: "Lombardia",
      distance_km: null,
      is_primary_zone: true
    },
    {
      user_id: "cat-2",
      full_name: "CAT Milano Ovest",
      email: "cat.ovest@demo.it",
      phone_number: "+39 333 2222222",
      job_title: "CAT di zona",
      comune: "Milano",
      provincia: "MI",
      regione: "Lombardia",
      distance_km: 6.2,
      is_primary_zone: false
    }
  ],
  route_review_deadline: null,
  route_proposal_event_id: null,
  slot_duration_minutes: 120,
  assignment_run_hour: 9,
  assigned_expert_name: null,
  assigned_expert_retained: false,
  preparation_items: []
};

export const mockDocuments: PortalDocument[] = [
  {
    id: "doc-1",
    file_name: "atto-liquidazione.pdf",
    category: "act",
    status: "active",
    uploaded_at: "2026-04-04T10:00:00Z"
  },
  {
    id: "doc-2",
    file_name: "richiesta-documenti.pdf",
    category: "notice",
    status: "active",
    uploaded_at: "2026-03-30T08:30:00Z"
  }
];

export const mockMessages: PortalMessageList = {
  items: [
    {
      id: "msg-1",
      author_type: "portal",
      body_text: "Buongiorno, ho appena caricato le foto.",
      created_at: "2026-04-05T08:30:00Z"
    },
    {
      id: "msg-2",
      author_type: "system",
      body_text: "Il messaggio e stato inoltrato al perito incaricato.",
      created_at: "2026-04-05T08:31:00Z"
    }
  ],
  total: 2
};

export const mockUploadIntent = (fileName: string): PortalUploadIntent => ({
  document_id: "doc-upload-mock",
  upload_mode: "signed-url-pending",
  upload_url: null,
  storage_path: `portal/tenant-mock/claim-mock-001/${fileName}`,
  expires_in: 3600
});

export const mockDocumentCollectionSubmission: PortalDocumentCollectionSubmission = {
  id: "document-collection-mock",
  status: "submitted",
  submitted_at: new Date().toISOString()
};

export const mockDocumentCollectionDraft: PortalDocumentCollectionDraft = {
  status: "draft",
  draft_json: {
    step_kind: "inventory",
    inventory_count: 1,
    notes: "",
    confirmations: {},
    buildingUploads: [],
    repairReceiptUploads: [],
    items: [
      {
        itemType: "",
        brand: "",
        model: "",
        purchaseYear: "",
        purchaseYearApproximate: false,
        damageType: "",
        damageDynamics: "",
        hasDamagedComponents: false,
        damagedComponents: [],
        wholeItemUploads: [],
        optionalVideosUploads: [],
        optionalSupportingDocsUploads: [],
        componentUploads: {}
      }
    ]
  },
  updated_at: new Date().toISOString()
};

export const mockBankSubmission = (iban: string): PortalBankAccountSubmission => ({
  id: "bank-mock",
  status: "valid",
  submitted_at: new Date().toISOString(),
  validation: {
    is_valid: true,
    normalized_iban: iban.replace(/\s+/g, "").toUpperCase(),
    country_code: "IT",
    check_digits: "60",
    cin: "X",
    abi: "05428",
    cab: "11101",
    account_number: "000000123456"
  }
});

export const mockAdditionalDocumentSubmission: PortalAdditionalDocumentSubmission = {
  status: "submitted",
  submitted_at: new Date().toISOString(),
  document_count: 2
};

export const mockSignatureRequest: PortalSignatureRequest = {
  id: "signature-request-mock",
  status: "pending_confirmation",
  challenge_id: "challenge-signature-mock",
  expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
  preview_token: "preview-signature-token"
};

export const mockSignatureConfirmation: PortalSignatureConfirmation = {
  id: "signature-request-mock",
  status: "signed",
  signed_at: new Date().toISOString()
};
