import { useEffect, useRef } from 'react';
import { getCurrentPerXUser, getPerXAccessToken } from '@/lib/perxApi';

const HEARTBEAT_INTERVAL_MS = 5 * 60 * 1000;

export default function SessionHeartbeat() {
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    const heartbeat = async () => {
      if (!getPerXAccessToken()) return;
      await getCurrentPerXUser().catch(() => undefined);
    };

    heartbeat();
    intervalRef.current = setInterval(heartbeat, HEARTBEAT_INTERVAL_MS);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, []);

  return null;
}
