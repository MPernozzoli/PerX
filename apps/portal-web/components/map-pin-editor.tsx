"use client";

import { useRef, useState } from "react";
import type { KeyboardEvent, PointerEvent } from "react";

type MapPinEditorProps = {
  latitude: number | null;
  longitude: number | null;
  disabled?: boolean;
  onChange: (nextLatitude: number, nextLongitude: number) => void;
};

const DEFAULT_LATITUDE = 41.9028;
const DEFAULT_LONGITUDE = 12.4964;
const LATITUDE_SPAN = 0.008;
const LONGITUDE_SPAN = 0.012;

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

export function MapPinEditor({
  latitude,
  longitude,
  disabled = false,
  onChange
}: MapPinEditorProps) {
  const surfaceRef = useRef<HTMLDivElement | null>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [viewportCenter, setViewportCenter] = useState(() => ({
    latitude: latitude ?? DEFAULT_LATITUDE,
    longitude: longitude ?? DEFAULT_LONGITUDE
  }));

  const markerLatitude = latitude ?? viewportCenter.latitude;
  const markerLongitude = longitude ?? viewportCenter.longitude;
  const relativeX = clamp(
    0.5 + (markerLongitude - viewportCenter.longitude) / LONGITUDE_SPAN,
    0.04,
    0.96
  );
  const relativeY = clamp(
    0.5 - (markerLatitude - viewportCenter.latitude) / LATITUDE_SPAN,
    0.04,
    0.96
  );

  function updateFromPoint(clientX: number, clientY: number) {
    const surface = surfaceRef.current;
    if (!surface) {
      return;
    }

    const bounds = surface.getBoundingClientRect();
    const normalizedX = clamp((clientX - bounds.left) / bounds.width, 0, 1);
    const normalizedY = clamp((clientY - bounds.top) / bounds.height, 0, 1);
    const nextLongitude =
      viewportCenter.longitude + (normalizedX - 0.5) * LONGITUDE_SPAN;
    const nextLatitude =
      viewportCenter.latitude - (normalizedY - 0.5) * LATITUDE_SPAN;

    onChange(Number(nextLatitude.toFixed(6)), Number(nextLongitude.toFixed(6)));
  }

  function handlePointerDown(event: PointerEvent<HTMLDivElement>) {
    if (disabled) {
      return;
    }
    event.currentTarget.setPointerCapture(event.pointerId);
    setIsDragging(true);
    updateFromPoint(event.clientX, event.clientY);
  }

  function handlePointerMove(event: PointerEvent<HTMLDivElement>) {
    if (disabled || !isDragging) {
      return;
    }
    updateFromPoint(event.clientX, event.clientY);
  }

  function handlePointerUp(event: PointerEvent<HTMLDivElement>) {
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    setIsDragging(false);
  }

  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (disabled) {
      return;
    }

    const latitudeStep = LATITUDE_SPAN / 20;
    const longitudeStep = LONGITUDE_SPAN / 20;
    let nextLatitude = markerLatitude;
    let nextLongitude = markerLongitude;

    if (event.key === "ArrowUp") {
      nextLatitude += latitudeStep;
    } else if (event.key === "ArrowDown") {
      nextLatitude -= latitudeStep;
    } else if (event.key === "ArrowLeft") {
      nextLongitude -= longitudeStep;
    } else if (event.key === "ArrowRight") {
      nextLongitude += longitudeStep;
    } else {
      return;
    }

    event.preventDefault();
    onChange(Number(nextLatitude.toFixed(6)), Number(nextLongitude.toFixed(6)));
  }

  return (
    <div className={`inspection-map${disabled ? " inspection-map--disabled" : ""}`}>
      <div
        ref={surfaceRef}
        tabIndex={disabled ? -1 : 0}
        role="application"
        aria-label="Mappa di posizionamento sopralluogo"
        className="inspection-map__surface"
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerLeave={handlePointerUp}
        onKeyDown={handleKeyDown}
      >
        <div className="inspection-map__grid" />
        <div className="inspection-map__ring inspection-map__ring--primary" />
        <div className="inspection-map__ring inspection-map__ring--secondary" />
        <div
          className={`inspection-map__pin${isDragging ? " inspection-map__pin--dragging" : ""}`}
          style={{
            left: `${relativeX * 100}%`,
            top: `${relativeY * 100}%`
          }}
        >
          <span />
        </div>
        <div className="inspection-map__overlay">
          <strong>Punto di incontro con il tecnico</strong>
          <span>Posiziona il pin sull&apos;ingresso o sul punto esatto di arrivo.</span>
        </div>
      </div>

      <div className="inspection-map__footer">
        <p className="inspection-map__coords">
          {markerLatitude.toFixed(6)}, {markerLongitude.toFixed(6)}
        </p>
        <button
          type="button"
          className="ghost-button"
          disabled={disabled}
          onClick={() =>
            setViewportCenter({
              latitude: markerLatitude,
              longitude: markerLongitude
            })
          }
        >
          Centra sul pin
        </button>
      </div>
    </div>
  );
}
