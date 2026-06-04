"use client";

import Link from "next/link";
import { startTransition, useState } from "react";

import { ClaimPageHeader, SessionMissingState } from "@/components/claim-page-primitives";
import { DocumentCollectionWizard } from "@/components/document-collection-wizard";
import { SectionCard } from "@/components/section-card";
import { usePortalClaimData } from "@/components/use-portal-claim-data";
import {
  createUploadIntent,
  downloadPortalDocument,
  submitAdditionalDocuments,
  uploadPortalDocumentFile
} from "@/lib/api";
import {
  formatDateTime,
  getDocumentationSummary,
  isDocumentCollectionMode
} from "@/lib/claim-ui";

type AdditionalUploadDraft = {
  documentId: string;
  fileName: string;
};

export function ClaimDocumentationPage() {
  const { documents, error, isLoading, refresh, session, setError, summary } = usePortalClaimData();
  const [documentaleResult, setDocumentaleResult] = useState<string | null>(null);
  const [additionalNote, setAdditionalNote] = useState("");
  const [additionalUploads, setAdditionalUploads] = useState<AdditionalUploadDraft[]>([]);
  const [additionalResult, setAdditionalResult] = useState<string | null>(null);

  if (!session) {
    return <SessionMissingState />;
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
        requestError instanceof Error ? requestError.message : "Download documento non riuscito."
      );
    }
  }

  if (!summary) {
    return <p className="feedback">Caricamento sezione documentazione...</p>;
  }

  const documentationSummary = getDocumentationSummary(summary);
  const documentCollectionMode = isDocumentCollectionMode(summary);

  return (
    <div className="dashboard-shell">
      <ClaimPageHeader
        eyebrow="Documentazione"
        title={documentationSummary.title}
        description={documentationSummary.description}
        summary={summary}
      >
        <Link href="/claim" className="ghost-button">
          Torna alla dashboard
        </Link>
      </ClaimPageHeader>

      {isLoading ? <p className="feedback">Caricamento dati...</p> : null}
      {error ? <p className="feedback feedback--error">{error}</p> : null}

      <div className="workspace-grid workspace-grid--single">
        {documentCollectionMode ? (
          <>
            <div className="process-panel">
              <div className="process-panel__intro">
                <strong>Procedura guidata documentale</strong>
                <p>
                  Questa è la procedura principale della pagina. Ogni passo viene salvato
                  automaticamente e, una volta caricati i file, non potranno più essere rimossi dal
                  portale.
                </p>
              </div>
            </div>
            <DocumentCollectionWizard
              session={session}
              claimId={summary.claim_id}
              onSubmitted={async (message) => {
                setDocumentaleResult(message);
                await refresh(summary.claim_id);
              }}
            />
            {documentaleResult ? (
              <p className="feedback feedback--success">{documentaleResult}</p>
            ) : null}
          </>
        ) : (
          <SectionCard title="Gestione documentazione" eyebrow="Operatività" accent="gold">
            {summary.additional_document_requests.length > 0 ? (
              <div className="process-panel">
                <div className="process-panel__intro">
                  <strong>Documenti richiesti dal perito</strong>
                  <p>Carica qui sotto i file richiesti. Il campo resta unico e si adatta alla pratica.</p>
                </div>
                <ul className="process-panel__steps">
                  {summary.additional_document_requests.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              </div>
            ) : (
              <p className="support-copy">
                Puoi allegare in qualsiasi momento foto, video o documenti utili alla gestione del
                sinistro.
              </p>
            )}

            <div className="mini-form">
              <label>
                Descrizione
                <textarea
                  value={additionalNote}
                  onChange={(event) => setAdditionalNote(event.target.value)}
                  placeholder="Spiega brevemente cosa stai caricando."
                />
              </label>
              <label>
                File da caricare
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
                          setAdditionalResult(
                            "File acquisiti. Una volta caricati non possono più essere rimossi dal portale."
                          );
                        } catch (requestError) {
                          setError(
                            requestError instanceof Error
                              ? requestError.message
                              : "Caricamento documentazione non riuscito."
                          );
                        }
                      })();
                    });
                    event.currentTarget.value = "";
                  }}
                />
              </label>
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
                          `Documentazione inviata: ${response.document_count} file alle ${formatDateTime(
                            response.submitted_at
                          )}`
                        );
                        setAdditionalNote("");
                        setAdditionalUploads([]);
                        await refresh(summary.claim_id);
                      } catch (requestError) {
                        setError(
                          requestError instanceof Error
                            ? requestError.message
                            : "Invio documentazione non riuscito."
                        );
                      }
                    })();
                  });
                }}
              >
                Invia documentazione
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
        )}

        <SectionCard title="Documenti del sinistro" eyebrow="Archivio" accent="ink">
          {documents.length > 0 ? (
            <ul className="plain-list">
              {documents.map((document) => (
                <li key={document.id}>
                  <strong>{document.file_name}</strong>
                  <span>{document.category ?? "senza categoria"}</span>
                  <span>{document.status}</span>
                  <button
                    type="button"
                    className="link-button"
                    onClick={() =>
                      void handleDownloadDocument(document.id, document.file_name, summary.claim_id)
                    }
                  >
                    Scarica
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <p>Nessun documento ancora disponibile sul sinistro.</p>
          )}
        </SectionCard>
      </div>
    </div>
  );
}
