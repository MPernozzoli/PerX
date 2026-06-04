"use client";

import Link from "next/link";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";

import { PortalShell } from "@/components/portal-shell";
import { requestPortalOtp, verifyPortalOtp } from "@/lib/api";
import { setStoredPortalSession } from "@/lib/session";

type Stage = "phone" | "otp" | "done";

export default function ClaimPortalEntryPage() {
  const params = useParams<{ ref: string }>();
  const router = useRouter();
  const searchParams = useSearchParams();
  const focus = searchParams?.get("focus");
  const claimReference =
    typeof params?.ref === "string" ? decodeURIComponent(params.ref).toUpperCase() : "";

  const [stage, setStage] = useState<Stage>("phone");
  const [phoneNumber, setPhoneNumber] = useState("");
  const [otpCode, setOtpCode] = useState("");
  const [rememberMe, setRememberMe] = useState(true);
  const [maskedDestination, setMaskedDestination] = useState<string | null>(null);
  const [deliveryChannel, setDeliveryChannel] = useState<string | null>(null);
  const [previewOtp, setPreviewOtp] = useState<string | null>(null);
  const [isPending, setIsPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!claimReference) {
      setError("Riferimento sinistro mancante nel link.");
    }
  }, [claimReference]);

  async function handleRequestOtp(event: React.FormEvent) {
    event.preventDefault();
    if (!phoneNumber || !claimReference) return;
    setIsPending(true);
    setError(null);
    try {
      const response = await requestPortalOtp({
        claimReference,
        phoneNumber,
        channel: "sms"
      });
      setMaskedDestination(response.masked_destination ?? null);
      setDeliveryChannel(response.delivery_channel ?? null);
      setPreviewOtp(response.preview_otp_code ?? null);
      setStage("otp");
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Non è stato possibile inviare il codice."
      );
    } finally {
      setIsPending(false);
    }
  }

  async function handleVerifyOtp(event: React.FormEvent) {
    event.preventDefault();
    if (!otpCode || !claimReference) return;
    setIsPending(true);
    setError(null);
    try {
      const session = await verifyPortalOtp({
        claimReference,
        phoneNumber,
        otpCode,
        rememberMe
      });
      setStoredPortalSession(session);
      setStage("done");
      const focusDestinations: Record<string, string> = {
        atto: "/claim/atto",
        videoperizia: "/claim/videoperizia",
        sopralluogo: "/claim/sopralluogo",
      };
      const destination = (focus && focusDestinations[focus]) || "/claim";
      router.replace(destination);
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Codice OTP non valido."
      );
    } finally {
      setIsPending(false);
    }
  }

  return (
    <PortalShell centered>
      <section className="entry-card entry-card--narrow">
        <div className="entry-card__header">
          <p className="entry-card__eyebrow">Accesso pratica</p>
          <h1>Sinistro {claimReference || "—"}</h1>
          <p>
            {stage === "phone"
              ? "Inserisci il tuo numero di telefono. Riceverai un codice per accedere."
              : `Ti abbiamo inviato un codice ${
                  deliveryChannel === "sms" ? "via SMS" : "via email"
                }${maskedDestination ? ` a ${maskedDestination}` : ""}.`}
          </p>
        </div>

        {stage === "phone" && (
          <form onSubmit={handleRequestOtp} className="col" style={{ gap: 16 }}>
            <label className="field">
              <span className="field__label">Numero di telefono</span>
              <input
                type="tel"
                className="input"
                placeholder="+39 333 1234567"
                value={phoneNumber}
                onChange={(event) => setPhoneNumber(event.target.value)}
                autoFocus
                required
              />
              <span className="field__hint">
                Deve corrispondere al numero comunicato in polizza o al perito.
              </span>
            </label>
            <button
              type="submit"
              className="btn btn--primary btn--lg btn--block"
              disabled={isPending || !phoneNumber || !claimReference}
            >
              {isPending ? "Invio in corso..." : "Invia codice"}
            </button>
          </form>
        )}

        {stage === "otp" && (
          <form onSubmit={handleVerifyOtp} className="col" style={{ gap: 16 }}>
            <label className="field">
              <span className="field__label">Codice OTP</span>
              <input
                type="text"
                inputMode="numeric"
                pattern="[0-9]*"
                maxLength={6}
                className="input input--mono"
                placeholder="123456"
                value={otpCode}
                onChange={(event) => setOtpCode(event.target.value.replace(/\D/g, ""))}
                autoFocus
                required
              />
              {previewOtp && (
                <span className="field__hint">
                  Codice preview (dev): <strong>{previewOtp}</strong>
                </span>
              )}
            </label>
            <label className="field field--inline">
              <input
                type="checkbox"
                checked={rememberMe}
                onChange={(event) => setRememberMe(event.target.checked)}
              />
              <span>Ricordami su questo dispositivo</span>
            </label>
            <button
              type="submit"
              className="btn btn--primary btn--lg btn--block"
              disabled={isPending || otpCode.length < 4}
            >
              {isPending ? "Verifica in corso..." : "Entra nel portale"}
            </button>
            <button
              type="button"
              className="btn btn--ghost btn--block"
              onClick={() => {
                setStage("phone");
                setOtpCode("");
                setPreviewOtp(null);
              }}
            >
              Cambia numero di telefono
            </button>
          </form>
        )}

        {error && (
          <p style={{ color: "var(--danger, #c0392b)", marginTop: 16 }}>{error}</p>
        )}

        <p style={{ marginTop: 24, fontSize: 12, color: "var(--ink-3)" }}>
          Non hai ricevuto il messaggio?{" "}
          <Link href="/" className="primary-link">
            Accedi con un altro metodo
          </Link>
        </p>
      </section>
    </PortalShell>
  );
}
