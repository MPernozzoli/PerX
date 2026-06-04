import { supabase } from '@/integrations/supabase/client';

const MAP_KEYS_SESSION_KEY = 'map_keys_session';

export interface MapKeysSession {
  sessionKey: string;
  keys: Record<string, string>;
}

/**
 * Restituisce la sessione map keys (sessionKey + reverse map) da sessionStorage
 * o la ottiene chiamando get-map-keys. Usato da SearchBar, UserRolesManager, ecc.
 * per passare sessionKey alle Edge Function e deoffuscare le risposte.
 */
export async function getMapKeysSession(): Promise<MapKeysSession | null> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) return null;

  try {
    const stored = sessionStorage.getItem(MAP_KEYS_SESSION_KEY);
    if (stored) {
      const parsed = JSON.parse(stored) as MapKeysSession;
      if (parsed?.sessionKey && parsed?.keys && typeof parsed.keys === 'object') return parsed;
    }
  } catch {
    /* ignore */
  }
  sessionStorage.removeItem(MAP_KEYS_SESSION_KEY);

  const { data: keysData, error: keysError } = await supabase.functions.invoke('get-map-keys', {
    headers: { Authorization: `Bearer ${session.access_token}` },
  });
  if (keysError || !keysData?.sessionKey || !keysData?.keys) return null;

  const payload: MapKeysSession = { sessionKey: keysData.sessionKey, keys: keysData.keys };
  sessionStorage.setItem(MAP_KEYS_SESSION_KEY, JSON.stringify(payload));
  return payload;
}

export function clearMapKeysSession(): void {
  sessionStorage.removeItem(MAP_KEYS_SESSION_KEY);
}
