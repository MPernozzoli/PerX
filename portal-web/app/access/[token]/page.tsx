"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { exchangePortalToken } from "@/lib/api";
import { PortalShell } from "@/components/portal-shell";
import { setStoredPortalSession } from "@/lib/session";

export default function AccessTokenPage() {
  const params = useParams<{ token: string }>();
  const router = useRouter();
  const [status, setStatus] = useState("Validazione link in corso...");
  const [error, setError] = useState<string | null>(null);
  const token = typeof params?.token === "string" ? params.token : "";

  useEffect(() => {
    if (!token) {
      setError("Il link non contiene un token valido.");
      return;
    }

    let active = true;

    void (async () => {
      try {
        const session = await exchangePortalToken(token);
        if (!active) {
          return;
        }
        setStoredPortalSession(session);
        setStatus("Sessione attivata. Reindirizzamento alla dashboard...");
        router.replace("/claim");
      } catch (requestError) {
        if (!active) {
          return;
        }
        setError(
          requestError instanceof Error
            ? requestError.message
            : typeof requestError === "string"
              ? requestError
              : "Il link non e piu valido o e scaduto."
        );
      }
    })();

    return () => {
      active = false;
    };
  }, [router, token]);

  return (
    <PortalShell centered>
      <section className="entry-card entry-card--narrow">
        <div className="entry-card__header">
          <p className="entry-card__eyebrow">Magic link</p>
          <h1>Accesso al sinistro</h1>
          <p>{error ?? status}</p>
        </div>
        {error ? (
          <Link href="/" className="primary-link">
            Richiedi un nuovo accesso
          </Link>
        ) : null}
      </section>
    </PortalShell>
  );
}
