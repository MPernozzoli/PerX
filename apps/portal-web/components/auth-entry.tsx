"use client";

import Link from "next/link";
import { startTransition, useEffect, useRef, useState } from "react";

import { startPortalAuth } from "@/lib/api";
import { getStoredPortalSession } from "@/lib/session";
import type { PortalAuthStartResponse } from "@/lib/types";

function LockIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <rect x="4" y="11" width="16" height="10" rx="2" />
      <path d="M8 11V7a4 4 0 0 1 8 0v4" />
    </svg>
  );
}

function ShieldIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M12 3l8 3v6c0 5-3.5 8.5-8 9-4.5-.5-8-4-8-9V6l8-3z" />
    </svg>
  );
}

function MailIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="M3 7l9 6 9-6" />
    </svg>
  );
}

function ArrowRightIcon({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M5 12h14M13 6l6 6-6 6" />
    </svg>
  );
}

function ArrowLeftIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M19 12H5M11 6l-6 6 6 6" />
    </svg>
  );
}

type Stage = "form" | "sent" | "result";

export function AuthEntry() {
  const [claimReference, setClaimReference] = useState("");
  const [taxCode, setTaxCode] = useState("");
  const [stage, setStage] = useState<Stage>("form");
  const [isPending, setIsPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<PortalAuthStartResponse | null>(null);
  const [hasActiveSession, setHasActiveSession] = useState(false);
  const claimInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    setHasActiveSession(Boolean(getStoredPortalSession()));
    claimInputRef.current?.focus();
  }, []);

  async function handleSubmit() {
    if (!claimReference) return;
    setIsPending(true);
    setError(null);

    try {
      const response = await startPortalAuth({
        claimReference,
        taxCode,
        fullName: "",
        phoneNumber: ""
      });
      setResult(response);
      setStage("result");
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Non è stato possibile avviare l'accesso."
      );
    } finally {
      setIsPending(false);
    }
  }

  return (
    <main className="canvas">
      <section className="hero">
        {/* Colonna sinistra — copia editoriale */}
        <div className="hero__copy">
          <div className="hero__meta">
            <div className="eyebrow eyebrow--accent">Portale assicurati</div>
            <span className="caption">v 4.2</span>
          </div>

          <h1 className="h-display">
            La tua pratica,<br />
            <em>seguita con cura.</em>
          </h1>

          <p className="lede">
            Tutto il percorso del sinistro in un solo posto: stato della pratica,
            documenti, sopralluogo, coordinate bancarie e firma finale.
            Nessun call center, nessun modulo cartaceo.
          </p>

          <blockquote className="hero__quote">
            «Un sinistro è un momento delicato. Il portale serve a renderlo
            comprensibile, lineare e ben documentato.»
            <footer style={{ marginTop: 10, fontStyle: "normal", fontSize: 12, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--ink-3)" }}>
              Studio peritale · responsabile clienti
            </footer>
          </blockquote>

          <div className="hero__highlights">
            <div className="hero__highlight">
              <div className="hero__highlight-num">01</div>
              <div>
                <div className="hero__highlight-title">Accesso senza credenziali</div>
                <div className="hero__highlight-desc">
                  Riferimento sinistro + link di accesso via email. Niente password da ricordare.
                </div>
              </div>
            </div>
            <div className="hero__highlight">
              <div className="hero__highlight-num">02</div>
              <div>
                <div className="hero__highlight-title">Trasparenza completa</div>
                <div className="hero__highlight-desc">
                  Vedi le stesse informazioni che ha il perito incaricato della tua pratica.
                </div>
              </div>
            </div>
            <div className="hero__highlight">
              <div className="hero__highlight-num">03</div>
              <div>
                <div className="hero__highlight-title">Procedure guidate</div>
                <div className="hero__highlight-desc">
                  Documenti, sopralluogo e firma seguono un percorso semplice, passo per passo.
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Colonna destra — card di accesso */}
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div className="card card--paper-elev" style={{ borderColor: "var(--ink)", padding: 32 }}>
            {stage === "form" && (
              <>
                <div className="row row--between" style={{ marginBottom: 24 }}>
                  <div className="eyebrow">Accesso pratica</div>
                  <span className="caption row" style={{ gap: 6 }}>
                    <LockIcon /> Sessione sicura
                  </span>
                </div>

                <h2 className="h2" style={{ marginBottom: 8 }}>Apri la tua pratica</h2>
                <p className="body-text" style={{ marginTop: 0, marginBottom: 24 }}>
                  Inserisci il riferimento ricevuto via email o SMS. Riceverai un codice
                  di conferma per accedere in sicurezza.
                </p>

                <form
                  className="col"
                  style={{ gap: 16 }}
                  onSubmit={(event) => {
                    event.preventDefault();
                    startTransition(() => { void handleSubmit(); });
                  }}
                >
                  <label className="field">
                    <span className="field__label">Riferimento sinistro</span>
                    <input
                      ref={claimInputRef}
                      className="input input--mono"
                      placeholder="PX-2026-00421"
                      value={claimReference}
                      onChange={(e) => setClaimReference(e.target.value.toUpperCase())}
                    />
                    <span className="field__hint">
                      Formato PX-anno-numero, presente nella mail di benvenuto.
                    </span>
                  </label>

                  <label className="field">
                    <span className="field__label">Codice fiscale</span>
                    <input
                      className="input input--mono"
                      placeholder="MRCLNE85T48F205Z"
                      value={taxCode}
                      onChange={(e) => setTaxCode(e.target.value.toUpperCase())}
                    />
                    <span className="field__hint">
                      Verifichiamo che il riferimento corrisponda.
                    </span>
                  </label>

                  <button
                    type="submit"
                    className="btn btn--primary btn--lg btn--block"
                    disabled={isPending || !claimReference}
                  >
                    {isPending ? "Richiesta in corso…" : "Richiedi codice di accesso"}
                    {!isPending && <ArrowRightIcon />}
                  </button>

                  <div className="caption" style={{ textAlign: "center" }}>
                    Non trovi il riferimento?{" "}
                    <a href="mailto:assistenza@perx.it" className="link">Scrivici</a>
                  </div>
                </form>

                {error ? (
                  <p className="feedback feedback--error" style={{ marginTop: 16 }}>{error}</p>
                ) : null}

                {hasActiveSession ? (
                  <div style={{ marginTop: 16, paddingTop: 16, borderTop: "1px solid var(--line-soft)" }}>
                    <Link href="/claim" className="btn btn--ghost btn--block">
                      Riapri la sessione attiva <ArrowRightIcon size={14} />
                    </Link>
                  </div>
                ) : null}
              </>
            )}

            {stage === "sent" && (
              <div style={{ padding: "24px 0", textAlign: "center" }}>
                <div style={{
                  width: 56,
                  height: 56,
                  margin: "0 auto 16px",
                  border: "1px solid var(--line)",
                  borderRadius: "var(--r-md)",
                  display: "grid",
                  placeItems: "center",
                  color: "var(--ink-3)"
                }}>
                  <MailIcon />
                </div>
                <h3 className="h3" style={{ marginBottom: 8 }}>Invio del codice in corso…</h3>
                <p className="body-text" style={{ margin: 0 }}>
                  Stiamo inviando un SMS al numero registrato in pratica.
                </p>
              </div>
            )}

            {stage === "result" && result ? (
              <>
                <div className="eyebrow" style={{ marginBottom: 16 }}>Richiesta inviata</div>
                <div className="feedback feedback--success" style={{ marginBottom: 16 }}>
                  <p style={{ margin: 0 }}>
                    Stato: <strong>{result.status}</strong>
                  </p>
                  {result.masked_destination ? (
                    <p style={{ margin: "6px 0 0" }}>Destinazione: {result.masked_destination}</p>
                  ) : null}
                  {result.preview_magic_link_url ? (
                    <p style={{ margin: "6px 0 0" }}>
                      Anteprima sviluppo:{" "}
                      <a href={result.preview_magic_link_url} className="link">
                        {result.preview_magic_link_url}
                      </a>
                    </p>
                  ) : null}
                </div>
                <button
                  className="btn btn--quiet btn--sm"
                  onClick={() => { setStage("form"); setResult(null); }}
                >
                  <ArrowLeftIcon /> Modifica i dati
                </button>
              </>
            ) : null}
          </div>

          <div className="caption" style={{ padding: "0 8px", display: "flex", alignItems: "center", gap: 8 }}>
            <ShieldIcon />
            <span>Connessione cifrata · I dati restano nel perimetro della compagnia assicurativa.</span>
          </div>
        </div>
      </section>
    </main>
  );
}
