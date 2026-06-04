import React, { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { getMapKeysSession, clearMapKeysSession } from '@/lib/mapKeysSession';
import { deobfuscateMapData } from '@/lib/deobfuscateMapData';

export type DiagnosticStatus = 'ok' | 'warning' | 'error';

export interface DiagnosticCheck {
  status: DiagnosticStatus;
  message: string;
  details?: string;
  timestamp: string;
}

export interface SystemDiagnostics {
  session: DiagnosticCheck;
  mapData: DiagnosticCheck;
  geometries: DiagnosticCheck;
  search: DiagnosticCheck;
  database: DiagnosticCheck;
  cache: DiagnosticCheck;
}

export type SystemStatus = 'operational' | 'partial' | 'down' | 'unknown';

interface DiagnosticContextType {
  diagnostics: SystemDiagnostics | null;
  systemStatus: SystemStatus;
  isRunning: boolean;
  lastRun: Date | null;
  isUnderMaintenance: boolean;
  setIsUnderMaintenance: (value: boolean) => void;
  runDiagnostics: (triggerServerRun?: boolean) => Promise<void>;
}

const DiagnosticContext = createContext<DiagnosticContextType | undefined>(undefined);

export const useDiagnostics = () => {
  const context = useContext(DiagnosticContext);
  if (!context) {
    throw new Error('useDiagnostics must be used within a DiagnosticProvider');
  }
  return context;
};

interface DiagnosticProviderProps {
  children: ReactNode;
}

export const DiagnosticProvider: React.FC<DiagnosticProviderProps> = ({ children }) => {
  const [diagnostics, setDiagnostics] = useState<SystemDiagnostics | null>(null);
  const [systemStatus, setSystemStatus] = useState<SystemStatus | 'unknown'>('unknown');
  const [isRunning, setIsRunning] = useState(false);
  const [lastRun, setLastRun] = useState<Date | null>(null);
  const [isUnderMaintenance, setIsUnderMaintenance] = useState(() => {
    const stored = localStorage.getItem('system_under_maintenance');
    return stored === 'true';
  });

  useEffect(() => {
    localStorage.setItem('system_under_maintenance', String(isUnderMaintenance));
  }, [isUnderMaintenance]);

  const calculateSystemStatus = useCallback((diag: SystemDiagnostics, underMaintenance: boolean): SystemStatus => {
    if (underMaintenance) return 'partial';
    const statuses = Object.values(diag).map(check => check.status);
    const errorCount = statuses.filter(s => s === 'error').length;
    const warningCount = statuses.filter(s => s === 'warning').length;
    if (diag.session.status === 'error' || diag.mapData.status === 'error' || diag.geometries.status === 'error') {
      return 'down';
    }
    if (errorCount > 0 || warningCount > 1) return 'partial';
    if (warningCount > 0) return 'partial';
    return 'operational';
  }, []);

  const fetchFromTable = useCallback(async (): Promise<{ result: SystemDiagnostics; created_at: string } | null> => {
    const mapKeys = await getMapKeysSession();
    const body = mapKeys?.sessionKey ? { sessionKey: mapKeys.sessionKey } : {};
    const { data, error } = await supabase.functions.invoke('get-diagnostics', {
      method: 'POST',
      body,
      headers: { Authorization: `Bearer ${(await supabase.auth.getSession()).data.session?.access_token ?? ''}` },
    });

    if (error) {
      console.warn('Errore lettura diagnostica:', error);
      return null;
    }
    if ((data as { code?: string })?.code === 'NEED_MAP_KEYS') {
      clearMapKeysSession();
      const { data: retryData, error: retryError } = await supabase.functions.invoke('get-diagnostics', {
        method: 'POST',
        body: {},
        headers: { Authorization: `Bearer ${(await supabase.auth.getSession()).data.session?.access_token ?? ''}` },
      });
      if (retryError || !retryData) return null;
      const raw = retryData as { result: SystemDiagnostics; created_at: string };
      if (!raw?.result) return null;
      return { result: raw.result, created_at: raw.created_at };
    }
    const raw = mapKeys?.keys && data
      ? (deobfuscateMapData(data, mapKeys.keys) as { result: SystemDiagnostics; created_at: string })
      : (data as { result: SystemDiagnostics; created_at: string });
    if (!raw?.result) return null;
    return { result: raw.result, created_at: raw.created_at };
  }, []);

  const runDiagnostics = useCallback(async (triggerServerRun = false) => {
    setIsRunning(true);
    try {
      if (triggerServerRun) {
        const { data: { session } } = await supabase.auth.getSession();
        if (session?.access_token) {
          const { error } = await supabase.functions.invoke('run-diagnostics', {
            headers: { Authorization: `Bearer ${session.access_token}` },
          });
          if (error) {
            console.error('Errore esecuzione diagnostica server:', error);
          }
        }
      }

      const data = await fetchFromTable();
      if (data) {
        setDiagnostics(data.result);
        setSystemStatus(calculateSystemStatus(data.result, isUnderMaintenance));
        setLastRun(new Date(data.created_at));
      } else {
        setSystemStatus('unknown');
      }
    } catch (error) {
      console.error('Errore diagnostica:', error);
    } finally {
      setIsRunning(false);
    }
  }, [fetchFromTable, calculateSystemStatus, isUnderMaintenance]);

  useEffect(() => {
    runDiagnostics(false);
  }, []);

  useEffect(() => {
    if (diagnostics) {
      setSystemStatus(calculateSystemStatus(diagnostics, isUnderMaintenance));
    }
  }, [isUnderMaintenance, diagnostics, calculateSystemStatus]);

  return (
    <DiagnosticContext.Provider
      value={{
        diagnostics,
        systemStatus,
        isRunning,
        lastRun,
        isUnderMaintenance,
        setIsUnderMaintenance,
        runDiagnostics,
      }}
    >
      {children}
    </DiagnosticContext.Provider>
  );
};
