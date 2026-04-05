"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { exchangePortalToken } from "@/lib/api";
import { setStoredPortalSession } from "@/lib/session";

export default function AccessTokenPage({
  params
}: {
  params: { token: string };
}) {
  const router = useRouter();
  const [status, setStatus] = useState("Validazione link in corso...");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    void (async () => {
      try {
        const session = await exchangePortalToken(params.token);
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
            : "Il link non e piu valido o e scaduto."
        );
      }
    })();

    return () => {
      active = false;
    };
  }, [params.token, router]);

  return (
    <main className="app-shell app-shell--centered">
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
    </main>
  );
}
