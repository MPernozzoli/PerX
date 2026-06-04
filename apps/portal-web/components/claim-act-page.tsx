"use client";

import Link from "next/link";

import { ClaimPageHeader, SessionMissingState } from "@/components/claim-page-primitives";
import { SectionCard } from "@/components/section-card";
import { usePortalClaimData } from "@/components/use-portal-claim-data";
import { downloadPortalDocument } from "@/lib/api";
import { formatDateTime, getActSummary } from "@/lib/claim-ui";

export function ClaimActPage() {
  const { error, isLoading, session, setError, summary } = usePortalClaimData();

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
    return <p className="feedback">Caricamento sezione atto...</p>;
  }

  const actSummary = getActSummary(summary);

  return (
    <div className="dashboard-shell">
      <ClaimPageHeader
        eyebrow="Atto"
        title={actSummary.title}
        description={actSummary.description}
        summary={summary}
      >
        <Link href="/claim" className="ghost-button">
          Torna alla dashboard
        </Link>
      </ClaimPageHeader>

      {isLoading ? <p className="feedback">Caricamento dati...</p> : null}
      {error ? <p className="feedback feedback--error">{error}</p> : null}

      <div className="workspace-grid">
        <SectionCard title="Firma e sottoscrizione" eyebrow="Workflow" accent="gold">
          {summary.act_flow ? (
            <div className="process-panel">
              <div className="process-panel__intro">
                <strong>{summary.act_flow.label}</strong>
                <p>
                  Il flusso prevede invio atto, firma esterna dell&apos;assicurato, aggiornamento via
                  webhook, controfirma dello studio e pubblicazione del PDF finale nel portale.
                </p>
              </div>
              <ul className="plain-list">
                {summary.act_flow.provider ? (
                  <li>
                    <strong>Provider firma</strong>
                    <span>{summary.act_flow.provider}</span>
                  </li>
                ) : null}
                {summary.act_flow.signed_at ? (
                  <li>
                    <strong>Firmato dall&apos;assicurato</strong>
                    <span>{formatDateTime(summary.act_flow.signed_at)}</span>
                  </li>
                ) : null}
                {summary.act_flow.countersigned_at ? (
                  <li>
                    <strong>Controfirmato</strong>
                    <span>{formatDateTime(summary.act_flow.countersigned_at)}</span>
                  </li>
                ) : null}
              </ul>
            </div>
          ) : (
            <p className="support-copy">
              Quando l&apos;atto sarà pronto comparirà qui il link alla firma esterna e, a seguire, il
              PDF controfirmato da scaricare.
            </p>
          )}

          {summary.act_flow?.signing_url ? (
            <a
              href={summary.act_flow.signing_url}
              target="_blank"
              rel="noreferrer"
              className="primary-link"
            >
              Apri link di firma esterna
            </a>
          ) : null}

          {summary.act_flow?.countersigned_document_id ? (
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
        </SectionCard>

        <SectionCard title="Stato del processo" eyebrow="Riepilogo" accent="ink">
          <ul className="plain-list">
            <li>
              <strong>Atto inviato</strong>
              <span>{summary.act_sent_at ? formatDateTime(summary.act_sent_at) : "non ancora"}</span>
            </li>
            <li>
              <strong>Atto ricevuto sottoscritto</strong>
              <span>{summary.act_signed_at ? formatDateTime(summary.act_signed_at) : "non ancora"}</span>
            </li>
            <li>
              <strong>Stato pratica</strong>
              <span>{summary.macro_state.label}</span>
            </li>
          </ul>
        </SectionCard>
      </div>
    </div>
  );
}
