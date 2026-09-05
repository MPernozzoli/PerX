"use client";

import { useCallback, useEffect, useState } from "react";

import { SessionMissingState } from "@/components/claim-page-primitives";
import { SectionCard } from "@/components/section-card";
import {
  cancelDeletionRequest,
  createDeletionRequest,
  getActiveDeletionRequest,
  getPortalMeNotifications,
  getPortalMePolicy,
  getPortalMeProfile,
  listPortalMeSessions,
  revokePortalMeSession,
  updatePortalMeNotifications,
  updatePortalMeProfile
} from "@/lib/api";
import { getStoredPortalSession } from "@/lib/session";
import type {
  PortalMeDeletionRequest,
  PortalMeNotificationChannel,
  PortalMeNotificationPrefs,
  PortalMePolicy,
  PortalMeProfile,
  PortalMeSessionInfo,
  PortalSession
} from "@/lib/types";

type SectionKey = "dati" | "privacy" | "comunicazioni" | "sicurezza";

const SECTIONS: { key: SectionKey; label: string }[] = [
  { key: "dati", label: "I tuoi dati" },
  { key: "privacy", label: "Informativa" },
  { key: "comunicazioni", label: "Comunicazioni" },
  { key: "sicurezza", label: "Sicurezza" }
];

export function ClaimImpostazioniPage() {
  const [session, setSession] = useState<PortalSession | null>(null);
  const [activeSection, setActiveSection] = useState<SectionKey>("dati");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setSession(getStoredPortalSession());
  }, []);

  if (!session) {
    return <SessionMissingState />;
  }

  return (
    <div className="claim-page">
      <header className="workspace-header-card">
        <div className="workspace-header-card__copy">
          <p className="workspace-header-card__eyebrow">Account</p>
          <h1>Impostazioni e privacy</h1>
          <p>Gestisci i tuoi dati, i consensi, le preferenze di contatto e le sessioni attive.</p>
        </div>
      </header>

      <nav className="claim-section-nav" style={{ marginTop: 16 }}>
        {SECTIONS.map((s) => (
          <button
            key={s.key}
            type="button"
            onClick={() => setActiveSection(s.key)}
            className={`claim-section-nav__link${activeSection === s.key ? " claim-section-nav__link--active" : ""}`}
          >
            {s.label}
          </button>
        ))}
      </nav>

      {error && (
        <p className="feedback feedback--error" style={{ marginTop: 12 }}>
          {error}
        </p>
      )}

      <div style={{ marginTop: 16, display: "grid", gap: 16 }}>
        {activeSection === "dati" && <DatiSection session={session} setError={setError} />}
        {activeSection === "privacy" && <PrivacySection session={session} setError={setError} />}
        {activeSection === "comunicazioni" && <ComunicazioniSection session={session} setError={setError} />}
        {activeSection === "sicurezza" && <SicurezzaSection session={session} setError={setError} />}
      </div>
    </div>
  );
}

// ============================================================================
// Section 1 — I tuoi dati
// ============================================================================

