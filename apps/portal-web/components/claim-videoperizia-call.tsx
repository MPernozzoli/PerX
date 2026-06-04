"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { SessionMissingState } from "@/components/claim-page-primitives";
import { SectionCard } from "@/components/section-card";
import { useInsuredLocationPublisher } from "@/components/use-insured-location-publisher";
import {
  getVideoperiziaSession,
  joinVideoperiziaLobby,
  mintVideoperiziaToken
} from "@/lib/api";
import { getStoredPortalSession } from "@/lib/session";
import type {
  PortalSession,
  PortalVideoperiziaSession,
  PortalVideoperiziaToken
} from "@/lib/types";

// LiveKit React components are loaded lazily on the client only when the
// session goes live, so the initial portal bundle stays small and SSR doesn't
// try to evaluate the wasm-backed livekit-client.
import dynamic from "next/dynamic";

const LiveKitCallStage = dynamic<{
  token: PortalVideoperiziaToken;
}>(() => import("@/components/videoperizia-livekit-stage"), {
  ssr: false,
  loading: () => <p className="claim-section__hint">Inizializzazione videochiamata…</p>
});

const PREP_TIPS = [
  "Trovati in un punto con buona luce — preferibilmente vicino a una finestra.",
  "Connessione stabile (Wi-Fi se possibile) per evitare interruzioni.",
  "Prepara i beni o le aree che dovrai mostrare al perito.",
  "Assicurati di poterti muovere senza ostacoli per inquadrare ciò che serve."
];

const POLL_INTERVAL_MS = 3000;

type ConnectionPhase =
  | "loading"
  | "ready_to_join"
  | "lobby"
  | "live"
  | "ended"
  | "error";

function describePhase(session: PortalVideoperiziaSession | null): ConnectionPhase {
  if (!session) return "ready_to_join";
  switch (session.state) {
    case "scheduled":
      return "ready_to_join";
    case "lobby_open":
      return "lobby";
    case "live":
      return "live";
    case "ended":
    case "aborted":
      return "ended";
    default:
      return "ready_to_join";
  }
}

