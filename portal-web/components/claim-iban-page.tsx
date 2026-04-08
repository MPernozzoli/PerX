"use client";

import Link from "next/link";
import { startTransition, useEffect, useState } from "react";

import { ClaimPageHeader, SessionMissingState } from "@/components/claim-page-primitives";
import { SectionCard } from "@/components/section-card";
import { usePortalClaimData } from "@/components/use-portal-claim-data";
import { getIbanSummary } from "@/lib/claim-ui";
import { submitBankAccount } from "@/lib/api";
import type { PortalBankAccountSubmission } from "@/lib/types";

export function ClaimIbanPage() {
  const { error, isLoading, refresh, session, setError, summary } = usePortalClaimData();
  const [iban, setIban] = useState("");
  const [bankResult, setBankResult] = useState<PortalBankAccountSubmission | null>(null);
  const [isEditing, setIsEditing] = useState(false);

  useEffect(() => {
    if (!summary?.iban_value_masked) {
      setIsEditing(true);
    }
  }, [summary?.iban_value_masked]);

  if (!session) {
    return <SessionMissingState />;
  }

  if (!summary) {
    return <p className="feedback">Caricamento sezione IBAN...</p>;
  }

  const ibanSummary = getIbanSummary(summary);

  return (
    <div className="dashboard-shell">
      <ClaimPageHeader
        eyebrow="IBAN"
        title={ibanSummary.title}
        description={ibanSummary.description}
        summary={summary}
      >
        <Link href="/claim" className="ghost-button">
          Torna alla dashboard
        </Link>
      </ClaimPageHeader>

      {isLoading ? <p className="feedback">Caricamento dati...</p> : null}
      {error ? <p className="feedback feedback--error">{error}</p> : null}

      <div className="workspace-grid">
        <SectionCard title="Coordinate bancarie" eyebrow="Liquidazione" accent="green">
          {!summary.iban_value_masked ? (
            <div className="process-panel">
              <div className="process-panel__intro">
                <strong>IBAN necessario per proseguire</strong>
                <p>
                  Per i sinistri FE l&apos;IBAN deve essere intestato al contraente di polizza. Senza
                  questo dato la pratica non può procedere verso la fase economica.
                </p>
              </div>
            </div>
          ) : (
            <button
              type="button"
              className="inline-toggle-card"
              onClick={() => setIsEditing((current) => !current)}
            >
              <span>IBAN inserito</span>
              <strong>{summary.iban_value_masked}</strong>
              <small>{isEditing ? "Chiudi dettaglio" : "Apri dettaglio e modifica"}</small>
            </button>
          )}

          <p className="support-copy">
            Contraente di polizza: <strong>{summary.contraente_name ?? "non indicato"}</strong>
          </p>

          {isEditing ? (
            <div className="mini-form">
              <label>
                IBAN
                <input
                  value={iban}
                  onChange={(event) => setIban(event.target.value)}
                  placeholder="IT60X0542811101000000123456"
                />
              </label>
              <button
                type="button"
                onClick={() => {
                  startTransition(() => {
                    void (async () => {
                      try {
                        const response = await submitBankAccount(
                          session,
                          {
                            iban
                          },
                          summary.claim_id
                        );
                        setBankResult(response);
                        setIban("");
                        setIsEditing(false);
                        await refresh(summary.claim_id);
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
          ) : null}

          <p className="support-copy">
            Nota: in questa fase puoi indicare solo l&apos;IBAN del contraente. TODO: estendere il
            flusso per altre tipologie di sinistro con più intestatari e più coordinate.
          </p>

          {bankResult ? (
            <div className="feedback">
              <p>Esito: {bankResult.validation.is_valid ? "IBAN valido" : "IBAN non valido"}</p>
              <p>IBAN normalizzato: {bankResult.validation.normalized_iban}</p>
              {bankResult.validation.abi ? <p>ABI: {bankResult.validation.abi}</p> : null}
              {bankResult.validation.cab ? <p>CAB: {bankResult.validation.cab}</p> : null}
            </div>
          ) : null}
        </SectionCard>

        <SectionCard title="Perché serve" eyebrow="Informazioni" accent="ink">
          <ul className="plain-list">
            <li>
              <strong>Dato obbligatorio</strong>
              <span>Il portale lo richiede per permettere l&apos;avanzamento verso la liquidazione.</span>
            </li>
            <li>
              <strong>Intestazione</strong>
              <span>L&apos;IBAN deve essere intestato al contraente di polizza.</span>
            </li>
            <li>
              <strong>Modifica</strong>
              <span>Se è già presente, puoi aprire il dettaglio e aggiornarlo dalla stessa sezione.</span>
            </li>
          </ul>
        </SectionCard>
      </div>
    </div>
  );
}
