"use client";

import Link from "next/link";
import { startTransition } from "react";

import { ClaimPageHeader, ClaimSwitcher, SessionMissingState } from "@/components/claim-page-primitives";
import { ClaimProgress } from "@/components/claim-progress";
import { SectionCard } from "@/components/section-card";
import { usePortalClaimData } from "@/components/use-portal-claim-data";
import {
  formatCurrency,
  formatDateTime,
  getActSummary,
  getDocumentationSummary,
  getIbanSummary,
  getInspectionSummary
} from "@/lib/claim-ui";

export function ClaimDashboard() {
  const { accessibleClaims, error, isLoading, session, signOut, summary, switchClaim, timeline } =
    usePortalClaimData();

  if (!session) {
    return <SessionMissingState />;
  }

  const documentationSummary = getDocumentationSummary(summary);
  const ibanSummary = getIbanSummary(summary);
  const inspectionSummary = getInspectionSummary(summary);
  const actSummary = getActSummary(summary);

  return (
    <div className="dashboard-shell">
      {summary ? (
        <>
          <ClaimPageHeader
            eyebrow="Dashboard"
            title="Il tuo sinistro in sintesi"
            description="Qui trovi solo le informazioni essenziali della pratica e l'accesso rapido alle sezioni in cui puoi intervenire."
            summary={summary}
          >
            <button type="button" className="ghost-button" onClick={signOut}>
              Chiudi sessione
            </button>
          </ClaimPageHeader>

          <ClaimSwitcher
            claims={accessibleClaims}
            activeClaimId={summary.claim_id}
            onSelect={(claimId) => {
              startTransition(() => {
                void switchClaim(claimId);
              });
            }}
          />
        </>
      ) : null}

      {isLoading ? <p className="feedback">Caricamento dashboard...</p> : null}
      {error ? <p className="feedback feedback--error">{error}</p> : null}

      {summary ? (
        <>
          <section className="overview-panel overview-panel--compact">
            <div className="reference-card">
              <div>
                <span className="reference-card__label">Compagnia</span>
                <strong>{summary.compagnia ?? "n/d"}</strong>
              </div>
              <div>
                <span className="reference-card__label">Assicurato</span>
                <strong>{summary.nome_assicurato ?? "n/d"}</strong>
              </div>
              <div>
                <span className="reference-card__label">Data sinistro</span>
                <strong>{summary.data_sinistro ? formatDateTime(summary.data_sinistro) : "n/d"}</strong>
              </div>
              <div>
                <span className="reference-card__label">Perito assegnato</span>
                <strong>{summary.expert.full_name ?? "Non ancora assegnato"}</strong>
              </div>
            </div>

            <div className="progress-panel">
              <div className="progress-panel__header">
                <div>
                  <p className="section-card__eyebrow">Avanzamento</p>
                  <h3>{summary.macro_state.label}</h3>
                </div>
                <p className="support-copy">{summary.macro_state.description}</p>
              </div>
              <ClaimProgress stateCode={summary.macro_state.internal_state} />
            </div>
          </section>

          <section className="dashboard-focus-grid">
            <Link
              href="/claim/documentazione"
              className={`dashboard-focus-card${
                documentationSummary.emphasis ? " dashboard-focus-card--emphasis" : ""
              }`}
            >
              <p className="dashboard-focus-card__eyebrow">Documentazione</p>
              <h2>{documentationSummary.title}</h2>
              <p>{documentationSummary.description}</p>
              <span>Apri sezione documentazione</span>
            </Link>

            <Link
              href="/claim/iban"
              className={`dashboard-focus-card${
                ibanSummary.emphasis ? " dashboard-focus-card--emphasis" : ""
              }`}
            >
              <p className="dashboard-focus-card__eyebrow">IBAN</p>
              <h2>{ibanSummary.title}</h2>
              <p>{ibanSummary.description}</p>
              <span>{summary.iban_value_masked ? "Vedi o modifica IBAN" : "Inserisci IBAN"}</span>
            </Link>

            <Link
              href="/claim/sopralluogo"
              className={`dashboard-focus-card${
                inspectionSummary.emphasis ? " dashboard-focus-card--emphasis" : ""
              }`}
            >
              <p className="dashboard-focus-card__eyebrow">{inspectionSummary.modeLabel}</p>
              <h2>{inspectionSummary.title}</h2>
              <p>{inspectionSummary.description}</p>
              <span>Apri sezione {inspectionSummary.modeLabel.toLowerCase()}</span>
            </Link>

            <Link
              href="/claim/atto"
              className={`dashboard-focus-card${
                actSummary.emphasis ? " dashboard-focus-card--emphasis" : ""
              }`}
            >
              <p className="dashboard-focus-card__eyebrow">Atto</p>
              <h2>{actSummary.title}</h2>
              <p>{actSummary.description}</p>
              <span>Apri sezione atto</span>
            </Link>
          </section>

          <div className="dashboard-grid dashboard-grid--overview">
            <SectionCard title="Informazioni essenziali" eyebrow="Pratica" accent="ink">
              <ul className="plain-list">
                <li>
                  <strong>Importo richiesto</strong>
                  <span>{formatCurrency(summary.requested_amount)}</span>
                </li>
                <li>
                  <strong>Danno stimato</strong>
                  <span>{formatCurrency(summary.estimated_damage_amount)}</span>
                </li>
                <li>
                  <strong>Liquidato</strong>
                  <span>{formatCurrency(summary.liquidated_amount)}</span>
                </li>
                <li>
                  <strong>Attività aperte</strong>
                  <span>
                    {summary.requirements.length > 0
                      ? `${summary.requirements.length} richieste nel portale`
                      : "Nessuna azione immediata richiesta"}
                  </span>
                </li>
              </ul>
            </SectionCard>

            <SectionCard title="Perito incaricato" eyebrow="Contatto" accent="gold">
              {summary.expert.full_name ? (
                <div className="expert-summary">
                  <p className="stack-line">
                    <strong>{summary.expert.full_name}</strong>
                  </p>
                  <p className="stack-line">{summary.expert.job_title ?? "Perito incaricato"}</p>
                  {summary.expert.email ? <p className="stack-line">{summary.expert.email}</p> : null}
                  {summary.expert.phone_number ? (
                    <p className="stack-line">{summary.expert.phone_number}</p>
                  ) : null}
                  <p className="stack-line">
                    Disponibile ora: {summary.expert.is_available_now ? "Si" : "No"}
                  </p>
                  {summary.expert.availability_note ? (
                    <p className="support-copy">{summary.expert.availability_note}</p>
                  ) : null}
                  {summary.chat_enabled ? (
                    <Link href="/claim/chat" className="primary-link">
                      Apri messaggi
                    </Link>
                  ) : null}
                </div>
              ) : (
                <p>Il perito non è ancora stato assegnato.</p>
              )}
            </SectionCard>

            <SectionCard title="Prossimi passaggi" eyebrow="Da fare" accent="green">
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
            </SectionCard>

            <SectionCard title="Ultimi aggiornamenti" eyebrow="Timeline" accent="ink">
              <ul className="plain-list">
                {timeline.slice(0, 5).map((event) => (
                  <li key={event.id}>
                    <strong>{event.label}</strong>
                    <span>{formatDateTime(event.event_time)}</span>
                    {event.description ? <span>{event.description}</span> : null}
                  </li>
                ))}
              </ul>
            </SectionCard>
          </div>
        </>
      ) : null}
    </div>
  );
}
