import { useEffect, useState } from 'react';
import { PerXSession, restorePerXSession } from '@/lib/perxApi';

export const useAnonymousAuth = () => {
  const [session, setSession] = useState<PerXSession | null>(null);
  const [loading, setLoading] = useState(true);
  const [requiresLogin, setRequiresLogin] = useState(false);

  useEffect(() => {
    let cancelled = false;

    const initializeAuth = async () => {
      const restored = await restorePerXSession();
      if (cancelled) return;

      setSession(restored);
      setRequiresLogin(!restored);
      setLoading(false);
    };

    initializeAuth();

    return () => {
      cancelled = true;
    };
  }, []);

  return { session, loading, requiresLogin };
};
