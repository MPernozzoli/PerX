"use client";

import Link from "next/link";
import { startTransition, useEffect, useState } from "react";

import { ClaimPageHeader, SessionMissingState } from "@/components/claim-page-primitives";
import { MapPinEditor } from "@/components/map-pin-editor";
import { SectionCard } from "@/components/section-card";
import { usePortalClaimData } from "@/components/use-portal-claim-data";
import {
  formatDateTime,
  formatInspectionDayLabel
} from "@/lib/claim-ui";
import {
  submitInspectionPreferences,
  updateInspectionLocation
} from "@/lib/api";
import type { PortalInspectionSchedulingOverview } from "@/lib/types";

type InspectionSlotDraft = {
  key: string;
  date: string;
  label: string;
  startTime: string;
  endTime: string;
};

function buildInspectionSlotKey(date: string, label: string) {
  return `${date}::${label}`;
}

function timeLabelFromIso(value: string) {
  return new Date(value).toLocaleTimeString("it-IT", {
    hour: "2-digit",
    minute: "2-digit"
  });
}

function splitTimeRange(
  label: string,
  fallbackStart?: string,
  fallbackEnd?: string
): { startTime: string; endTime: string } {
  const parts = label
    .split(" - ")
    .map((part) => part.trim())
    .filter(Boolean);
  if (parts.length === 2) {
    return {
      startTime: parts[0],
      endTime: parts[1]
    };
  }

  return {
    startTime: fallbackStart ? timeLabelFromIso(fallbackStart) : "09:00",
    endTime: fallbackEnd ? timeLabelFromIso(fallbackEnd) : "11:00"
  };
}

function resolveSelectedInspectionSlots(
  overview: PortalInspectionSchedulingOverview | null,
  selectedKeys: string[]
): InspectionSlotDraft[] {
  if (!overview || selectedKeys.length === 0) {
    return [];
  }

  const lookup = new Map<string, InspectionSlotDraft>();

  for (const day of overview.availability_days) {
    for (const slot of day.slots) {
      const key = buildInspectionSlotKey(slot.date, slot.label);
      const timeRange = splitTimeRange(slot.label, slot.start_at, slot.end_at);
      lookup.set(key, {
        key,
        date: slot.date,
        label: slot.label,
        startTime: timeRange.startTime,
        endTime: timeRange.endTime
      });
    }
  }

  for (const slot of overview.selected_slots) {
    const key = buildInspectionSlotKey(slot.date, slot.label);
    const timeRange = splitTimeRange(slot.label, slot.start_at, slot.end_at);
    lookup.set(key, {
      key,
      date: slot.date,
      label: slot.label,
      startTime: timeRange.startTime,
      endTime: timeRange.endTime
    });
  }

  return selectedKeys
    .map((key) => lookup.get(key))
    .filter((value): value is InspectionSlotDraft => Boolean(value))
    .sort((left, right) => {
      if (left.date === right.date) {
        return left.startTime.localeCompare(right.startTime);
      }
      return left.date.localeCompare(right.date);
    });
}

function formatCoordinateInput(value: number | null | undefined) {
  return typeof value === "number" ? value.toFixed(6) : "";
}

