"use client";

import Link from "next/link";
import { startTransition, useState } from "react";

import { ClaimPageHeader, SessionMissingState } from "@/components/claim-page-primitives";
import { SectionCard } from "@/components/section-card";
import { usePortalClaimData } from "@/components/use-portal-claim-data";
import { createPortalMessage } from "@/lib/api";
import { formatDateTime } from "@/lib/claim-ui";

export function ClaimChatPage() {
  const { error, isLoading, messages, refresh, session, setError, summary } = usePortalClaimData();
  const [chatMessage, setChatMessage] = useState("");
  const [chatResult, setChatResult] = useState<string | null>(null);

  if (!session) {
    return <SessionMissingState />;
  }

  if (!summary) {
    return <p className="feedback">Caricamento sezione messaggi...</p>;
  }

  return (
    <div className="dashboard-shell">
      <ClaimPageHeader
        eyebrow="Messaggi"
        title="Contatta il perito"
        description="Quando il perito è disponibile puoi usare questa sezione per inviare messaggi instradati nella chat interna dello studio."
        summary={summary}
      >
        <Link href="/claim" className="ghost-button">
          Torna alla dashboard
        </Link>
      </ClaimPageHeader>

      {isLoading ? <p className="feedback">Caricamento dati...</p> : null}
      {error ? <p className="feedback feedback--error">{error}</p> : null}

      <div className="workspace-grid">
        <SectionCard title="Conversazione" eyebrow="Chat" accent="ink">
          <div className="chat-stream">
            {messages.map((message) => (
              <article key={message.id} className={`chat-bubble chat-bubble--${message.author_type}`}>
                <p>{message.body_text}</p>
                <span>{formatDateTime(message.created_at)}</span>
              </article>
            ))}
          </div>
        </SectionCard>

        <SectionCard title="Nuovo messaggio" eyebrow="Invio" accent="green">
          <p className="support-copy">
            Perito assegnato: <strong>{summary.expert.full_name ?? "non ancora assegnato"}</strong>
          </p>
          <div className="mini-form">
            <label>
              Messaggio
              <textarea
                value={chatMessage}
                onChange={(event) => setChatMessage(event.target.value)}
                placeholder="Scrivi qui il messaggio da inviare..."
              />
            </label>
            <button
              type="button"
              onClick={() => {
                if (!chatMessage.trim()) {
                  setChatResult("Inserisci un messaggio prima di inviare.");
                  return;
                }
                startTransition(() => {
                  void (async () => {
                    try {
                      await createPortalMessage(session, { bodyText: chatMessage }, summary.claim_id);
                      setChatMessage("");
                      setChatResult("Messaggio inviato e instradato al team.");
                      await refresh(summary.claim_id);
                    } catch (requestError) {
                      setError(
                        requestError instanceof Error
                          ? requestError.message
                          : "Invio messaggio non riuscito."
                      );
                    }
                  })();
                });
              }}
            >
              Invia messaggio
            </button>
          </div>
          {chatResult ? <p className="feedback">{chatResult}</p> : null}
        </SectionCard>
      </div>
    </div>
  );
}
