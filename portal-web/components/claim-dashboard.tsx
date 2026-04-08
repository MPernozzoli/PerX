"use client";

import Link from "next/link";
import { startTransition, useEffect, useState } from "react";

import { ClaimProgress } from "@/components/claim-progress";
import { DocumentCollectionWizard } from "@/components/document-collection-wizard";
import { MapPinEditor } from "@/components/map-pin-editor";
import { SectionCard } from "@/components/section-card";
import {
  createPortalMessage,
  createUploadIntent,
  downloadPortalDocument,
  getInspectionSchedulingOverview,
  getPortalClaimSummaryForClaim,
  getPortalDocuments,
  getPortalTimeline,
  listAccessibleClaims,
  listPortalMessages,
  submitAdditionalDocuments,
  submitBankAccount,
  submitInspectionPreferences,
  uploadPortalDocumentFile,
  updateInspectionLocation
} from "@/lib/api";
import { clearStoredPortalSession, getStoredPortalSession } from "@/lib/session";
import type {
  PortalAccessibleClaim,
  PortalBankAccountSubmission,
  PortalClaimSummary,
  PortalDocument,
  PortalInspectionSchedulingOverview,
  PortalMessage,
  PortalSession,
  PortalTimelineEvent,
  PortalUploadIntent
} from "@/lib/types";

type AdditionalUploadDraft = {
  documentId: string;
  fileName: string;
};

type InspectionSlotDraft = {
  key: string;
  date: string;
  label: string;
  startTime: string;
  endTime: string;
};

function buildInspectionSlotKey(date: string, label: string) {
  return `${date}::${label}`;
}

function formatDateTime(value: string) {
  return new Date(value).toLocaleString("it-IT", {
    dateStyle: "medium",
    timeStyle: "short"
  });
}

function formatCurrency(value?: number | null) {
  if (value == null) {
    return "n/d";
  }
  return `${value.toLocaleString("it-IT", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  })} €`;
}

function formatInspectionDayLabel(date: string) {
  return new Date(`${date}T12:00:00`).toLocaleDateString("it-IT", {
    weekday: "long",
    day: "numeric",
    month: "long"
  });
}

function timeLabelFromIso(value: string) {
  return new Date(value).toLocaleTimeString("it-IT", {
    hour: "2-digit",
    minute: "2-digit"
  });
}

function splitTimeRange(
  label: string,
  fallbackStart?: string,
  fallbackEnd?: string
): { startTime: string; endTime: string } {
  const parts = label
    .split(" - ")
    .map((part) => part.trim())
    .filter(Boolean);
  if (parts.length === 2) {
    return {
      startTime: parts[0],
      endTime: parts[1]
    };
  }

  return {
    startTime: fallbackStart ? timeLabelFromIso(fallbackStart) : "09:00",
    endTime: fallbackEnd ? timeLabelFromIso(fallbackEnd) : "11:00"
  };
}

function resolveSelectedInspectionSlots(
  overview: PortalInspectionSchedulingOverview | null,
  selectedKeys: string[]
): InspectionSlotDraft[] {
  if (!overview || selectedKeys.length === 0) {
    return [];
  }

  const lookup = new Map<string, InspectionSlotDraft>();

  for (const day of overview.availability_days) {
    for (const slot of day.slots) {
      const key = buildInspectionSlotKey(slot.date, slot.label);
      const timeRange = splitTimeRange(slot.label, slot.start_at, slot.end_at);
      lookup.set(key, {
        key,
        date: slot.date,
        label: slot.label,
        startTime: timeRange.startTime,
        endTime: timeRange.endTime
      });
    }
  }

  for (const slot of overview.selected_slots) {
    const key = buildInspectionSlotKey(slot.date, slot.label);
    const timeRange = splitTimeRange(slot.label, slot.start_at, slot.end_at);
    lookup.set(key, {
      key,
      date: slot.date,
      label: slot.label,
      startTime: timeRange.startTime,
      endTime: timeRange.endTime
    });
  }

  return selectedKeys
    .map((key) => lookup.get(key))
    .filter((value): value is InspectionSlotDraft => Boolean(value))
    .sort((left, right) => {
      if (left.date === right.date) {
        return left.startTime.localeCompare(right.startTime);
      }
      return left.date.localeCompare(right.date);
    });
}

function formatCoordinateInput(value: number | null | undefined) {
  return typeof value === "number" ? value.toFixed(6) : "";
}

