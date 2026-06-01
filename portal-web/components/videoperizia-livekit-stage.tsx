"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import {
  LiveKitRoom,
  RoomAudioRenderer,
  VideoConference,
  useRoomContext
} from "@livekit/components-react";
import "@livekit/components-styles";
import { RoomEvent, Track } from "livekit-client";

import type { PortalVideoperiziaToken } from "@/lib/types";

type Props = {
  token: PortalVideoperiziaToken;
};

/**
 * Monta la LiveKit room per il lato assicurato. Quando il backend concede
 * `can_publish=true` (post-Avvia del perito) la chiamata diventa bidirezionale;
 * altrimenti l'utente è in attesa.
 *
 * Sopra alla call montiamo un overlay listener che reagisce ai comandi che
 * arrivano sul data channel da parte del perito (`camera_flip`, `flash_request`,
 * `capture_notice`) — vedi `VideoperiziaRemoteCommandHandler`.
 */
export default function VideoperiziaLiveKitStage({ token }: Props) {
  const connectOpts = useMemo(() => ({ adaptiveStream: true, dynacast: true }), []);

  return (
    <div className="videoperizia-call">
      <LiveKitRoom
        serverUrl={token.livekit_url}
        token={token.token}
        connect
        video={token.can_publish}
        audio={token.can_publish}
        options={connectOpts}
        data-lk-theme="default"
      >
        <VideoConference />
        <RoomAudioRenderer />
        <VideoperiziaRemoteCommandHandler />
      </LiveKitRoom>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Remote commands + GPS publishing
// ---------------------------------------------------------------------------

type RemoteCommand =
  | { type: "camera_flip" }
  | { type: "flash_request"; payload?: { turn_on?: boolean } }
  | { type: "capture_notice" };

function VideoperiziaRemoteCommandHandler() {
  const room = useRoomContext();
  const [flashAlert, setFlashAlert] = useState<{ turnOn: boolean } | null>(null);
  const [captureNotice, setCaptureNotice] = useState(false);
  const captureNoticeTimerRef = useRef<number | null>(null);

  const handleCameraFlip = useCallback(async () => {
    if (!room || !room.localParticipant) return;
    const camPublication = room.localParticipant.getTrackPublication(Track.Source.Camera);
    const camTrack = camPublication?.videoTrack;
    if (!camTrack) return;
    try {
      // Read current facingMode from track settings, flip, and restart.
      const settings = camTrack.mediaStreamTrack.getSettings();
      const next = settings.facingMode === "environment" ? "user" : "environment";
      await camTrack.restartTrack({ facingMode: next });
    } catch (error) {
      console.warn("[videoperizia] camera_flip failed", error);
    }
  }, [room]);

  useEffect(() => {
    if (!room) return;
    const handler = (payload: Uint8Array) => {
      let command: RemoteCommand | null = null;
      try {
        command = JSON.parse(new TextDecoder().decode(payload)) as RemoteCommand;
      } catch {
        return;
      }
      switch (command.type) {
        case "camera_flip":
          void handleCameraFlip();
          break;
        case "flash_request":
          setFlashAlert({ turnOn: command.payload?.turn_on !== false });
          break;
        case "capture_notice":
          setCaptureNotice(true);
          if (captureNoticeTimerRef.current) {
            window.clearTimeout(captureNoticeTimerRef.current);
          }
          captureNoticeTimerRef.current = window.setTimeout(
            () => setCaptureNotice(false),
            2500
          );
          break;
      }
    };
    room.on(RoomEvent.DataReceived, handler);
    return () => {
      room.off(RoomEvent.DataReceived, handler);
      if (captureNoticeTimerRef.current) {
        window.clearTimeout(captureNoticeTimerRef.current);
        captureNoticeTimerRef.current = null;
      }
    };
  }, [room, handleCameraFlip]);

  return (
    <>
      {flashAlert ? (
        <FlashRequestAlert
          turnOn={flashAlert.turnOn}
          onDismiss={() => setFlashAlert(null)}
        />
      ) : null}
      {captureNotice ? <CaptureNoticeBanner /> : null}
    </>
  );
}

function FlashRequestAlert({ turnOn, onDismiss }: { turnOn: boolean; onDismiss: () => void }) {
  return (
    <div className="videoperizia-flash-alert" role="alertdialog" aria-live="assertive">
      <div className="videoperizia-flash-alert__inner">
        <p className="videoperizia-flash-alert__title">
          {turnOn
            ? "Il perito ti chiede di accendere il flash"
            : "Il perito ti chiede di spegnere il flash"}
        </p>
        <p className="videoperizia-flash-alert__body">
          Apri la torcia del tuo dispositivo (sul telefono di solito è nel pannello
          di controllo). Quando hai fatto, tocca conferma.
        </p>
        <button type="button" className="primary-button" onClick={onDismiss}>
          Fatto
        </button>
      </div>
    </div>
  );
}

function CaptureNoticeBanner() {
  return (
    <div className="videoperizia-capture-notice" role="status">
      <span aria-hidden>📸</span>
      <span>Il perito sta scattando una foto</span>
    </div>
  );
}
