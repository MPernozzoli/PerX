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
    <div className="auth-shell">
      <section className="hero-panel">
        <p className="hero-panel__eyebrow">PerX Assicurati</p>
        <h1>Portale sinistri dedicato all'assicurato</h1>
        <p className="hero-panel__lead">
          Accesso diretto al sinistro, documentazione, chat con il perito, coordinate bancarie e
          firma degli atti in un unico punto.
        </p>
        <div className="hero-panel__pills">
          <span>Magic link</span>
          <span>Dashboard stato pratica</span>
          <span>Documentale guidata</span>
          <span>Firma OTP</span>
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
            Per ora il canale attivo e l&apos;e-mail. Il backend genera gia il challenge e, in
            sviluppo, mostra l&apos;anteprima del magic link.
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
              placeholder="RSSMRA80A01H501Z"
            />
          </label>
          <label>
            Nome e cognome
            <input
              value={fullName}
              onChange={(event) => setFullName(event.target.value)}
              placeholder="Mario Rossi"
            />
          </label>
          <label>
            Telefono
            <input
              value={phoneNumber}
              onChange={(event) => setPhoneNumber(event.target.value)}
              placeholder="+39 333 1234567"
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