function parseCoordinateInput(value: string) {
  const normalized = value.replace(",", ".").trim();
  if (!normalized) {
    return undefined;
  }
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export function ClaimDashboard() {
  const [session, setSession] = useState<PortalSession | null>(null);
  const [accessibleClaims, setAccessibleClaims] = useState<PortalAccessibleClaim[]>([]);
  const [summary, setSummary] = useState<PortalClaimSummary | null>(null);
  const [timeline, setTimeline] = useState<PortalTimelineEvent[]>([]);
  const [documents, setDocuments] = useState<PortalDocument[]>([]);
  const [messages, setMessages] = useState<PortalMessage[]>([]);
  const [inspectionOverview, setInspectionOverview] =
    useState<PortalInspectionSchedulingOverview | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [uploadFileName, setUploadFileName] = useState("");
  const [uploadIntent, setUploadIntent] = useState<PortalUploadIntent | null>(null);

  const [documentaleResult, setDocumentaleResult] = useState<string | null>(null);

  const [iban, setIban] = useState("");
  const [bankResult, setBankResult] = useState<PortalBankAccountSubmission | null>(null);

  const [chatMessage, setChatMessage] = useState("");
  const [chatResult, setChatResult] = useState<string | null>(null);
  const [signatureResult, setSignatureResult] = useState<string | null>(null);
  const [additionalNote, setAdditionalNote] = useState("");
  const [additionalResult, setAdditionalResult] = useState<string | null>(null);
  const [additionalUploads, setAdditionalUploads] = useState<AdditionalUploadDraft[]>([]);

  const [inspectionAddressLine, setInspectionAddressLine] = useState("");
  const [inspectionMunicipality, setInspectionMunicipality] = useState("");
  const [inspectionProvince, setInspectionProvince] = useState("");
  const [inspectionRegion, setInspectionRegion] = useState("");
  const [inspectionLatitude, setInspectionLatitude] = useState("");
  const [inspectionLongitude, setInspectionLongitude] = useState("");
  const [inspectionNotes, setInspectionNotes] = useState("");
  const [selectedInspectionSlotKeys, setSelectedInspectionSlotKeys] = useState<string[]>([]);
  const [inspectionResult, setInspectionResult] = useState<string | null>(null);

  function syncInspectionOverview(nextOverview: PortalInspectionSchedulingOverview) {
    setInspectionOverview(nextOverview);
    setInspectionAddressLine(nextOverview.location.address_line ?? "");
    setInspectionMunicipality(nextOverview.location.municipality ?? "");
    setInspectionProvince(nextOverview.location.province ?? "");
    setInspectionRegion(nextOverview.location.region ?? "");
    setInspectionLatitude(formatCoordinateInput(nextOverview.location.latitude));
    setInspectionLongitude(formatCoordinateInput(nextOverview.location.longitude));
    setSelectedInspectionSlotKeys(
      nextOverview.selected_slots.map((slot) =>
        buildInspectionSlotKey(slot.date, slot.label)
      )
    );
  }

  async function handleDownloadDocument(documentId: string, fileName: string, claimId: string) {
    try {
      const blob = await downloadPortalDocument(session!, { documentId }, claimId);
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = fileName;
      link.click();
      URL.revokeObjectURL(url);
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Download documento non riuscito."
      );
    }
  }

  async function refreshPortalData(currentSession: PortalSession, claimId: string) {
    setIsLoading(true);
    setError(null);

    try {
      const [
        nextAccessibleClaims,
        nextSummary,
        nextTimeline,
        nextDocuments,
        nextMessages,
        nextInspectionOverview
      ] = await Promise.all([
        listAccessibleClaims(currentSession),
        getPortalClaimSummaryForClaim(currentSession, claimId),
        getPortalTimeline(currentSession, claimId),
        getPortalDocuments(currentSession, claimId),
        listPortalMessages(currentSession, claimId),
        getInspectionSchedulingOverview(currentSession, claimId)
      ]);

      setAccessibleClaims(nextAccessibleClaims);
      setSummary(nextSummary);
      setTimeline(nextTimeline);
      setDocuments(nextDocuments);
      setMessages(nextMessages.items);
      syncInspectionOverview(nextInspectionOverview);
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Impossibile caricare i dati del portale."
      );
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    const storedSession = getStoredPortalSession();
    setSession(storedSession);
    if (!storedSession) {
      setIsLoading(false);
      return;
    }

    void refreshPortalData(storedSession, storedSession.claimId);
  }, []);

  if (!session) {
    return (
      <div className="empty-state">
        <p className="empty-state__eyebrow">Sessione non disponibile</p>
        <h1>Nessuna sessione portale attiva</h1>
        <p>Apri un magic link o richiedi un nuovo accesso dalla pagina iniziale.</p>
        <Link href="/" className="primary-link">
          Torna all&apos;accesso
        </Link>
      </div>
    );
  }

  const inspectionEnabled =
    Boolean(summary?.inspection_scheduling_enabled) || Boolean(inspectionOverview?.enabled);
  const inspectionLocked = inspectionOverview?.status === "confirmed";
  const hasInspectionAvailability = Boolean(
    inspectionOverview?.availability_days.some((day) => day.slot_count > 0)
  );
  const selectedInspectionSlots = resolveSelectedInspectionSlots(
    inspectionOverview,
    selectedInspectionSlotKeys
  );

  return (
    <div className="dashboard-shell">
      <header className="dashboard-hero">
        <div>
          <p className="dashboard-hero__eyebrow">Sinistro monitorato</p>
          <h1>{summary?.external_ref ?? session.claimId}</h1>
          <p className="dashboard-hero__lead">
            {summary?.compagnia ? `${summary.compagnia} · ` : ""}
            {summary?.nome_assicurato ?? "Assicurato"}
          </p>
        </div>
        <div className="dashboard-hero__actions">
          <button
            type="button"
            className="ghost-button"
            onClick={() => {
              clearStoredPortalSession();
              window.location.href = "/";
            }}
          >
            Chiudi sessione
          </button>
        </div>
      </header>

      {isLoading ? <p className="feedback">Caricamento dashboard...</p> : null}
      {error ? <p className="feedback feedback--error">{error}</p> : null}

      {summary ? (
        <>
          {accessibleClaims.length > 0 ? (
            <section className="claims-overview">
              <div className="claims-overview__header">
                <div>
                  <p className="status-strip__eyebrow">I tuoi sinistri</p>
                  <h2>Tutti i sinistri accessibili nel portale</h2>
                </div>
                <p className="support-copy">
                  Anche i sinistri senza azioni pendenti restano sempre consultabili.
                </p>
              </div>
              <div className="claims-overview__grid">
                {accessibleClaims.map((claim) => (
                  <button
                    key={claim.claim_id}
                    type="button"
                    className={`claim-switcher-card${
                      claim.claim_id === summary.claim_id ? " claim-switcher-card--active" : ""
                    }`}
                    onClick={() => {
                      setInspectionResult(null);
                      setError(null);
                      setAdditionalResult(null);
                      setAdditionalUploads([]);
                      startTransition(() => {
                        void refreshPortalData(session, claim.claim_id);
                      });
                    }}
                  >
                    <span className="claim-switcher-card__eyebrow">
                      {claim.external_ref ?? claim.numero_sinistro ?? claim.claim_id}
                    </span>
                    <strong>{claim.macro_state.label}</strong>
                    <span>{claim.compagnia ?? "Compagnia non indicata"}</span>
                    <span>{claim.nome_assicurato ?? "Assicurato"}</span>
                    <span>
                      {claim.has_pending_actions
                        ? "Richiede attenzione"
                        : "Nessuna azione richiesta"}
                    </span>
                    <div className="claim-switcher-card__amounts">
                      <span>
                        Richiesta:{" "}
                        {claim.requested_amount != null
                          ? `${claim.requested_amount.toLocaleString("it-IT")} €`
                          : "n/d"}
                      </span>
                      <span>
                        Liquidato:{" "}
                        {claim.liquidated_amount != null
                          ? `${claim.liquidated_amount.toLocaleString("it-IT")} €`
                          : "n/d"}
                      </span>
                    </div>
                  </button>
                ))}
              </div>
            </section>
          ) : null}

          <section className="overview-panel">
            <div className="overview-panel__hero">
              <span className="overview-pill">Area assicurato</span>
              <h2>
                Benvenuto, {summary.nome_assicurato ?? "assicurato"}
              </h2>
              <p>
                Qui puoi seguire lo stato del sinistro, consultare importi e documenti, fissare il
                sopralluogo quando richiesto e completare i passaggi finali della pratica.
              </p>
            </div>

            <div className="reference-card">
              <div>
                <span className="reference-card__label">Numero pratica</span>
                <strong>{summary.external_ref ?? summary.numero_sinistro ?? summary.claim_id}</strong>
              </div>
              <div>
                <span className="reference-card__label">Aperta il</span>
                <strong>
                  {summary.data_sinistro ? formatDateTime(summary.data_sinistro) : "n/d"}
                </strong>
              </div>
            </div>

            {summary.requirements.length > 0 ? (
              <div className="alerts-stack">
                {summary.requirements.slice(0, 3).map((requirement) => (
                  <article key={requirement.key} className="alert-card">
                    <strong>{requirement.label}</strong>
                    <span>{requirement.description}</span>
                  </article>
                ))}
              </div>
            ) : null}

            <div className="progress-panel">
              <div className="progress-panel__header">
                <div>
                  <p className="section-card__eyebrow">Stato della pratica</p>
                  <h3>{summary.macro_state.label}</h3>
                </div>
                <p className="support-copy">{summary.macro_state.description}</p>
              </div>
              <ClaimProgress stateCode={summary.macro_state.internal_state} />
            </div>

            <div className="action-grid">
              <a href="#documenti" className="action-card action-card--warm">
                <strong>Documentazione</strong>
                <span>Carica documenti e completa la documentale guidata.</span>
              </a>
              <a href="#sopralluogo" className="action-card action-card--cool">
                <strong>Sopralluogo</strong>
                <span>Conferma posizione e scegli le finestre disponibili.</span>
              </a>
              <a href="#pagamenti" className="action-card">
                <strong>IBAN e importi</strong>
                <span>Consulta il quadro economico e salva le coordinate bancarie.</span>
              </a>
              <a href="#firma" className="action-card">
                <strong>Atto e firma</strong>
                <span>Verifica lo stato dell&apos;atto e completa la sottoscrizione.</span>
              </a>
            </div>
          </section>

          <section className="status-strip">
            <div>
              <p className="status-strip__eyebrow">Macro stato</p>
              <h2>{summary.macro_state.label}</h2>
              <p>{summary.macro_state.description}</p>
            </div>
            <div className="status-chip-grid">
              <div className="status-chip">
                <span>Azione richiesta</span>
                <strong>{summary.macro_state.needs_action ? "Si" : "No"}</strong>
              </div>
              <div className="status-chip">
                <span>Stato interno</span>
                <strong>{summary.macro_state.internal_state ?? "n/d"}</strong>
              </div>
              <div className="status-chip">
                <span>Chat</span>
                <strong>{summary.chat_enabled ? "Disponibile" : "Non disponibile"}</strong>
              </div>
              <div className="status-chip">
                <span>Importo richiesto</span>
                <strong>
                  {summary.requested_amount != null
                    ? `${summary.requested_amount.toLocaleString("it-IT")} €`
                    : "n/d"}
                </strong>
              </div>
              <div className="status-chip">
                <span>Liquidato</span>
                <strong>
                  {summary.liquidated_amount != null
                    ? `${summary.liquidated_amount.toLocaleString("it-IT")} €`
                    : "n/d"}
                </strong>
              </div>
            </div>
          </section>

          <div className="dashboard-grid">
            <SectionCard title="Perito incaricato" eyebrow="Contatto" accent="gold">
              {summary.expert.full_name ? (
                <>
                  <p className="stack-line">
                    <strong>{summary.expert.full_name}</strong>
                  </p>
                  <p className="stack-line">{summary.expert.job_title}</p>
                  <p className="stack-line">{summary.expert.email}</p>
                  <p className="stack-line">{summary.expert.phone_number}</p>
                  <p className="stack-line">
                    Disponibile ora: {summary.expert.is_available_now ? "Si" : "No"}
                  </p>
                  <p className="stack-line">Online: {summary.expert.is_online ? "Si" : "No"}</p>
                  <p className="stack-line">{summary.expert.availability_note}</p>
                </>
              ) : (
                <p>Perito non ancora assegnato.</p>
              )}
            </SectionCard>

            <SectionCard title="Prossime attivita" eyebrow="Pratica" accent="ink">
              {summary.requirements.length > 0 ? (
                <ul className="plain-list">
                  {summary.requirements.map((requirement) => (
                    <li key={requirement.key}>
                      <strong>{requirement.label}</strong>
                      <span>{requirement.description}</span>
                    </li>
                  ))}
                </ul>
              ) : (
                <p>Nessuna azione immediata richiesta.</p>
              )}
              {summary.upcoming_appointment ? (
                <div className="appointment-box">
                  <p className="appointment-box__title">{summary.upcoming_appointment.title}</p>
                  <p>{formatDateTime(summary.upcoming_appointment.starts_at)}</p>
                  <p>{summary.upcoming_appointment.location}</p>
                </div>
              ) : null}
            </SectionCard>

            <SectionCard title="Importi e atto" eyebrow="Quadro economico" accent="gold">
              <p className="stack-line">
                Danno stimato:{" "}
                <strong>{formatCurrency(summary.estimated_damage_amount)}</strong>
              </p>
              <p className="stack-line">
                Richiesta iniziale: <strong>{formatCurrency(summary.requested_amount)}</strong>
              </p>
              <p className="stack-line">
                Liquidato: <strong>{formatCurrency(summary.liquidated_amount)}</strong>
              </p>
              <p className="stack-line">
                Atto inviato:{" "}
                <strong>{summary.act_sent_at ? formatDateTime(summary.act_sent_at) : "non ancora"}</strong>
              </p>
              <p className="stack-line">
                Atto sottoscritto:{" "}
                <strong>
                  {summary.act_signed_at ? formatDateTime(summary.act_signed_at) : "non ancora"}
                </strong>
              </p>
              <p className="support-copy">
                Quando disponibile, l&apos;atto resta consultabile anche nella sezione documenti del
                sinistro selezionato.
              </p>
            </SectionCard>

            {inspectionEnabled && inspectionOverview ? (
              <div id="sopralluogo">
              <SectionCard title="Fissazione sopralluogo" eyebrow="Sopralluogo" accent="green">
                <div className="inspection-stack">
                  <p>{inspectionOverview.instructions}</p>
                  {inspectionOverview.pending_confirmation_message ? (
                    <p className="feedback feedback--success">
                      {inspectionOverview.pending_confirmation_message}
                    </p>
                  ) : null}
                  {inspectionResult ? <p className="feedback">{inspectionResult}</p> : null}
                  {inspectionOverview.route_review_deadline ? (
                    <p className="feedback">
                      Revisione interna in corso fino al{" "}
                      {formatDateTime(inspectionOverview.route_review_deadline)}.
                    </p>
                  ) : null}

                  <div className="inspection-layout">
                    <div className="mini-form">
                      <label>
                        Indirizzo sopralluogo
                        <input
                          value={inspectionAddressLine}
                          onChange={(event) => setInspectionAddressLine(event.target.value)}
                          placeholder="Via, civico, interno"
                          readOnly={inspectionLocked}
                        />
                      </label>

                      <div className="field-grid field-grid--triple">
                        <label>
                          Comune
                          <input
                            value={inspectionMunicipality}
                            onChange={(event) => setInspectionMunicipality(event.target.value)}
                            placeholder="Comune"
                            readOnly={inspectionLocked}
                          />
                        </label>
                        <label>
                          Provincia
                          <input
                            value={inspectionProvince}
                            onChange={(event) => setInspectionProvince(event.target.value)}
                            placeholder="MI"
                            readOnly={inspectionLocked}
                          />
                        </label>
                        <label>
                          Regione
                          <input
                            value={inspectionRegion}
                            onChange={(event) => setInspectionRegion(event.target.value)}
                            placeholder="Lombardia"
                            readOnly={inspectionLocked}
                          />
                        </label>
                      </div>

                      <div className="field-grid field-grid--double">
                        <label>
                          Latitudine
                          <input
                            value={inspectionLatitude}
                            onChange={(event) => setInspectionLatitude(event.target.value)}
                            placeholder="45.464200"
                            readOnly={inspectionLocked}
                          />
                        </label>
                        <label>
                          Longitudine
                          <input
                            value={inspectionLongitude}
                            onChange={(event) => setInspectionLongitude(event.target.value)}
                            placeholder="9.190000"
                            readOnly={inspectionLocked}
                          />
                        </label>
                      </div>

                      <p className="support-copy">
                        Posiziona il pin esattamente all&apos;ingresso o nel punto in cui il
                        tecnico deve arrivare per incontrarti.
                      </p>

                      {!inspectionLocked ? (
                        <button
                          type="button"
                          onClick={() => {
                            const latitude = parseCoordinateInput(inspectionLatitude);
                            const longitude = parseCoordinateInput(inspectionLongitude);

                            if (!inspectionAddressLine.trim()) {
                              setError("Inserisci o conferma l'indirizzo del sopralluogo.");
                              return;
                            }

                            startTransition(() => {
                              void (async () => {
                                try {
                                  await updateInspectionLocation(session, {
                                    addressLine: inspectionAddressLine,
                                    municipality: inspectionMunicipality,
                                    province: inspectionProvince,
                                    region: inspectionRegion,
                                    latitude,
                                    longitude
                                  }, summary.claim_id);
                                  setInspectionResult(
                                    "Posizione confermata. Ora puoi selezionare una o piu finestre disponibili."
                                  );
                                  await refreshPortalData(session, summary.claim_id);
                                } catch (requestError) {
                                  setError(
                                    requestError instanceof Error
                                      ? requestError.message
                                      : "Aggiornamento posizione non riuscito."
                                  );
                                }
                              })();
                            });
                          }}
                        >
                          Conferma posizione
                        </button>
                      ) : null}
                    </div>

                    <MapPinEditor
                      key={`inspection-map-${inspectionOverview.location.confirmed_at ?? "draft"}`}
                      latitude={parseCoordinateInput(inspectionLatitude) ?? null}
                      longitude={parseCoordinateInput(inspectionLongitude) ?? null}
                      disabled={inspectionLocked}
                      onChange={(nextLatitude, nextLongitude) => {
                        setInspectionLatitude(nextLatitude.toFixed(6));
                        setInspectionLongitude(nextLongitude.toFixed(6));
                      }}
                    />
                  </div>

                  <div className="inspection-candidates">
                    <div>
                      <p className="section-card__eyebrow">CAT di zona</p>
                      <h3>Copertura area sopralluogo</h3>
                    </div>
                    {inspectionOverview.candidate_cats.length > 0 ? (
                      <div className="candidate-grid">
                        {inspectionOverview.candidate_cats.map((candidate) => (
                          <article key={candidate.user_id} className="candidate-card">
                            <strong>{candidate.full_name}</strong>
                            <span>{candidate.job_title ?? "CAT"}</span>
                            <span>
                              {candidate.comune}
                              {candidate.provincia ? ` (${candidate.provincia})` : ""}
                            </span>
                            {candidate.email ? <span>{candidate.email}</span> : null}
                            {candidate.phone_number ? <span>{candidate.phone_number}</span> : null}
                            <span>
                              {candidate.is_primary_zone
                                ? "Zona primaria"
                                : candidate.distance_km
                                  ? `Supporto a ${candidate.distance_km.toFixed(1)} km`
                                  : "Zona secondaria"}
                            </span>
                          </article>
                        ))}
                      </div>
                    ) : (
                      <p className="support-copy">
                        Nessun CAT disponibile sulla base della posizione attuale.
                      </p>
                    )}
                  </div>

                  <div className="inspection-availability">
                    <div>
                      <p className="section-card__eyebrow">Finestre disponibili</p>
                      <h3>Seleziona una o piu fasce da due ore</h3>
                      <p className="support-copy">
                        Mostriamo solo le finestre compatibili con i CAT dell&apos;area e con i
                        sopralluoghi gia fissati o in pending.
                      </p>
                    </div>

                    {!inspectionOverview.address_confirmed ? (
                      <p className="feedback">
                        Conferma prima posizione e punto di incontro per attivare la selezione
                        delle disponibilita.
                      </p>
                    ) : null}

                    {hasInspectionAvailability ? (
                      <div className="inspection-days-grid">
                        {inspectionOverview.availability_days.map((day) => (
                          <article
                            key={day.date}
                            className={`inspection-day-card${
                              !day.is_available ? " inspection-day-card--disabled" : ""
                            }`}
                          >
                            <div className="inspection-day-card__header">
                              <strong>{formatInspectionDayLabel(day.date)}</strong>
                              <span>
                                {day.is_available
                                  ? `${day.slot_count} fasce disponibili`
                                  : "Nessuna disponibilita"}
                              </span>
                            </div>

                            {day.slots.length > 0 ? (
                              <div className="inspection-slot-grid">
                                {day.slots.map((slot) => {
                                  const slotKey = buildInspectionSlotKey(slot.date, slot.label);
                                  const isSelected =
                                    selectedInspectionSlotKeys.includes(slotKey);

                                  return (
                                    <button
                                      key={slot.id}
                                      type="button"
                                      className={`inspection-slot-button${
                                        isSelected ? " inspection-slot-button--selected" : ""
                                      }`}
                                      disabled={
                                        !inspectionOverview.address_confirmed || inspectionLocked
                                      }
                                      onClick={() => {
                                        setSelectedInspectionSlotKeys((current) =>
                                          current.includes(slotKey)
                                            ? current.filter((item) => item !== slotKey)
                                            : [...current, slotKey]
                                        );
                                      }}
                                    >
                                      <strong>{slot.label}</strong>
                                      <span>{slot.available_cat_count} CAT compatibili</span>
                                    </button>
                                  );
                                })}
                              </div>
                            ) : (
                              <p className="support-copy">
                                Questa giornata resta non disponibile per tutti i CAT della zona.
                              </p>
                            )}
                          </article>
                        ))}
                      </div>
                    ) : (
                      <p className="feedback">
                        Nessuna finestra utile rilevata nell&apos;orizzonte corrente di
                        pianificazione.
                      </p>
                    )}
                  </div>

                  <div className="inspection-summary-box">
                    <div>
                      <p className="section-card__eyebrow">Preferenze inviate</p>
                      <h3>Finestre selezionate</h3>
                    </div>
                    {selectedInspectionSlots.length > 0 ? (
                      <ul className="plain-list">
                        {selectedInspectionSlots.map((slot) => (
                          <li key={slot.key}>
                            <strong>{formatInspectionDayLabel(slot.date)}</strong>
                            <span>{slot.label}</span>
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <p className="support-copy">
                        Non hai ancora selezionato alcuna fascia oraria.
                      </p>
                    )}

                    {!inspectionLocked ? (
                      <div className="mini-form">
                        <label>
                          Note per il sopralluogo
                          <textarea
                            value={inspectionNotes}
                            onChange={(event) => setInspectionNotes(event.target.value)}
                            placeholder="Indicazioni di accesso, piano, citofono, vincoli orari..."
                          />
                        </label>
                        <button
                          type="button"
                          onClick={() => {
                            if (!inspectionOverview.address_confirmed) {
                              setError("Conferma prima la posizione del sopralluogo.");
                              return;
                            }

                            if (selectedInspectionSlots.length === 0) {
                              setError(
                                "Seleziona almeno una fascia oraria prima di inviare le preferenze."
                              );
                              return;
                            }

                            startTransition(() => {
                              void (async () => {
                                try {
                                  await submitInspectionPreferences(session, {
                                    selectedSlots: selectedInspectionSlots.map((slot) => ({
                                      date: slot.date,
                                      startTime: slot.startTime,
                                      endTime: slot.endTime,
                                      label: slot.label
                                    })),
                                    notes: inspectionNotes,
                                    requestedDurationMinutes: 120
                                  }, summary.claim_id);
                                  setInspectionResult(
                                    "Preferenze inviate. Riceverai il messaggio di conferma entro le 24 ore precedenti alla data selezionata."
                                  );
                                  await refreshPortalData(session, summary.claim_id);
                                } catch (requestError) {
                                  setError(
                                    requestError instanceof Error
                                      ? requestError.message
                                      : "Invio preferenze sopralluogo non riuscito."
                                  );
                                }
                              })();
                            });
                          }}
                        >
                          Invia preferenze sopralluogo
                        </button>
                      </div>
                    ) : null}
                  </div>
                </div>
              </SectionCard>
              </div>
            ) : null}

            <SectionCard title="Timeline" eyebrow="Avanzamento" accent="green">
              <ul className="plain-list">
                {timeline.map((event) => (
                  <li key={event.id}>
                    <strong>{event.label}</strong>
                    <span>{formatDateTime(event.event_time)}</span>
                    {event.description ? <span>{event.description}</span> : null}
                  </li>
                ))}
              </ul>
            </SectionCard>

            <div id="documenti">
            <SectionCard title="Documenti" eyebrow="Archivio pratica" accent="ink">
              <ul className="plain-list">
                {documents.map((document) => (
                  <li key={document.id}>
                    <strong>{document.file_name}</strong>
                    <span>{document.category ?? "senza categoria"}</span>
                    <span>{document.status}</span>
                  </li>
                ))}
              </ul>
              <div className="mini-form">
                <input
                  value={uploadFileName}
                  onChange={(event) => setUploadFileName(event.target.value)}
                  placeholder="nome-file.pdf"
                />
                <button
                  type="button"
                  onClick={() => {
                    if (!uploadFileName) {
                      setError("Inserisci un nome file per simulare l'intent di upload.");
                      return;
                    }
                    startTransition(() => {
                      void (async () => {
                        try {
                          const nextIntent = await createUploadIntent(session, {
                            fileName: uploadFileName,
                            category: "insured_upload"
                          }, summary.claim_id);
                          setUploadIntent(nextIntent);
                        } catch (requestError) {
                          setError(
                            requestError instanceof Error
                              ? requestError.message
                              : "Creazione intent non riuscita."
                          );
                        }
                      })();
                    });
                  }}
                >
                  Crea upload intent
                </button>
              </div>
              {uploadIntent ? (
                <div className="feedback">
                  <p>Document ID: {uploadIntent.document_id}</p>
                  <p>Storage path: {uploadIntent.storage_path}</p>
                  <p>Modo upload: {uploadIntent.upload_mode}</p>
                </div>
              ) : null}
            </SectionCard>
            </div>

            <SectionCard title="Documentale guidata" eyebrow="Workflow mobile" accent="gold">
              <div className="process-panel">
                <div className="process-panel__intro">
                  <strong>Una procedura semplice, un passaggio alla volta</strong>
                  <p>
                    Prima ci indichi i beni danneggiati e il tipo di danno. Solo dopo ti
                    chiederemo foto, video, documenti utili e infine i giustificativi di
                    riparazione o sostituzione.
                  </p>
                </div>
                <ul className="process-panel__steps">
                  <li>1. Numero beni e dettagli di ogni bene danneggiato</li>
                  <li>2. Due foto del fabbricato</li>
                  <li>3. Foto del bene completo e dei componenti danneggiati</li>
                  <li>4. Eventuali video e altri documenti utili</li>
                  <li>5. Fatture o preventivi per riparazione o sostituzione</li>
                </ul>
              </div>
              <DocumentCollectionWizard
                session={session}
                claimId={summary.claim_id}
                onSubmitted={async (message) => {
                  setDocumentaleResult(message);
                  await refreshPortalData(session, summary.claim_id);
                }}
              />
              {documentaleResult ? (
                <p className="feedback feedback--success">{documentaleResult}</p>
              ) : null}
            </SectionCard>

            <div id="pagamenti">
            <SectionCard title="Coordinate bancarie" eyebrow="Liquidazione" accent="green">
              {!summary.iban_value_masked ? (
                <div className="process-panel">
                  <div className="process-panel__intro">
                    <strong>IBAN necessario per proseguire</strong>
                    <p>
                      Per i sinistri FE l&apos;IBAN deve essere intestato al contraente di polizza.
                      Senza questo dato la pratica non potra avanzare verso la liquidazione.
                    </p>
                  </div>
                </div>
              ) : null}
              <p className="support-copy">
                Contraente di polizza: <strong>{summary.contraente_name ?? "non indicato"}</strong>
              </p>
              <div className="mini-form">
                <input
                  value={iban}
                  onChange={(event) => setIban(event.target.value)}
                  placeholder="IT60X0542811101000000123456"
                />
                <button
                  type="button"
                  onClick={() => {
                    startTransition(() => {
                      void (async () => {
                        try {
                          const response = await submitBankAccount(session, {
                            iban
                          }, summary.claim_id);
                          setBankResult(response);
                          await refreshPortalData(session, summary.claim_id);
                        } catch (requestError) {
                          setError(
                            requestError instanceof Error
                              ? requestError.message
                              : "Salvataggio IBAN non riuscito."
                          );
                        }
                      })();
                    });
                  }}
                >
                  Valida e salva
                </button>
              </div>
              <p className="support-copy">
                Nota: in questa fase puoi indicare solo l&apos;IBAN del contraente. TODO:
                estendere il flusso per altre tipologie di sinistro con piu intestatari e piu
                coordinate.
              </p>
              {summary.iban_value_masked ? (
                <p className="feedback feedback--success">
                  IBAN gia registrato sul sinistro: {summary.iban_value_masked}
                </p>
              ) : null}
              {bankResult ? (
                <div className="feedback">
                  <p>Esito: {bankResult.validation.is_valid ? "IBAN valido" : "IBAN non valido"}</p>
                  <p>IBAN normalizzato: {bankResult.validation.normalized_iban}</p>
                  {bankResult.validation.abi ? <p>ABI: {bankResult.validation.abi}</p> : null}
                  {bankResult.validation.cab ? <p>CAB: {bankResult.validation.cab}</p> : null}
                </div>
              ) : null}
            </SectionCard>
            </div>

            <SectionCard
              title="Carica altra documentazione utile"
              eyebrow="Documenti aggiuntivi"
              accent="green"
            >
              {summary.additional_document_requests.length > 0 ? (
                <div className="process-panel">
                  <div className="process-panel__intro">
                    <strong>Richieste del perito</strong>
                    <p>Qui sotto trovi l&apos;elenco della documentazione aggiuntiva richiesta.</p>
                  </div>
                  <ul className="process-panel__steps">
                    {summary.additional_document_requests.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </div>
              ) : (
                <p className="support-copy">
                  Puoi caricare in qualsiasi momento altra documentazione utile anche se non ci sono
                  richieste specifiche in elenco.
                </p>
              )}

              <div className="mini-form">
                <textarea
                  value={additionalNote}
                  onChange={(event) => setAdditionalNote(event.target.value)}
                  placeholder="Descrivi brevemente cosa stai caricando."
                />
                <input
                  type="file"
                  multiple
                  accept=".pdf,image/*,video/*"
                  onChange={(event) => {
                    const files = Array.from(event.target.files ?? []);
                    if (files.length === 0) {
                      return;
                    }
                    startTransition(() => {
                      void (async () => {
                        try {
                          const uploaded: AdditionalUploadDraft[] = [];
                          for (const file of files) {
                            const intent = await createUploadIntent(
                              session,
                              {
                                fileName: file.name,
                                mimeType: file.type,
                                sizeBytes: file.size,
                                category: "insured_additional_document"
                              },
                              summary.claim_id
                            );
                            await uploadPortalDocumentFile(
                              session,
                              {
                                documentId: intent.document_id,
                                file
                              },
                              summary.claim_id
                            );
                            uploaded.push({
                              documentId: intent.document_id,
                              fileName: file.name
                            });
                          }
                          setAdditionalUploads((current) => [...current, ...uploaded]);
                          setAdditionalResult("File acquisiti. Non possono piu essere rimossi dal portale.");
                        } catch (requestError) {
                          setError(
                            requestError instanceof Error
                              ? requestError.message
                              : "Caricamento documentazione aggiuntiva non riuscito."
                          );
                        }
                      })();
                    });
                    event.currentTarget.value = "";
                  }}
                />
                <button
                  type="button"
                  onClick={() => {
                    if (additionalUploads.length === 0) {
                      setAdditionalResult("Carica almeno un file prima di inviare.");
                      return;
                    }
                    startTransition(() => {
                      void (async () => {
                        try {
                          const response = await submitAdditionalDocuments(
                            session,
                            {
                              note: additionalNote,
                              documentIds: additionalUploads.map((item) => item.documentId),
                              requestedItems: summary.additional_document_requests
                            },
                            summary.claim_id
                          );
                          setAdditionalResult(
                            `Documentazione aggiuntiva inviata: ${response.document_count} file alle ${formatDateTime(
                              response.submitted_at
                            )}`
                          );
                          setAdditionalNote("");
                          setAdditionalUploads([]);
                          await refreshPortalData(session, summary.claim_id);
                        } catch (requestError) {
                          setError(
                            requestError instanceof Error
                              ? requestError.message
                              : "Invio documentazione aggiuntiva non riuscito."
                          );
                        }
                      })();
                    });
                  }}
                >
                  Invia documentazione aggiuntiva
                </button>
              </div>
              {additionalUploads.length > 0 ? (
                <ul className="plain-list">
                  {additionalUploads.map((item) => (
                    <li key={item.documentId}>
                      <strong>{item.fileName}</strong>
                      <span>Acquisito dal portale</span>
                    </li>
                  ))}
                </ul>
              ) : null}
              {additionalResult ? <p className="feedback">{additionalResult}</p> : null}
            </SectionCard>

            <SectionCard title="Chat con il perito" eyebrow="Conversazione" accent="ink">
              <div className="chat-stream">
                {messages.map((message) => (
                  <article
                    key={message.id}
                    className={`chat-bubble chat-bubble--${message.author_type}`}
                  >
                    <p>{message.body_text}</p>
                    <span>{formatDateTime(message.created_at)}</span>
                  </article>
                ))}
              </div>
              <div className="mini-form">
                <textarea
                  value={chatMessage}
                  onChange={(event) => setChatMessage(event.target.value)}
                  placeholder="Scrivi un messaggio da inoltrare nella chat interna..."
                />
                <button
                  type="button"
                  onClick={() => {
                    if (!chatMessage.trim()) {
                      setChatResult("Inserisci un messaggio prima di inviare.");
                      return;
                    }
                    startTransition(() => {
                      void (async () => {
                        try {
                          await createPortalMessage(session, { bodyText: chatMessage }, summary.claim_id);
                          setChatMessage("");
                          setChatResult("Messaggio inviato e instradato al team.");
                          await refreshPortalData(session, summary.claim_id);
                        } catch (requestError) {
                          setError(
                            requestError instanceof Error
                              ? requestError.message
                              : "Invio messaggio non riuscito."
                          );
                        }
                      })();
                    });
                  }}
                >
                  Invia messaggio
                </button>
              </div>
              {chatResult ? <p className="feedback">{chatResult}</p> : null}
            </SectionCard>

            <div id="firma">
            <SectionCard title="Firma atto" eyebrow="Sottoscrizione" accent="gold">
              {summary.act_flow ? (
                <>
                  <p className="stack-line">
                    Stato attuale: <strong>{summary.act_flow.label}</strong>
                  </p>
                  {summary.act_flow.provider ? (
                    <p className="stack-line">Provider firma: {summary.act_flow.provider}</p>
                  ) : null}
                  {summary.act_flow.signing_url ? (
                    <p className="stack-line">
                      <a
                        href={summary.act_flow.signing_url}
                        target="_blank"
                        rel="noreferrer"
                        className="primary-link"
                      >
                        Apri link di firma esterna
                      </a>
                    </p>
                  ) : null}
                  {summary.act_flow.signed_at ? (
                    <p className="stack-line">
                      Firmato dall&apos;assicurato il {formatDateTime(summary.act_flow.signed_at)}
                    </p>
                  ) : null}
                  {summary.act_flow.countersigned_at ? (
                    <p className="stack-line">
                      Controfirmato il {formatDateTime(summary.act_flow.countersigned_at)}
                    </p>
                  ) : null}
                  {summary.act_flow.countersigned_document_id ? (
                    <button
                      type="button"
                      onClick={() =>
                        void handleDownloadDocument(
                          summary.act_flow?.countersigned_document_id ?? "",
                          "atto-controfirmato.pdf",
                          summary.claim_id
                        )
                      }
                    >
                      Scarica PDF controfirmato
                    </button>
                  ) : null}
                  <p className="support-copy">
                    Flusso previsto: l&apos;atto viene pubblicato, firmato esternamente
                    dall&apos;assicurato, poi controfirmato dallo studio e infine reso disponibile
                    qui sul portale.
                  </p>
                </>
              ) : (
                <p className="support-copy">
                  Quando l&apos;atto sara pronto comparira qui il link alla firma esterna e, a
                  seguire, il PDF controfirmato da scaricare.
                </p>
              )}
              {signatureResult ? <p className="feedback">{signatureResult}</p> : null}
            </SectionCard>
            </div>
          </div>
        </>
      ) : null}
    </div>
  );
}