function parseCoordinateInput(value: string) {
  const normalized = value.replace(",", ".").trim();
  if (!normalized) {
    return undefined;
  }
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export function ClaimInspectionPage() {
  const { error, inspectionOverview, isLoading, refresh, session, setError, summary } =
    usePortalClaimData();
  const [inspectionAddressLine, setInspectionAddressLine] = useState("");
  const [inspectionMunicipality, setInspectionMunicipality] = useState("");
  const [inspectionProvince, setInspectionProvince] = useState("");
  const [inspectionRegion, setInspectionRegion] = useState("");
  const [inspectionLatitude, setInspectionLatitude] = useState("");
  const [inspectionLongitude, setInspectionLongitude] = useState("");
  const [inspectionNotes, setInspectionNotes] = useState("");
  const [selectedInspectionSlotKeys, setSelectedInspectionSlotKeys] = useState<string[]>([]);
  const [inspectionResult, setInspectionResult] = useState<string | null>(null);

  useEffect(() => {
    if (!inspectionOverview) {
      return;
    }
    setInspectionAddressLine(inspectionOverview.location.address_line ?? "");
    setInspectionMunicipality(inspectionOverview.location.municipality ?? "");
    setInspectionProvince(inspectionOverview.location.province ?? "");
    setInspectionRegion(inspectionOverview.location.region ?? "");
    setInspectionLatitude(formatCoordinateInput(inspectionOverview.location.latitude));
    setInspectionLongitude(formatCoordinateInput(inspectionOverview.location.longitude));
    setSelectedInspectionSlotKeys(
      inspectionOverview.selected_slots.map((slot) =>
        buildInspectionSlotKey(slot.date, slot.label)
      )
    );
  }, [inspectionOverview]);

  if (!session) {
    return <SessionMissingState />;
  }

  if (!summary) {
    return <p className="feedback">Caricamento sezione sopralluogo...</p>;
  }

  const inspectionEnabled =
    Boolean(summary.inspection_scheduling_enabled) || Boolean(inspectionOverview?.enabled);
  const inspectionLocked = inspectionOverview?.status === "confirmed";
  const hasInspectionAvailability = Boolean(
    inspectionOverview?.availability_days.some((day) => day.slot_count > 0)
  );
  const selectedInspectionSlots = resolveSelectedInspectionSlots(
    inspectionOverview,
    selectedInspectionSlotKeys
  );

  return (
    <div className="dashboard-shell">
      <ClaimPageHeader
        eyebrow="Sopralluogo"
        title="Conferma posizione e preferenze"
        description="Quando il sinistro richiede un sopralluogo, qui confermi il punto di incontro e scegli le finestre orarie disponibili."
        summary={summary}
      >
        <Link href="/claim" className="ghost-button">
          Torna alla dashboard
        </Link>
      </ClaimPageHeader>

      {isLoading ? <p className="feedback">Caricamento dati...</p> : null}
      {error ? <p className="feedback feedback--error">{error}</p> : null}

      {!inspectionEnabled || !inspectionOverview ? (
        <SectionCard title="Sopralluogo" eyebrow="Stato" accent="ink">
          <p>Al momento non ci sono attività di sopralluogo da gestire per questo sinistro.</p>
        </SectionCard>
      ) : (
        <SectionCard title="Fissazione sopralluogo" eyebrow="Operatività" accent="green">
          <div className="inspection-stack">
            <p>{inspectionOverview.instructions}</p>
            {inspectionOverview.pending_confirmation_message ? (
              <p className="feedback feedback--success">
                {inspectionOverview.pending_confirmation_message}
              </p>
            ) : null}
            {inspectionResult ? <p className="feedback">{inspectionResult}</p> : null}
            {inspectionOverview.route_review_deadline ? (
              <p className="feedback">
                Revisione interna in corso fino al{" "}
                {formatDateTime(inspectionOverview.route_review_deadline)}.
              </p>
            ) : null}

            <div className="inspection-layout">
              <div className="mini-form">
                <label>
                  Indirizzo sopralluogo
                  <input
                    value={inspectionAddressLine}
                    onChange={(event) => setInspectionAddressLine(event.target.value)}
                    placeholder="Via, civico, interno"
                    readOnly={inspectionLocked}
                  />
                </label>

                <div className="field-grid field-grid--triple">
                  <label>
                    Comune
                    <input
                      value={inspectionMunicipality}
                      onChange={(event) => setInspectionMunicipality(event.target.value)}
                      placeholder="Comune"
                      readOnly={inspectionLocked}
                    />
                  </label>
                  <label>
                    Provincia
                    <input
                      value={inspectionProvince}
                      onChange={(event) => setInspectionProvince(event.target.value)}
                      placeholder="MI"
                      readOnly={inspectionLocked}
                    />
                  </label>
                  <label>
                    Regione
                    <input
                      value={inspectionRegion}
                      onChange={(event) => setInspectionRegion(event.target.value)}
                      placeholder="Lombardia"
                      readOnly={inspectionLocked}
                    />
                  </label>
                </div>

                <div className="field-grid field-grid--double">
                  <label>
                    Latitudine
                    <input
                      value={inspectionLatitude}
                      onChange={(event) => setInspectionLatitude(event.target.value)}
                      placeholder="45.464200"
                      readOnly={inspectionLocked}
                    />
                  </label>
                  <label>
                    Longitudine
                    <input
                      value={inspectionLongitude}
                      onChange={(event) => setInspectionLongitude(event.target.value)}
                      placeholder="9.190000"
                      readOnly={inspectionLocked}
                    />
                  </label>
                </div>

                <p className="support-copy">
                  Posiziona il pin esattamente all&apos;ingresso o nel punto in cui il tecnico deve
                  arrivare per incontrarti.
                </p>

                {!inspectionLocked ? (
                  <button
                    type="button"
                    onClick={() => {
                      const latitude = parseCoordinateInput(inspectionLatitude);
                      const longitude = parseCoordinateInput(inspectionLongitude);

                      if (!inspectionAddressLine.trim()) {
                        setError("Inserisci o conferma l'indirizzo del sopralluogo.");
                        return;
                      }

                      startTransition(() => {
                        void (async () => {
                          try {
                            await updateInspectionLocation(
                              session,
                              {
                                addressLine: inspectionAddressLine,
                                municipality: inspectionMunicipality,
                                province: inspectionProvince,
                                region: inspectionRegion,
                                latitude,
                                longitude
                              },
                              summary.claim_id
                            );
                            setInspectionResult(
                              "Posizione confermata. Ora puoi selezionare una o più finestre disponibili."
                            );
                            await refresh(summary.claim_id);
                          } catch (requestError) {
                            setError(
                              requestError instanceof Error
                                ? requestError.message
                                : "Aggiornamento posizione non riuscito."
                            );
                          }
                        })();
                      });
                    }}
                  >
                    Conferma posizione
                  </button>
                ) : null}
              </div>

              <MapPinEditor
                key={`inspection-map-${inspectionOverview.location.confirmed_at ?? "draft"}`}
                latitude={parseCoordinateInput(inspectionLatitude) ?? null}
                longitude={parseCoordinateInput(inspectionLongitude) ?? null}
                disabled={inspectionLocked}
                onChange={(nextLatitude, nextLongitude) => {
                  setInspectionLatitude(nextLatitude.toFixed(6));
                  setInspectionLongitude(nextLongitude.toFixed(6));
                }}
              />
            </div>

            <div className="inspection-candidates">
              <div>
                <p className="section-card__eyebrow">CAT di zona</p>
                <h3>Copertura area sopralluogo</h3>
              </div>
              {inspectionOverview.candidate_cats.length > 0 ? (
                <div className="candidate-grid">
                  {inspectionOverview.candidate_cats.map((candidate) => (
                    <article key={candidate.user_id} className="candidate-card">
                      <strong>{candidate.full_name}</strong>
                      <span>{candidate.job_title ?? "CAT"}</span>
                      <span>
                        {candidate.comune}
                        {candidate.provincia ? ` (${candidate.provincia})` : ""}
                      </span>
                      {candidate.email ? <span>{candidate.email}</span> : null}
                      {candidate.phone_number ? <span>{candidate.phone_number}</span> : null}
                      <span>
                        {candidate.is_primary_zone
                          ? "Zona primaria"
                          : candidate.distance_km
                            ? `Supporto a ${candidate.distance_km.toFixed(1)} km`
                            : "Zona secondaria"}
                      </span>
                    </article>
                  ))}
                </div>
              ) : (
                <p className="support-copy">
                  Nessun CAT disponibile sulla base della posizione attuale.
                </p>
              )}
            </div>

            <div className="inspection-availability">
              <div>
                <p className="section-card__eyebrow">Finestre disponibili</p>
                <h3>Seleziona una o più fasce da due ore</h3>
                <p className="support-copy">
                  Mostriamo solo le finestre compatibili con i CAT dell&apos;area e con i sopralluoghi
                  già fissati o in pending.
                </p>
              </div>

              {!inspectionOverview.address_confirmed ? (
                <p className="feedback">
                  Conferma prima posizione e punto di incontro per attivare la selezione delle
                  disponibilità.
                </p>
              ) : null}

              {hasInspectionAvailability ? (
                <div className="inspection-days-grid">
                  {inspectionOverview.availability_days.map((day) => (
                    <article
                      key={day.date}
                      className={`inspection-day-card${
                        !day.is_available ? " inspection-day-card--disabled" : ""
                      }`}
                    >
                      <div className="inspection-day-card__header">
                        <strong>{formatInspectionDayLabel(day.date)}</strong>
                        <span>
                          {day.is_available
                            ? `${day.slot_count} fasce disponibili`
                            : "Nessuna disponibilità"}
                        </span>
                      </div>

                      {day.slots.length > 0 ? (
                        <div className="inspection-slot-grid">
                          {day.slots.map((slot) => {
                            const slotKey = buildInspectionSlotKey(slot.date, slot.label);
                            const isSelected = selectedInspectionSlotKeys.includes(slotKey);

                            return (
                              <button
                                key={slot.id}
                                type="button"
                                className={`inspection-slot-button${
                                  isSelected ? " inspection-slot-button--selected" : ""
                                }`}
                                disabled={!inspectionOverview.address_confirmed || inspectionLocked}
                                onClick={() => {
                                  setSelectedInspectionSlotKeys((current) =>
                                    current.includes(slotKey)
                                      ? current.filter((item) => item !== slotKey)
                                      : [...current, slotKey]
                                  );
                                }}
                              >
                                <strong>{slot.label}</strong>
                                <span>{slot.available_cat_count} CAT compatibili</span>
                              </button>
                            );
                          })}
                        </div>
                      ) : (
                        <p className="support-copy">
                          Questa giornata resta non disponibile per tutti i CAT della zona.
                        </p>
                      )}
                    </article>
                  ))}
                </div>
              ) : (
                <p className="feedback">
                  Nessuna finestra utile rilevata nell&apos;orizzonte corrente di pianificazione.
                </p>
              )}
            </div>

            <div className="inspection-summary-box">
              <div>
                <p className="section-card__eyebrow">Preferenze inviate</p>
                <h3>Finestre selezionate</h3>
              </div>
              {selectedInspectionSlots.length > 0 ? (
                <ul className="plain-list">
                  {selectedInspectionSlots.map((slot) => (
                    <li key={slot.key}>
                      <strong>{formatInspectionDayLabel(slot.date)}</strong>
                      <span>{slot.label}</span>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="support-copy">Non hai ancora selezionato alcuna fascia oraria.</p>
              )}

              {!inspectionLocked ? (
                <div className="mini-form">
                  <label>
                    Note per il sopralluogo
                    <textarea
                      value={inspectionNotes}
                      onChange={(event) => setInspectionNotes(event.target.value)}
                      placeholder="Indicazioni di accesso, piano, citofono, vincoli orari..."
                    />
                  </label>
                  <button
                    type="button"
                    onClick={() => {
                      if (!inspectionOverview.address_confirmed) {
                        setError("Conferma prima la posizione del sopralluogo.");
                        return;
                      }

                      if (selectedInspectionSlots.length === 0) {
                        setError(
                          "Seleziona almeno una fascia oraria prima di inviare le preferenze."
                        );
                        return;
                      }

                      startTransition(() => {
                        void (async () => {
                          try {
                            await submitInspectionPreferences(
                              session,
                              {
                                selectedSlots: selectedInspectionSlots.map((slot) => ({
                                  date: slot.date,
                                  startTime: slot.startTime,
                                  endTime: slot.endTime,
                                  label: slot.label
                                })),
                                notes: inspectionNotes,
                                requestedDurationMinutes: 120
                              },
                              summary.claim_id
                            );
                            setInspectionResult(
                              "Preferenze inviate. Riceverai il messaggio di conferma entro le 24 ore precedenti alla data selezionata."
                            );
                            await refresh(summary.claim_id);
                          } catch (requestError) {
                            setError(
                              requestError instanceof Error
                                ? requestError.message
                                : "Invio preferenze sopralluogo non riuscito."
                            );
                          }
                        })();
                      });
                    }}
                  >
                    Invia preferenze sopralluogo
                  </button>
                </div>
              ) : null}
            </div>
          </div>
        </SectionCard>
      )}
    </div>
  );
}