function DatiSection({
  session,
  setError
}: {
  session: PortalSession;
  setError: (msg: string | null) => void;
}) {
  const [profile, setProfile] = useState<PortalMeProfile | null>(null);
  const [isEditing, setIsEditing] = useState(false);
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [isSaving, setIsSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      const data = await getPortalMeProfile(session);
      setProfile(data);
      setEmail(data.email ?? "");
      setPhone(data.phone ?? "");
    } catch (e) {
      setError((e as Error).message);
    }
  }, [session, setError]);

  useEffect(() => {
    void load();
  }, [load]);

  const onSave = async () => {
    setIsSaving(true);
    try {
      const payload: { email?: string; phone?: string } = {};
      if (email && email !== profile?.email) payload.email = email;
      if (phone && phone !== profile?.phone) payload.phone = phone;
      if (Object.keys(payload).length === 0) {
        setIsEditing(false);
        return;
      }
      const updated = await updatePortalMeProfile(session, payload);
      setProfile(updated);
      setEmail(updated.email ?? "");
      setPhone(updated.phone ?? "");
      setIsEditing(false);
      setError(null);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setIsSaving(false);
    }
  };

  if (!profile) {
    return <p className="feedback">Caricamento dati personali…</p>;
  }

  return (
    <SectionCard title="I tuoi dati" eyebrow="GDPR art. 15 — diritto di accesso">
      <p style={{ color: "var(--text-muted, #666)", fontSize: 14 }}>
        Questo è quello che lo studio peritale conserva su di te. Puoi modificare email e telefono;
        il resto (CF, indirizzo, dati di polizza) richiede invece l'intervento dello studio.
      </p>

      <dl className="dl-grid" style={{ display: "grid", gridTemplateColumns: "auto 1fr", gap: "8px 16px", marginTop: 16 }}>
        <dt>Nome</dt><dd>{profile.display_name}</dd>
        {profile.codice_fiscale_masked && (<><dt>Codice fiscale</dt><dd style={{ fontFamily: "monospace" }}>{profile.codice_fiscale_masked}</dd></>)}
        {profile.partita_iva_masked && (<><dt>Partita IVA</dt><dd style={{ fontFamily: "monospace" }}>{profile.partita_iva_masked}</dd></>)}
        {profile.data_nascita && (<><dt>Data di nascita</dt><dd>{profile.data_nascita}</dd></>)}
        {profile.luogo_nascita && (<><dt>Luogo di nascita</dt><dd>{profile.luogo_nascita}</dd></>)}
        {profile.pec && (<><dt>PEC</dt><dd>{profile.pec}</dd></>)}

        <dt>Email</dt>
        <dd>
          {isEditing ? (
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
          ) : (
            profile.email ?? <em>non specificata</em>
          )}
        </dd>

        <dt>Telefono</dt>
        <dd>
          {isEditing ? (
            <input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} />
          ) : (
            profile.phone ?? <em>non specificato</em>
          )}
        </dd>
      </dl>

      <div style={{ marginTop: 16, display: "flex", gap: 8 }}>
        {isEditing ? (
          <>
            <button type="button" onClick={onSave} disabled={isSaving} className="btn btn--primary">
              {isSaving ? "Salvataggio…" : "Salva"}
            </button>
            <button
              type="button"
              onClick={() => {
                setEmail(profile.email ?? "");
                setPhone(profile.phone ?? "");
                setIsEditing(false);
              }}
              className="btn"
            >
              Annulla
            </button>
          </>
        ) : (
          <button type="button" onClick={() => setIsEditing(true)} className="btn">
            Modifica email e telefono
          </button>
        )}
      </div>
    </SectionCard>
  );
}

// ============================================================================
// Section 2 — Privacy
// ============================================================================

