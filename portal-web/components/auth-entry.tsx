"use client";

import Link from "next/link";
import { startTransition, useEffect, useState } from "react";

import { startPortalAuth } from "@/lib/api";
import { getStoredPortalSession } from "@/lib/session";
import type { PortalAuthStartResponse } from "@/lib/types";

export function AuthEntry() {
  const [claimReference, setClaimReference] = useState("");
  const [taxCode, setTaxCode] = useState("");
  const [fullName, setFullName] = useState("");
  const [phoneNumber, setPhoneNumber] = useState("");
  const [isPending, setIsPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<PortalAuthStartResponse | null>(null);
  const [hasActiveSession, setHasActiveSession] = useState(false);

  useEffect(() => {
    setHasActiveSession(Boolean(getStoredPortalSession()));
  }, []);

  async function handleSubmit() {
    setIsPending(true);
    setError(null);

    try {
      const response = await startPortalAuth({
        claimReference,
        taxCode,
        fullName,
        phoneNumber
      });
      setResult(response);
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Non e stato possibile avviare l'accesso."
      );
    } finally {
      setIsPending(false);
    }
  }

  return (
    <div className="auth-shell auth-shell--portal">
      <section className="overview-panel">
        <div className="overview-panel__hero">
          <span className="overview-pill">PerX Assicurati</span>
          <h1>Gestisci il tuo sinistro in un unico punto</h1>
          <p>
            Stato pratica, documentazione, sopralluogo, coordinate bancarie, chat e firma finale:
            il portale raccoglie tutto il percorso dell&apos;assicurato in una sola area.
          </p>
        </div>
        <div className="action-grid">
          <div className="action-card action-card--warm">
            <strong>Accesso diretto</strong>
            <span>In sviluppo puoi entrare dal solo riferimento sinistro.</span>
          </div>
          <div className="action-card action-card--cool">
            <strong>Flussi guidati</strong>
            <span>Documentale e sopralluogo seguono una procedura passo per passo.</span>
          </div>
          <div className="action-card">
            <strong>Chiusura pratica</strong>
            <span>IBAN, importi e firma atto restano sempre consultabili.</span>
          </div>
        </div>
        {hasActiveSession ? (
          <Link href="/claim" className="primary-link">
            Apri la sessione gia attiva
          </Link>
        ) : null}
      </section>

      <section className="entry-card">
        <div className="entry-card__header">
          <p className="entry-card__eyebrow">Accesso</p>
          <h2>Richiedi il link di accesso</h2>
          <p>
            In sviluppo puoi accedere inserendo solo il numero o riferimento sinistro. Il backend
            genera il challenge e mostra l&apos;anteprima del magic link.
          </p>
        </div>

        <form
          className="entry-form"
          onSubmit={(event) => {
            event.preventDefault();
            startTransition(() => {
              void handleSubmit();
            });
          }}
        >
          <label>
            Riferimento sinistro
            <input
              value={claimReference}
              onChange={(event) => setClaimReference(event.target.value)}
              placeholder="PX-2026-00421"
            />
          </label>
          <label>
            Codice fiscale
            <input
              value={taxCode}
              onChange={(event) => setTaxCode(event.target.value)}
              placeholder="Opzionale"
            />
          </label>
          <label>
            Nome e cognome
            <input
              value={fullName}
              onChange={(event) => setFullName(event.target.value)}
              placeholder="Opzionale"
            />
          </label>
          <label>
            Telefono
            <input
              value={phoneNumber}
              onChange={(event) => setPhoneNumber(event.target.value)}
              placeholder="Opzionale"
            />
          </label>
          <button type="submit" disabled={isPending}>
            {isPending ? "Richiesta in corso..." : "Invia richiesta di accesso"}
          </button>
        </form>

        {error ? <p className="feedback feedback--error">{error}</p> : null}
        {result ? (
          <div className="feedback feedback--success">
            <p>
              Stato: <strong>{result.status}</strong>
            </p>
            {result.masked_destination ? <p>Destinazione: {result.masked_destination}</p> : null}
            {result.preview_magic_link_url ? (
              <p>
                Anteprima sviluppo:{" "}
                <a href={result.preview_magic_link_url}>{result.preview_magic_link_url}</a>
              </p>
            ) : null}
          </div>
        ) : null}
      </section>
    </div>
  );
}
