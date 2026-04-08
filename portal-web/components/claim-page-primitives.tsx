"use client";

import Link from "next/link";
import type { ReactNode } from "react";

import type { PortalAccessibleClaim, PortalClaimSummary } from "@/lib/types";

type ClaimPageHeaderProps = {
  eyebrow: string;
  title: string;
  description: string;
  summary: PortalClaimSummary;
  children?: ReactNode;
};

export function ClaimPageHeader({
  eyebrow,
  title,
  description,
  summary,
  children
}: ClaimPageHeaderProps) {
  return (
    <section className="workspace-header-card">
      <div className="workspace-header-card__copy">
        <p className="workspace-header-card__eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      <div className="workspace-header-card__meta">
        <div className="workspace-meta-card">
          <span>Sinistro</span>
          <strong>{summary.external_ref ?? summary.numero_sinistro ?? summary.claim_id}</strong>
        </div>
        <div className="workspace-meta-card">
          <span>Stato</span>
          <strong>{summary.macro_state.label}</strong>
        </div>
        {children}
      </div>
    </section>
  );
}

export function SessionMissingState() {
  return (
    <div className="empty-state">
      <p className="empty-state__eyebrow">Sessione non disponibile</p>
      <h1>Nessuna sessione portale attiva</h1>
      <p>Apri un magic link o richiedi un nuovo accesso dalla pagina iniziale.</p>
      <Link href="/" className="primary-link">
        Torna all&apos;accesso
      </Link>
    </div>
  );
}

export function ClaimSwitcher({
  claims,
  activeClaimId,
  onSelect
}: {
  claims: PortalAccessibleClaim[];
  activeClaimId?: string;
  onSelect: (claimId: string) => void;
}) {
  if (claims.length <= 1) {
    return null;
  }

  return (
    <section className="claims-overview claims-overview--compact">
      <div className="claims-overview__header">
        <div>
          <p className="status-strip__eyebrow">I tuoi sinistri</p>
          <h2>Seleziona la pratica da consultare</h2>
        </div>
      </div>
      <div className="claims-overview__grid">
        {claims.map((claim) => (
          <button
            key={claim.claim_id}
            type="button"
            className={`claim-switcher-card${
              claim.claim_id === activeClaimId ? " claim-switcher-card--active" : ""
            }`}
            onClick={() => onSelect(claim.claim_id)}
          >
            <span className="claim-switcher-card__eyebrow">
              {claim.external_ref ?? claim.numero_sinistro ?? claim.claim_id}
            </span>
            <strong>{claim.macro_state.label}</strong>
            <span>{claim.compagnia ?? "Compagnia non indicata"}</span>
            <span>
              {claim.has_pending_actions ? "Richiede attenzione" : "Nessuna azione richiesta"}
            </span>
          </button>
        ))}
      </div>
    </section>
  );
}