function PrivacySection({
  session,
  setError
}: {
  session: PortalSession;
  setError: (msg: string | null) => void;
}) {
  const [policy, setPolicy] = useState<PortalMePolicy | null>(null);
  const [policyError, setPolicyError] = useState<string | null>(null);
  const [deletion, setDeletion] = useState<PortalMeDeletionRequest | null>(null);
  const [showDeletionForm, setShowDeletionForm] = useState(false);
  const [deletionReason, setDeletionReason] = useState("");
  const [policyExpanded, setPolicyExpanded] = useState(false);

  const load = useCallback(async () => {
    try {
      const [p, d] = await Promise.allSettled([
        getPortalMePolicy(session),
        getActiveDeletionRequest(session)
      ]);
      if (p.status === "fulfilled") {
        setPolicy(p.value);
        setPolicyError(null);
      } else {
        setPolicyError("Informativa privacy non ancora pubblicata dallo studio.");
      }
      if (d.status === "fulfilled") setDeletion(d.value);
    } catch (e) {
      setError((e as Error).message);
    }
  }, [session, setError]);

  useEffect(() => {
    void load();
  }, [load]);

  const submitDeletion = async () => {
    try {
      const req = await createDeletionRequest(session, deletionReason || undefined);
      setDeletion(req);
      setShowDeletionForm(false);
      setDeletionReason("");
    } catch (e) {
      setError((e as Error).message);
    }
  };

  const cancelDeletion = async () => {
    if (!deletion) return;
    try {
      await cancelDeletionRequest(session, deletion.id);
      setDeletion(null);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  return (
    <>
      <SectionCard title="Base giuridica del trattamento" eyebrow="GDPR art. 6">
        <p style={{ fontSize: 14 }}>
          Trattiamo i tuoi dati personali per <strong>conto della compagnia assicurativa</strong>{" "}
          al fine di gestire il sinistro coperto dalla tua polizza. La base giuridica è
          l'<strong>esecuzione del contratto</strong> di cui sei parte (art. 6(1)(b) GDPR) ed eventuali{" "}
          <strong>obblighi di legge</strong> applicabili al processo peritale (art. 6(1)(c) GDPR).
        </p>
        <p style={{ fontSize: 14, marginTop: 8 }}>
          Per questo motivo <strong>non è richiesto il tuo consenso</strong>: il trattamento è
          necessario per espletare la pratica. Hai comunque il diritto di essere informato su
          come trattiamo i tuoi dati: l'informativa completa è disponibile qui sotto.
        </p>
      </SectionCard>

      <SectionCard title="Informativa privacy" eyebrow="Documento integrale dello studio">
        {policyError ? (
          <p className="feedback feedback--warn">{policyError}</p>
        ) : policy ? (
          <>
            <p style={{ color: "var(--text-muted, #666)", fontSize: 14 }}>
              Versione {policy.version} · in vigore dal{" "}
              {policy.effective_from
                ? new Date(policy.effective_from).toLocaleDateString("it-IT")
                : ""}
            </p>
            {policy.summary && <p>{policy.summary}</p>}
            <div style={{ marginTop: 12, maxHeight: policyExpanded ? "none" : 280, overflow: "auto", border: "1px solid var(--border, #e5e5e5)", padding: 12, borderRadius: 8, whiteSpace: "pre-wrap", fontSize: 13 }}>
              {policy.content_md}
            </div>
            <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
              <button type="button" className="btn" onClick={() => setPolicyExpanded((v) => !v)}>
                {policyExpanded ? "Riduci" : "Espandi tutto"}
              </button>
            </div>
          </>
        ) : (
          <p className="feedback">Caricamento informativa…</p>
        )}
      </SectionCard>

      <SectionCard title="Eliminazione dei dati" eyebrow="GDPR art. 17 — diritto all'oblio">
        <p style={{ fontSize: 14, color: "var(--text-muted, #666)" }}>
          I dati non possono essere eliminati prima di <strong>5 anni dall'ultimo sinistro chiuso</strong>:
          è il tempo minimo richiesto per garantire la corretta gestione peritale e gli obblighi di legge.
          Puoi comunque inoltrare la richiesta in qualsiasi momento — verrà processata alla scadenza.
        </p>

        {deletion ? (
          <div style={{ marginTop: 12, padding: 12, border: "1px solid var(--border, #e5e5e5)", borderRadius: 8 }}>
            <p>
              Richiesta inoltrata il{" "}
              <strong>{new Date(deletion.requested_at).toLocaleDateString("it-IT")}</strong>
            </p>
            <p>
              Eseguibile a partire dal:{" "}
              <strong>{new Date(deletion.eligible_from).toLocaleDateString("it-IT")}</strong>
            </p>
            <p>Stato: <strong>{deletion.status}</strong></p>
            {deletion.reason && (
              <p style={{ fontStyle: "italic" }}>“{deletion.reason}”</p>
            )}
            <button type="button" className="btn" style={{ marginTop: 8 }} onClick={cancelDeletion}>
              Annulla la richiesta
            </button>
          </div>
        ) : showDeletionForm ? (
          <div style={{ marginTop: 12 }}>
            <label htmlFor="deletion-reason">Motivo (facoltativo)</label>
            <textarea
              id="deletion-reason"
              value={deletionReason}
              onChange={(e) => setDeletionReason(e.target.value)}
              rows={3}
              maxLength={2000}
              style={{ width: "100%", marginTop: 4 }}
            />
            <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
              <button type="button" className="btn btn--primary" onClick={submitDeletion}>
                Conferma richiesta
              </button>
              <button type="button" className="btn" onClick={() => setShowDeletionForm(false)}>
                Indietro
              </button>
            </div>
          </div>
        ) : (
          <button type="button" className="btn" style={{ marginTop: 12 }} onClick={() => setShowDeletionForm(true)}>
            Richiedi eliminazione dei dati
          </button>
        )}
      </SectionCard>

      <SectionCard title="Scarica i tuoi dati" eyebrow="GDPR art. 15 / 20">
        <p style={{ fontSize: 14, color: "var(--text-muted, #666)" }}>
          Ottieni una copia integrale dei tuoi dati in formato JSON. Per motivi di sicurezza
          è richiesta una conferma con OTP via email. La funzione sarà disponibile dopo
          l'attivazione del secondo fattore di autenticazione.
        </p>
        <button type="button" className="btn" disabled style={{ marginTop: 12 }}>
          Scarica i miei dati (in arrivo)
        </button>
      </SectionCard>
    </>
  );
}

// ============================================================================
// Section 3 — Comunicazioni
// ============================================================================

const PREF_CHANNELS: { key: PortalMeNotificationChannel; label: string; flag: keyof PortalMeNotificationPrefs }[] = [
  { key: "email", label: "Email", flag: "channel_email" },
  { key: "whatsapp", label: "WhatsApp", flag: "channel_whatsapp" },
  { key: "sms", label: "SMS", flag: "channel_sms" },
  { key: "push", label: "Push (solo web app installata)", flag: "channel_push" }
];

function ComunicazioniSection({
  session,
  setError
}: {
  session: PortalSession;
  setError: (msg: string | null) => void;
}) {
  const [prefs, setPrefs] = useState<PortalMeNotificationPrefs | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      setPrefs(await getPortalMeNotifications(session));
    } catch (e) {
      setError((e as Error).message);
    }
  }, [session, setError]);

  useEffect(() => {
    void load();
  }, [load]);

  const update = (patch: Partial<PortalMeNotificationPrefs>) => {
    setPrefs((prev) => (prev ? { ...prev, ...patch } : prev));
  };

  const save = async () => {
    if (!prefs) return;
    setIsSaving(true);
    try {
      await updatePortalMeNotifications(session, prefs);
      setError(null);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setIsSaving(false);
    }
  };

  if (!prefs) {
    return <p className="feedback">Caricamento preferenze…</p>;
  }

  return (
    <SectionCard title="Comunicazioni" eyebrow="Come vuoi essere contattato">
      <fieldset style={{ border: 0, padding: 0 }}>
        <legend style={{ fontWeight: 600 }}>Canali abilitati</legend>
        <div style={{ display: "grid", gap: 8, marginTop: 8 }}>
          {PREF_CHANNELS.map((c) => (
            <label key={c.key} style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <input
                type="checkbox"
                checked={Boolean(prefs[c.flag])}
                onChange={(e) => update({ [c.flag]: e.target.checked } as Partial<PortalMeNotificationPrefs>)}
              />
              <span>{c.label}</span>
            </label>
          ))}
        </div>
      </fieldset>

      <fieldset style={{ border: 0, padding: 0, marginTop: 16 }}>
        <legend style={{ fontWeight: 600 }}>Canale preferito</legend>
        <select
          value={prefs.preferred_channel}
          onChange={(e) => update({ preferred_channel: e.target.value as PortalMeNotificationChannel })}
          style={{ marginTop: 8 }}
        >
          <option value="email">Email</option>
          <option value="whatsapp">WhatsApp</option>
          <option value="sms">SMS</option>
          <option value="push">Push</option>
        </select>
      </fieldset>

      <fieldset style={{ border: 0, padding: 0, marginTop: 16 }}>
        <legend style={{ fontWeight: 600 }}>Telefonate dal perito</legend>
        <label style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 8 }}>
          <input
            type="checkbox"
            checked={prefs.allow_phone_calls}
            onChange={(e) => update({ allow_phone_calls: e.target.checked })}
          />
          <span>Disponibile a ricevere telefonate</span>
        </label>
        {prefs.allow_phone_calls && (
          <div style={{ marginTop: 8, display: "flex", gap: 12, alignItems: "center" }}>
            <label>
              Dalle:
              <input
                type="time"
                value={prefs.call_window_start ?? ""}
                onChange={(e) => update({ call_window_start: e.target.value || null })}
                style={{ marginLeft: 6 }}
              />
            </label>
            <label>
              Alle:
              <input
                type="time"
                value={prefs.call_window_end ?? ""}
                onChange={(e) => update({ call_window_end: e.target.value || null })}
                style={{ marginLeft: 6 }}
              />
            </label>
          </div>
        )}
      </fieldset>

      <fieldset style={{ border: 0, padding: 0, marginTop: 16 }}>
        <legend style={{ fontWeight: 600 }}>Non disturbare</legend>
        <p style={{ fontSize: 13, color: "var(--text-muted, #666)" }}>
          Niente push o SMS in questa fascia oraria.
        </p>
        <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
          <label>
            Dalle:
            <input
              type="time"
              value={prefs.quiet_hours_start ?? ""}
              onChange={(e) => update({ quiet_hours_start: e.target.value || null })}
              style={{ marginLeft: 6 }}
            />
          </label>
          <label>
            Alle:
            <input
              type="time"
              value={prefs.quiet_hours_end ?? ""}
              onChange={(e) => update({ quiet_hours_end: e.target.value || null })}
              style={{ marginLeft: 6 }}
            />
          </label>
        </div>
      </fieldset>

      <fieldset style={{ border: 0, padding: 0, marginTop: 16 }}>
        <label style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <input
            type="checkbox"
            checked={prefs.documents_via_email}
            onChange={(e) => update({ documents_via_email: e.target.checked })}
          />
          <span>Inviami anche per email i documenti generati (oltre alla notifica)</span>
        </label>
      </fieldset>

      <div style={{ marginTop: 16 }}>
        <button type="button" className="btn btn--primary" onClick={save} disabled={isSaving}>
          {isSaving ? "Salvataggio…" : "Salva preferenze"}
        </button>
      </div>
    </SectionCard>
  );
}

