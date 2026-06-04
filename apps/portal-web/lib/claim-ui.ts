import type { PortalClaimSummary } from "./types";

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

export function getDocumentationSummary(
  summary: PortalClaimSummary | null,
): ClaimSectionSummary {
  if (!summary) {
    return { title: "Documentazione", description: "Caricamento in corso...", emphasis: false };
  }
  const required = summary.documentation_required ?? 0;
  const uploaded = summary.documentation_uploaded ?? 0;
  const pending = required - uploaded;
  if (pending > 0) {
    return {
      title: `${pending} document${pending === 1 ? "o" : "i"} richiesto${pending === 1 ? "" : "i"}`,
      description: `Hai caricato ${uploaded} di ${required} documenti richiesti.`,
      emphasis: true,
    };
  }
  if (required > 0) {
    return {
      title: "Documentazione completa",
      description: `Tutti i ${required} documenti richiesti sono stati caricati.`,
      emphasis: false,
    };
  }
  return {
    title: "Nessun documento richiesto",
    description: "Non ci sono documenti da caricare per questa pratica.",
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
      emphasis: true,
    };
  }
  if (summary.iban_status === "verified") {
    return {
      title: "IBAN verificato",
      description: `L'IBAN ${summary.iban_value_masked} è stato verificato con successo.`,
      emphasis: false,
    };
  }
  return {
    title: "IBAN in verifica",
    description: `Il tuo IBAN ${summary.iban_value_masked} è in fase di verifica.`,
    emphasis: false,
  };
}

const INSPECTION_MODE_LABELS: Record<string, string> = {
  fieldwork: "Sopralluogo",
  desktop: "Perizia desktop",
  video: "Videoperizia",
};

export function getInspectionSummary(
  summary: PortalClaimSummary | null,
): InspectionSectionSummary {
  const modeLabel =
    (summary?.inspection_mode && INSPECTION_MODE_LABELS[summary.inspection_mode]) ??
    "Sopralluogo";

  if (!summary) {
    return {
      title: modeLabel,
      description: "Caricamento in corso...",
      emphasis: false,
      modeLabel,
    };
  }
  const status = summary.inspection_status;
  if (!status || status === "pending") {
    return {
      title: "In attesa di programmazione",
      description: `Il ${modeLabel.toLowerCase()} non è ancora stato programmato.`,
      emphasis: false,
      modeLabel,
    };
  }
  if (status === "scheduled") {
    const when = summary.inspection_scheduled_at
      ? ` per il ${formatDateTime(summary.inspection_scheduled_at)}`
      : "";
    return {
      title: `${modeLabel} programmato`,
      description: `Appuntamento confermato${when}.`,
      emphasis: true,
      modeLabel,
    };
  }
  if (status === "completed") {
    return {
      title: `${modeLabel} completato`,
      description: "Il sopralluogo è stato effettuato.",
      emphasis: false,
      modeLabel,
    };
  }
  return {
    title: modeLabel,
    description: status,
    emphasis: false,
    modeLabel,
  };
}

export function isDocumentCollectionMode(summary: PortalClaimSummary | null): boolean {
  return summary?.documentation_mode === "collection";
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
  const status = summary.act_status;
  if (!status || status === "not_ready") {
    return {
      title: "Atto non disponibile",
      description: "L'atto di liquidazione non è ancora disponibile per la firma.",
      emphasis: false,
    };
  }
  if (status === "ready") {
    return {
      title: "Atto pronto per la firma",
      description: "L'atto di liquidazione è disponibile. Firmalo per procedere.",
      emphasis: true,
    };
  }
  if (status === "signed") {
    const when = summary.act_signed_at ? ` il ${formatDateTime(summary.act_signed_at)}` : "";
    return {
      title: "Atto firmato",
      description: `L'atto è stato firmato${when}.`,
      emphasis: false,
    };
  }
  return {
    title: "Atto",
    description: status,
    emphasis: false,
  };
}
