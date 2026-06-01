import type { PortalClaimSummary } from "@/lib/types";

const DOCUMENT_COLLECTION_STATES = new Set(["SV002", "SV022", "SV023"]);

export function formatDateTime(value: string) {
  return new Date(value).toLocaleString("it-IT", {
    dateStyle: "medium",
    timeStyle: "short"
  });
}

export function formatCurrency(value?: number | null) {
  if (value == null) {
    return "n/d";
  }
  return `${value.toLocaleString("it-IT", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  })} €`;
}

export function formatInspectionDayLabel(date: string) {
  return new Date(`${date}T12:00:00`).toLocaleDateString("it-IT", {
    weekday: "long",
    day: "numeric",
    month: "long"
  });
}

export function isDocumentCollectionMode(summary: PortalClaimSummary | null | undefined) {
  if (!summary) {
    return false;
  }
  return DOCUMENT_COLLECTION_STATES.has(summary.macro_state.internal_state ?? "");
}

export function getDocumentationSummary(summary: PortalClaimSummary | null | undefined) {
  if (!summary) {
    return {
      title: "Documentazione",
      description: "Consulta e carica i documenti del sinistro.",
      emphasis: false
    };
  }

  if (isDocumentCollectionMode(summary)) {
    return {
      title: "Va caricata la documentazione",
      description:
        "Per questo sinistro è attiva la procedura guidata documentale. Apri la sezione e completa tutti i passaggi richiesti.",
      emphasis: true
    };
  }

  if (summary.additional_document_requests.length > 0) {
    return {
      title: "Ci sono documenti richiesti",
      description:
        "Il perito ha richiesto documentazione aggiuntiva. Apri la sezione documentazione per vedere l'elenco e caricare i file.",
      emphasis: true
    };
  }

  return {
    title: "Carica documentazione utile",
    description:
      "Puoi allegare in qualsiasi momento altri documenti, foto o video utili alla gestione del sinistro.",
    emphasis: false
  };
}

export function getIbanSummary(summary: PortalClaimSummary | null | undefined) {
  if (!summary?.iban_value_masked) {
    return {
      title: "IBAN da inserire",
      description:
        "Per proseguire con la perizia e arrivare alla liquidazione servirà l'IBAN intestato al contraente di polizza.",
      emphasis: true
    };
  }

  return {
    title: "IBAN inserito",
    description: `Coordinate registrate: ${summary.iban_value_masked}. Apri la sezione per verificarle o aggiornarle.`,
    emphasis: false
  };
}

export function getInspectionSummary(summary: PortalClaimSummary | null | undefined) {
  if (
    summary?.macro_state.internal_state === "videoperizia"
    || summary?.macro_state.internal_state === "videoperizia_da_eseguire"
  ) {
    return {
      title: "Videoperizia da fissare",
      description: "Scegli una finestra di 30 minuti per la videochiamata con il perito.",
      emphasis: true,
      modeLabel: "Videoperizia"
    };
  }

  if (!summary?.inspection_scheduling_enabled) {
    return {
      title: "Sopralluogo",
      description: "Al momento non ci sono attività di sopralluogo da gestire.",
      emphasis: false,
      modeLabel: "Sopralluogo"
    };
  }

  return {
    title: "Sopralluogo da gestire",
    description:
      "Conferma l'indirizzo e scegli le finestre orarie in cui sei disponibile per il sopralluogo.",
    emphasis: true,
    modeLabel: "Sopralluogo"
  };
}

export function getActSummary(summary: PortalClaimSummary | null | undefined) {
  if (summary?.act_flow?.countersigned_document_id) {
    return {
      title: "Atto controfirmato disponibile",
      description:
        "Il PDF finale è disponibile nel portale. Apri la sezione atto per scaricarlo.",
      emphasis: false
    };
  }

  if (summary?.act_flow?.signing_url) {
    return {
      title: "Atto pronto da firmare",
      description:
        "È disponibile il link alla firma esterna. Apri la sezione atto per completare la sottoscrizione.",
      emphasis: true
    };
  }

  return {
    title: "Atto e firma",
    description:
      "Quando l'atto sarà pronto compariranno qui il link di firma esterna e poi il PDF controfirmato.",
    emphasis: false
  };
}