// ============================================================================
// Section 4 — Sicurezza
// ============================================================================

function SicurezzaSection({
  session,
  setError
}: {
  session: PortalSession;
  setError: (msg: string | null) => void;
}) {
  const [sessions, setSessions] = useState<PortalMeSessionInfo[]>([]);

  const load = useCallback(async () => {
    try {
      setSessions(await listPortalMeSessions(session));
    } catch (e) {
      setError((e as Error).message);
    }
  }, [session, setError]);

  useEffect(() => {
    void load();
  }, [load]);

  const revoke = async (id: string) => {
    try {
      await revokePortalMeSession(session, id);
      setSessions((prev) => prev.filter((s) => s.id !== id));
    } catch (e) {
      setError((e as Error).message);
    }
  };

  return (
    <SectionCard title="Sessioni attive" eyebrow="Da quali dispositivi sei connesso">
      {sessions.length === 0 ? (
        <p style={{ color: "var(--text-muted, #666)" }}>
          Nessuna sessione attiva registrata. (Il tracciamento si attiva al prossimo login.)
        </p>
      ) : (
        <ul style={{ listStyle: "none", padding: 0, display: "grid", gap: 8 }}>
          {sessions.map((s) => (
            <li
              key={s.id}
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                padding: 12,
                border: "1px solid var(--border, #e5e5e5)",
                borderRadius: 8
              }}
            >
              <div>
                <p style={{ margin: 0, fontWeight: 600 }}>
                  {s.device_label ?? s.user_agent ?? "Dispositivo sconosciuto"}
                  {s.is_current && (
                    <span style={{ marginLeft: 8, fontSize: 12, color: "var(--accent, #0a7)" }}>
                      (questo dispositivo)
                    </span>
                  )}
                </p>
                <p style={{ margin: 0, fontSize: 12, color: "var(--text-muted, #666)" }}>
                  {s.ip_address ?? "IP sconosciuto"} · ultimo accesso{" "}
                  {s.last_seen_at
                    ? new Date(s.last_seen_at).toLocaleString("it-IT")
                    : "—"}
                </p>
              </div>
              {!s.is_current && (
                <button type="button" className="btn" onClick={() => revoke(s.id)}>
                  Disconnetti
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
    </SectionCard>
  );
}
