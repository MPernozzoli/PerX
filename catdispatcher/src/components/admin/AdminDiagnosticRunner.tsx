import { useEffect, useRef } from 'react';
import { useDiagnostics } from '@/contexts/DiagnosticContext';

const DIAGNOSTIC_INTERVAL_MS = 30 * 60 * 1000; // 30 minuti

/**
 * Polling lettura diagnostica da tabella quando in Admin.
 * I dati sono popolati da run-diagnostics (cron server o "Riesegui").
 */
export const AdminDiagnosticRunner = () => {
  const { runDiagnostics } = useDiagnostics();
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    runDiagnostics();

    intervalRef.current = setInterval(() => {
      runDiagnostics();
    }, DIAGNOSTIC_INTERVAL_MS);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [runDiagnostics]);

  return null;
};
