"use client";

import Link from "next/link";
import { startTransition, useEffect, useState } from "react";

import { SectionCard } from "@/components/section-card";
import {
  confirmSignatureRequest,
  createPortalMessage,
  createSignatureRequest,
  createUploadIntent,
  getPortalClaimSummary,
  getPortalDocuments,
  getPortalTimeline,
  listPortalMessages,
  submitBankAccount,
  submitDocumentCollection
} from "@/lib/api";
import { clearStoredPortalSession, getStoredPortalSession } from "@/lib/session";
import type {
  PortalBankAccountSubmission,
  PortalClaimSummary,
  PortalDocument,
  PortalMessage,
  PortalSession,
  PortalSignatureRequest,
  PortalTimelineEvent,
  PortalUploadIntent
} from "@/lib/types";

export function ClaimDashboard() {
  const [session, setSession] = useState<PortalSession | null>(null);
  const [summary, setSummary] = useState<PortalClaimSummary | null>(null);
  const [timeline, setTimeline] = useState<PortalTimelineEvent[]>([]);
  const [documents, setDocuments] = useState<PortalDocument[]>([]);
  const [messages, setMessages] = useState<PortalMessage[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [uploadFileName, setUploadFileName] = useState("");
  const [uploadIntent, setUploadIntent] = useState<PortalUploadIntent | null>(null);

  const [documentaleNotes, setDocumentaleNotes] = useState("");
  const [documentalePhotosCount, setDocumentalePhotosCount] = useState("0");
  const [documentaleItemName, setDocumentaleItemName] = useState("");
  const [documentaleResult, setDocumentaleResult] = useState<string | null>(null);

  const [iban, setIban] = useState("");
  const [accountHolder, setAccountHolder] = useState("");
  const [bankResult, setBankResult] = useState<PortalBankAccountSubmission | null>(null);

  const [chatMessage, setChatMessage] = useState("");
  const [chatResult, setChatResult] = useState<string | null>(null);

  const [signatureDocumentId, setSignatureDocumentId] = useState("");
  const [signatureRequest, setSignatureRequest] = useState<PortalSignatureRequest | null>(null);
  const [signatureToken, setSignatureToken] = useState("");
  const [signatureResult, setSignatureResult] = useState<string | null>(null);

  async function refreshPortalData(currentSession: PortalSession) {
    setIsLoading(true);
    setError(null);

    try {
      const [nextSummary, nextTimeline, nextDocuments, nextMessages] = await Promise.all([
        getPortalClaimSummary(currentSession),
        getPortalTimeline(currentSession),
        getPortalDocuments(currentSession),
        listPortalMessages(currentSession)
      ]);

      setSummary(nextSummary);
      setTimeline(nextTimeline);
      setDocuments(nextDocuments);
      setMessages(nextMessages.items);

      if (!signatureDocumentId && nextDocuments.length > 0) {
        const actDocument = nextDocuments.find((document) => document.category === "act");
        if (actDocument) {
          setSignatureDocumentId(actDocument.id);
        }
      }
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

    void refreshPortalData(storedSession);
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
                  <p>{new Date(summary.upcoming_appointment.starts_at).toLocaleString()}</p>
                  <p>{summary.upcoming_appointment.location}</p>
                </div>
              ) : null}
            </SectionCard>

            <SectionCard title="Timeline" eyebrow="Avanzamento" accent="green">
              <ul className="plain-list">
                {timeline.map((event) => (
                  <li key={event.id}>
                    <strong>{event.label}</strong>
                    <span>{new Date(event.event_time).toLocaleString()}</span>
                    {event.description ? <span>{event.description}</span> : null}
                  </li>
                ))}
              </ul>
            </SectionCard>

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
                          });
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

            <SectionCard title="Documentale guidata" eyebrow="Workflow mobile" accent="gold">
              <div className="mini-form">
                <input
                  value={documentaleItemName}
                  onChange={(event) => setDocumentaleItemName(event.target.value)}
                  placeholder="Nome bene o componente"
                />
                <input
                  value={documentalePhotosCount}
                  onChange={(event) => setDocumentalePhotosCount(event.target.value)}
                  placeholder="Numero foto"
                />
                <textarea
                  value={documentaleNotes}
                  onChange={(event) => setDocumentaleNotes(event.target.value)}
                  placeholder="Note operative, geolocalizzazione, osservazioni..."
                />
                <button
                  type="button"
                  onClick={() => {
                    startTransition(() => {
                      void (async () => {
                        try {
                          const response = await submitDocumentCollection(session, {
                            notes: documentaleNotes,
                            photosCount: Number(documentalePhotosCount || "0"),
                            items: documentaleItemName
                              ? [
                                  {
                                    name: documentaleItemName,
                                    quantity: 1
                                  }
                                ]
                              : []
                          });
                          setDocumentaleResult(
                            `Invio completato: ${response.status} alle ${new Date(
                              response.submitted_at
                            ).toLocaleString()}`
                          );
                          await refreshPortalData(session);
                        } catch (requestError) {
                          setError(
                            requestError instanceof Error
                              ? requestError.message
                              : "Invio documentale non riuscito."
                          );
                        }
                      })();
                    });
                  }}
                >
                  Registra documentale
                </button>
              </div>
              {documentaleResult ? <p className="feedback">{documentaleResult}</p> : null}
            </SectionCard>

            <SectionCard title="Coordinate bancarie" eyebrow="Liquidazione" accent="green">
              <div className="mini-form">
                <input
                  value={iban}
                  onChange={(event) => setIban(event.target.value)}
                  placeholder="IT60X0542811101000000123456"
                />
                <input
                  value={accountHolder}
                  onChange={(event) => setAccountHolder(event.target.value)}
                  placeholder="Intestatario"
                />
                <button
                  type="button"
                  onClick={() => {
                    startTransition(() => {
                      void (async () => {
                        try {
                          const response = await submitBankAccount(session, {
                            iban,
                            accountHolder
                          });
                          setBankResult(response);
                          await refreshPortalData(session);
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
              {bankResult ? (
                <div className="feedback">
                  <p>Esito: {bankResult.validation.is_valid ? "IBAN valido" : "IBAN non valido"}</p>
                  <p>IBAN normalizzato: {bankResult.validation.normalized_iban}</p>
                  {bankResult.validation.abi ? <p>ABI: {bankResult.validation.abi}</p> : null}
                  {bankResult.validation.cab ? <p>CAB: {bankResult.validation.cab}</p> : null}
                </div>
              ) : null}
            </SectionCard>

            <SectionCard title="Chat con il perito" eyebrow="Conversazione" accent="ink">
              <div className="chat-stream">
                {messages.map((message) => (
                  <article key={message.id} className={`chat-bubble chat-bubble--${message.author_type}`}>
                    <p>{message.body_text}</p>
                    <span>{new Date(message.created_at).toLocaleString()}</span>
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
                          await createPortalMessage(session, { bodyText: chatMessage });
                          setChatMessage("");
                          setChatResult("Messaggio inviato e instradato al team.");
                          await refreshPortalData(session);
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

            <SectionCard title="Firma atto" eyebrow="Sottoscrizione" accent="gold">
              <div className="mini-form">
                <input
                  value={signatureDocumentId}
                  onChange={(event) => setSignatureDocumentId(event.target.value)}
                  placeholder="Document ID atto"
                />
                <button
                  type="button"
                  onClick={() => {
                    if (!signatureDocumentId) {
                      setSignatureResult("Seleziona un documento da firmare.");
                      return;
                    }
                    startTransition(() => {
                      void (async () => {
                        try {
                          const response = await createSignatureRequest(session, {
                            documentId: signatureDocumentId
                          });
                          setSignatureRequest(response);
                          setSignatureResult("Challenge di firma creato.");
                        } catch (requestError) {
                          setError(
                            requestError instanceof Error
                              ? requestError.message
                              : "Creazione firma non riuscita."
                          );
                        }
                      })();
                    });
                  }}
                >
                  Richiedi firma
                </button>
              </div>

              {signatureRequest ? (
                <div className="feedback">
                  <p>ID richiesta: {signatureRequest.id}</p>
                  <p>Stato: {signatureRequest.status}</p>
                  {signatureRequest.preview_token ? (
                    <p>Preview token sviluppo: {signatureRequest.preview_token}</p>
                  ) : null}
                </div>
              ) : null}

              <div className="mini-form">
                <input
                  value={signatureToken}
                  onChange={(event) => setSignatureToken(event.target.value)}
                  placeholder="Token di conferma firma"
                />
                <button
                  type="button"
                  onClick={() => {
                    if (!signatureRequest?.id || !signatureToken) {
                      setSignatureResult("Genera prima la richiesta e inserisci il token.");
                      return;
                    }
                    startTransition(() => {
                      void (async () => {
                        try {
                          const response = await confirmSignatureRequest(session, {
                            requestId: signatureRequest.id,
                            token: signatureToken
                          });
                          setSignatureResult(
                            `Firma registrata: ${response.status} alle ${
                              response.signed_at
                                ? new Date(response.signed_at).toLocaleString()
                                : "n/d"
                            }`
                          );
                          await refreshPortalData(session);
                        } catch (requestError) {
                          setError(
                            requestError instanceof Error
                              ? requestError.message
                              : "Conferma firma non riuscita."
                          );
                        }
                      })();
                    });
                  }}
                >
                  Conferma firma
                </button>
              </div>
              {signatureResult ? <p className="feedback">{signatureResult}</p> : null}
            </SectionCard>
          </div>
        </>
      ) : null}
    </div>
  );
}
