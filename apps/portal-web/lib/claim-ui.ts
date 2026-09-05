import type { PortalClaimSummary, PortalInspectionSchedulingOverview } from "./types";

export function formatCurrency(value: number | null | undefined): string {
  if (value == null) return "n/d";
  return new Intl.NumberFormat("it-IT", {
    style: "currency",
    currency: "EUR",
    maximumFractionDigits: 2,
  }).format(value);
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "n/d";
  try {
    return new Intl.DateTimeFormat("it-IT", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(value));
  } catch {
    return value;
  }
}

export interface ClaimSectionSummary {
  title: string;
  description: string;
  emphasis: boolean;
}

export interface InspectionSectionSummary extends ClaimSectionSummary {
  modeLabel: string;
}

/** The guided document-collection wizard is the primary flow while the claim
 * is waiting on the insured for documentation; once submitted (or outside
 * that state) the portal switches to the ad-hoc "additional documents"
 * uploader instead. */
export function isDocumentCollectionMode(summary: PortalClaimSummary | null): boolean {
  if (!summary) return false;
  return (
    summary.macro_state.code === "attention_needed" &&
    summary.document_collection_draft.status !== "submitted"
  );
}

export function getDocumentationSummary(
  summary: PortalClaimSummary | null,
): ClaimSectionSummary {
  if (!summary) {
    return { title: "Documentazione", description: "Caricamento in corso...", emphasis: false };
  }

  const pendingRequests = summary.additional_document_requests.length;
  if (pendingRequests > 0) {
    return {
      title: `${pendingRequests} document${pendingRequests === 1 ? "o" : "i"} richiesto${pendingRequests === 1 ? "" : "i"}`,
      description: "Il perito ha richiesto documentazione aggiuntiva.",
      emphasis: true,
    };
  }

  const draftStatus = summary.document_collection_draft.status;
  if (draftStatus === "submitted") {
    return {
      title: "Documentazione completa",
      description: "La documentazione richiesta è stata inviata.",
      emphasis: false,
    };
  }
  if (draftStatus === "draft") {
    return {
      title: "Documentazione in bozza",
      description: "Hai una procedura guidata in corso: riprendila per completarla.",
      emphasis: true,
    };
  }
  if (isDocumentCollectionMode(summary)) {
    return {
      title: "Documentazione da inviare",
      description: "Avvia la procedura guidata per caricare foto e documenti del sinistro.",
      emphasis: true,
    };
  }
  return {
    title: "Nessun documento richiesto",
    description: "Puoi comunque allegare in ogni momento file utili alla pratica.",
    emphasis: false,
  };
}

export function getIbanSummary(summary: PortalClaimSummary | null): ClaimSectionSummary {
  if (!summary) {
    return { title: "IBAN", description: "Caricamento in corso...", emphasis: false };
  }
  if (!summary.iban_value_masked) {
    return {
      title: "IBAN non inserito",
      description: "Inserisci il tuo IBAN per ricevere il pagamento della liquidazione.",
      emphasis: summary.iban_required_for_progress,
    };
  }
  return {
    title: "IBAN registrato",
    description: `L'IBAN ${summary.iban_value_masked} è registrato sulla pratica.`,
    emphasis: false,
  };
}

const INSPECTION_MODE_LABELS: Record<string, string> = {
  inspection: "Sopralluogo",
  video_inspection: "Videoperizia",
};

const INSPECTION_STATUS_LABELS: Record<string, { title: string; description: string; emphasis: boolean }> = {
  selection_required: {
    title: "Da programmare",
    description: "Conferma posizione e finestra oraria per procedere.",
    emphasis: true,
  },
  manual_coordination: {
    title: "In accordo diretto",
    description: "Il sopralluogo verrà concordato direttamente con il CAT incaricato.",
    emphasis: false,
  },
  pending_confirmation: {
    title: "In attesa di conferma",
    description: "Le tue preferenze sono state inoltrate al sistema appuntamenti.",
    emphasis: false,
  },
  confirmed: {
    title: "Confermato",
    description: "L'appuntamento risulta confermato.",
    emphasis: false,
  },
};

export function getInspectionSummary(
  overview: PortalInspectionSchedulingOverview | null,
): InspectionSectionSummary {
  const modeLabel = (overview?.mode && INSPECTION_MODE_LABELS[overview.mode]) ?? "Sopralluogo";

  if (!overview) {
    return { title: modeLabel, description: "Caricamento in corso...", emphasis: false, modeLabel };
  }
  if (!overview.enabled) {
    return {
      title: "Nessuna attività da gestire",
      description: "Al momento non ci sono attività di sopralluogo per questo sinistro.",
      emphasis: false,
      modeLabel,
    };
  }
  const known = INSPECTION_STATUS_LABELS[overview.status];
  if (known) {
    return { ...known, modeLabel };
  }
  return { title: modeLabel, description: overview.status, emphasis: false, modeLabel };
}

export function formatInspectionDayLabel(isoDate: string): string {
  try {
    return new Intl.DateTimeFormat("it-IT", {
      weekday: "long",
      day: "numeric",
      month: "long",
    }).format(new Date(isoDate));
  } catch {
    return isoDate;
  }
}

export function getActSummary(summary: PortalClaimSummary | null): ClaimSectionSummary {
  if (!summary) {
    return { title: "Atto", description: "Caricamento in corso...", emphasis: false };
  }
  const status = summary.act_flow?.status;
  if (!status) {
    return {
      title: "Atto non disponibile",
      description: "L'atto di liquidazione non è ancora disponibile per la firma.",
      emphasis: false,
    };
  }
  if (summary.act_signed_at) {
    return {
      title: "Atto firmato",
      description: `L'atto è stato firmato il ${formatDateTime(summary.act_signed_at)}.`,
      emphasis: false,
    };
  }
  if (summary.act_sent_at) {
    return {
      title: "Atto pronto per la firma",
      description: "L'atto di liquidazione è disponibile. Firmalo per procedere.",
      emphasis: true,
    };
  }
  return {
    title: summary.act_flow?.label ?? "Atto",
    description: status,
    emphasis: false,
  };
}