export function ClaimVideoperiziaCallPage() {
  const [session, setSession] = useState<PortalSession | null>(null);
  const [videoperizia, setVideoperizia] = useState<PortalVideoperiziaSession | null>(null);
  const [token, setToken] = useState<PortalVideoperiziaToken | null>(null);
  const [phase, setPhase] = useState<ConnectionPhase>("loading");
  const [error, setError] = useState<string | null>(null);
  const [isJoining, setIsJoining] = useState(false);

  const lastStateRef = useRef<string | null>(null);

  // Bootstrap: load portal session + current videoperizia session snapshot.
  useEffect(() => {
    const stored = getStoredPortalSession();
    setSession(stored);
    if (!stored) {
      setPhase("loading");
      return;
    }
    (async () => {
      try {
        const current = await getVideoperiziaSession(stored);
        setVideoperizia(current);
        setPhase(describePhase(current));
      } catch (requestError) {
        setError(
          requestError instanceof Error
            ? requestError.message
            : "Impossibile recuperare lo stato della videoperizia."
        );
        setPhase("error");
      }
    })();
  }, []);

  // Poll session state while we're in lobby or live so we react to the perito
  // pressing "Avvia" and to the call ending.
  useEffect(() => {
    if (!session) return;
    if (phase !== "lobby" && phase !== "live") return;
    let cancelled = false;
    const tick = async () => {
      try {
        const next = await getVideoperiziaSession(session);
        if (cancelled) return;
        setVideoperizia(next);
        setPhase(describePhase(next));
      } catch {
        // Network blips during polling are non-fatal; the next tick will retry.
      }
    };
    const id = window.setInterval(tick, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, [session, phase]);

  // Token lifecycle: mint when we enter lobby, refresh when state flips to live
  // (publish grant differs between the two).
  useEffect(() => {
    if (!session) return;
    if (phase !== "lobby" && phase !== "live") return;
    const currentState = videoperizia?.state ?? null;
    if (currentState && lastStateRef.current === currentState && token) {
      return;
    }
    lastStateRef.current = currentState;
    (async () => {
      try {
        const minted = await mintVideoperiziaToken(session);
        setToken(minted);
      } catch (requestError) {
        setError(
          requestError instanceof Error
            ? requestError.message
            : "Impossibile ottenere il token videochiamata."
        );
      }
    })();
  }, [session, phase, videoperizia?.state, token]);

  const handleJoinLobby = useCallback(async () => {
    if (!session) return;
    setIsJoining(true);
    setError(null);
    try {
      const next = await joinVideoperiziaLobby(session, {
        userAgent: typeof navigator !== "undefined" ? navigator.userAgent : null
      });
      setVideoperizia(next);
      setPhase(describePhase(next));
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Impossibile entrare nella videoperizia."
      );
    } finally {
      setIsJoining(false);
    }
  }, [session]);

  if (!session && phase === "loading") {
    return <p className="claim-section__hint">Caricamento…</p>;
  }
  if (!session) {
    return <SessionMissingState />;
  }

  return (
    <div className="claim-section claim-section--videoperizia">
      <SectionCard
        title="Videoperizia"
        subtitle={
          phase === "live"
            ? "Sei in videochiamata con il perito."
            : "Spazio dedicato alla videoperizia del tuo sinistro."
        }
      >
        {error ? <p className="claim-section__error">{error}</p> : null}

        {phase === "ready_to_join" ? (
          <ReadyToJoinView onJoin={handleJoinLobby} isJoining={isJoining} />
        ) : null}

        {phase === "lobby" ? <LobbyView /> : null}

        {phase === "live" && token ? (
          <>
            <GpsConsentBanner enabled={token.can_publish} session={session} />
            <LiveKitCallStage token={token} />
          </>
        ) : null}

        {phase === "ended" ? <EndedView /> : null}
      </SectionCard>
    </div>
  );
}

function ReadyToJoinView({
  onJoin,
  isJoining
}: {
  onJoin: () => void;
  isJoining: boolean;
}) {
  return (
    <div className="videoperizia-pre">
      <p>
        Tra poco entrerai in una sala di attesa virtuale. Quando il perito
        sarà pronto avvierà la videochiamata e lo vedrai apparire qui.
      </p>
      <PrepList />
      <button
        type="button"
        className="primary-button"
        onClick={onJoin}
        disabled={isJoining}
      >
        {isJoining ? "Apertura sala…" : "Sono pronto, entra in sala"}
      </button>
    </div>
  );
}

function LobbyView() {
  return (
    <div className="videoperizia-lobby">
      <p className="videoperizia-lobby__status">
        Sei in attesa che il perito si colleghi. Non chiudere questa pagina.
      </p>
      <PrepList />
      <p className="claim-section__hint">
        Appena il perito avvia la chiamata vedrai e sentirai il suo video qui
        sotto. Ti chiederemo i permessi del microfono e della telecamera in
        quel momento.
      </p>
    </div>
  );
}

function EndedView() {
  return (
    <div className="videoperizia-ended">
      <p>La videoperizia è terminata. Grazie per la collaborazione.</p>
      <p className="claim-section__hint">
        Il perito procederà ora con l’istruttoria. Ti contatteremo per i
        prossimi passi.
      </p>
    </div>
  );
}

function GpsConsentBanner({
  enabled,
  session
}: {
  enabled: boolean;
  session: PortalSession;
}) {
  const { status } = useInsuredLocationPublisher({ session, enabled });
  let statusText = "";
  let statusClass = "";
  switch (status) {
    case "requesting":
      statusText = "richiesta permesso…";
      break;
    case "active":
      statusText = "condivisione attiva";
      statusClass = "videoperizia-gps-consent__status--active";
      break;
    case "denied":
      statusText = "permesso negato — abilita nelle impostazioni del browser";
      statusClass = "videoperizia-gps-consent__status--denied";
      break;
    case "error":
      statusText = "errore nel rilevamento posizione";
      statusClass = "videoperizia-gps-consent__status--denied";
      break;
    default:
      statusText = "in attesa";
  }
  return (
    <div className="videoperizia-gps-consent" role="status">
      <span className="videoperizia-gps-consent__text">
        Condividiamo la tua posizione col perito per verificare che tu sia
        presso l’indirizzo del sinistro.
      </span>
      <span className={statusClass}>{statusText}</span>
    </div>
  );
}

function PrepList() {
  return (
    <ul className="videoperizia-prep">
      {PREP_TIPS.map((tip) => (
        <li key={tip}>{tip}</li>
      ))}
    </ul>
  );
}
