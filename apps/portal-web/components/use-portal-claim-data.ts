"use client";

import { useEffect, useState } from "react";

import {
  getInspectionSchedulingOverview,
  getPortalClaimSummaryForClaim,
  getPortalDocuments,
  getPortalTimeline,
  listAccessibleClaims,
  listPortalMessages
} from "@/lib/api";
import {
  clearStoredPortalSession,
  getStoredPortalActiveClaimId,
  getStoredPortalSession,
  setStoredPortalActiveClaimId
} from "@/lib/session";
import type {
  PortalAccessibleClaim,
  PortalClaimSummary,
  PortalDocument,
  PortalInspectionSchedulingOverview,
  PortalMessage,
  PortalSession,
  PortalTimelineEvent
} from "@/lib/types";

export function usePortalClaimData() {
  const [session, setSession] = useState<PortalSession | null>(null);
  const [accessibleClaims, setAccessibleClaims] = useState<PortalAccessibleClaim[]>([]);
  const [summary, setSummary] = useState<PortalClaimSummary | null>(null);
  const [timeline, setTimeline] = useState<PortalTimelineEvent[]>([]);
  const [documents, setDocuments] = useState<PortalDocument[]>([]);
  const [messages, setMessages] = useState<PortalMessage[]>([]);
  const [inspectionOverview, setInspectionOverview] =
    useState<PortalInspectionSchedulingOverview | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function refreshPortalData(currentSession: PortalSession, claimId: string) {
    setIsLoading(true);
    setError(null);

    try {
      const [
        nextAccessibleClaims,
        nextSummary,
        nextTimeline,
        nextDocuments,
        nextMessages,
        nextInspectionOverview
      ] = await Promise.all([
        listAccessibleClaims(currentSession),
        getPortalClaimSummaryForClaim(currentSession, claimId),
        getPortalTimeline(currentSession, claimId),
        getPortalDocuments(currentSession, claimId),
        listPortalMessages(currentSession, claimId),
        getInspectionSchedulingOverview(currentSession, claimId)
      ]);

      setAccessibleClaims(nextAccessibleClaims);
      setSummary(nextSummary);
      setTimeline(nextTimeline);
      setDocuments(nextDocuments);
      setMessages(nextMessages.items);
      setInspectionOverview(nextInspectionOverview);
      setStoredPortalActiveClaimId(claimId);
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Impossibile caricare i dati del portale."
      );
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    const storedSession = getStoredPortalSession();
    setSession(storedSession);
    if (!storedSession) {
      setIsLoading(false);
      return;
    }

    const activeClaimId = getStoredPortalActiveClaimId() ?? storedSession.claimId;
    void refreshPortalData(storedSession, activeClaimId);
  }, []);

  return {
    session,
    accessibleClaims,
    summary,
    timeline,
    documents,
    messages,
    inspectionOverview,
    isLoading,
    error,
    setError,
    refresh: async (claimId?: string) => {
      if (!session) {
        return;
      }
      await refreshPortalData(session, claimId ?? summary?.claim_id ?? session.claimId);
    },
    switchClaim: async (claimId: string) => {
      if (!session) {
        return;
      }
      await refreshPortalData(session, claimId);
    },
    signOut: () => {
      clearStoredPortalSession();
      window.location.href = "/";
    }
  };
}
