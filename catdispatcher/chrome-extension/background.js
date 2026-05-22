/**
 * Background Service Worker per ACT CAT Dispatcher
 * 
 * Gestisce:
 * - Autenticazione utente via Google OAuth
 * - Chiamate API cross-origin verso Supabase
 * - Orchestrazione tra popup e content script
 */

// ============================================================================
// CONFIGURAZIONE API
// ============================================================================

const CONFIG = {
  // URL base di Supabase
  SUPABASE_URL: 'https://rqrwzfenmxklmcxskfek.supabase.co',
  
  // Chiave API pubblica di Supabase (anon key)
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJxcnd6ZmVubXhrbG1jeHNrZmVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE3MzAyNzMsImV4cCI6MjA3NzMwNjI3M30.qtoT8NZQaogFxaJF--6aIjtwNznEEbWcV6XxqGRGMrY',
  
  GET_MAP_KEYS_ENDPOINT: '/functions/v1/get-map-keys',
  GET_CAT_BY_COMMUNE_ENDPOINT: '/functions/v1/get-cat-by-commune',
  ADDRESS_TO_CAT_ENDPOINT: '/functions/v1/address-to-cat',
  
  // URL della mappa CAT e del sito
  MAP_URL: 'https://catdispatcher.it',
  SITE_URL: 'https://catdispatcher.it',
  
  // Endpoint autenticazione Supabase
  AUTH_TOKEN_ENDPOINT: '/auth/v1/token',
  AUTH_USER_ENDPOINT: '/auth/v1/user'
};

// ============================================================================
// FUNZIONI AUTENTICAZIONE GOOGLE OAUTH
// ============================================================================

/**
 * Effettua il login tramite Google OAuth
 * Usa chrome.identity per gestire il flusso OAuth
 * @returns {Promise<Object>} Risultato del login
 */
async function loginWithGoogle() {
  console.log('[CAT Dispatcher BG] Avvio login Google OAuth...');

  try {
    // Ottieni il token Google tramite chrome.identity
    const googleToken = await getGoogleAuthToken();
    
    if (!googleToken) {
      throw new Error('Impossibile ottenere il token Google');
    }

    console.log('[CAT Dispatcher BG] Token Google ottenuto, scambio con Supabase...');

    // Scambia il token Google con un token Supabase
    const supabaseResult = await exchangeGoogleTokenForSupabase(googleToken);
    
    if (!supabaseResult.success) {
      throw new Error(supabaseResult.error || 'Errore scambio token');
    }

    // Verifica che l'email sia autorizzata
    const emailAllowed = await checkEmailAllowed(supabaseResult.user.email);
    
    if (!emailAllowed) {
      // Logout e restituisci errore
      await logout();
      return {
        success: false,
        error: 'Email non autorizzata. Contatta l\'amministratore per richiedere l\'accesso.'
      };
    }

    // Verifica se l'utente è bloccato (controllo server-side)
    const isBlocked = await checkIfUserBlocked(supabaseResult.accessToken || null);
    if (isBlocked) {
      await logout();
      return {
        success: false,
        error: 'Il tuo account è stato bloccato. Contatta l\'amministratore.'
      };
    }

    console.log('[CAT Dispatcher BG] Login completato per:', supabaseResult.user.email);

    return {
      success: true,
      user: supabaseResult.user
    };
  } catch (error) {
    console.error('[CAT Dispatcher BG] Errore login Google:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Ottiene un token di accesso Google tramite chrome.identity.launchWebAuthFlow
 * Questo approccio non richiede che l'utente sia loggato nel browser Chrome
 * @returns {Promise<string|null>} Token Google o null se fallisce
 */
async function getGoogleAuthToken() {
  return new Promise((resolve, reject) => {
    // Costruisci l'URL di autorizzazione Google OAuth
    const manifest = chrome.runtime.getManifest();
    const clientId = manifest.oauth2.client_id;
    const redirectUri = chrome.identity.getRedirectURL();
    const scopes = manifest.oauth2.scopes.join(' ');
    
    const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    authUrl.searchParams.set('client_id', clientId);
    authUrl.searchParams.set('redirect_uri', redirectUri);
    authUrl.searchParams.set('response_type', 'token');
    authUrl.searchParams.set('scope', scopes);
    authUrl.searchParams.set('prompt', 'select_account');
    
    console.log('[CAT Dispatcher BG] Redirect URI:', redirectUri);
    console.log('[CAT Dispatcher BG] Auth URL:', authUrl.toString());
    
    chrome.identity.launchWebAuthFlow(
      {
        url: authUrl.toString(),
        interactive: true
      },
      (responseUrl) => {
        if (chrome.runtime.lastError) {
          console.error('[CAT Dispatcher BG] Errore launchWebAuthFlow:', chrome.runtime.lastError);
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        
        if (!responseUrl) {
          reject(new Error('Nessuna risposta dal flusso OAuth'));
          return;
        }
        
        console.log('[CAT Dispatcher BG] Response URL ricevuto');
        
        // Estrai il token dalla URL di risposta
        // Format: https://...#access_token=TOKEN&token_type=Bearer&expires_in=3600
        const url = new URL(responseUrl);
        const hash = url.hash.substring(1); // Rimuovi il #
        const params = new URLSearchParams(hash);
        const accessToken = params.get('access_token');
        
        if (accessToken) {
          resolve(accessToken);
        } else {
          reject(new Error('Token non trovato nella risposta'));
        }
      }
    );
  });
}

/**
 * Scambia il token Google con un token di sessione Supabase
 * @param {string} googleToken - Token di accesso Google
 * @returns {Promise<Object>} Risultato con token Supabase e info utente
 */
async function exchangeGoogleTokenForSupabase(googleToken) {
  const url = `${CONFIG.SUPABASE_URL}${CONFIG.AUTH_TOKEN_ENDPOINT}?grant_type=id_token`;

  try {
    // Prima ottieni le info utente da Google per avere l'ID token
    const userInfoResponse = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: {
        'Authorization': `Bearer ${googleToken}`
      }
    });

    if (!userInfoResponse.ok) {
      throw new Error('Impossibile ottenere info utente da Google');
    }

    const userInfo = await userInfoResponse.json();
    console.log('[CAT Dispatcher BG] Info utente Google:', userInfo.email);

    // Ora dobbiamo usare il token per autenticarci con Supabase
    // Supabase supporta signInWithIdToken, ma da service worker usiamo l'API REST
    const response = await fetch(`${CONFIG.SUPABASE_URL}/auth/v1/token?grant_type=id_token`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': CONFIG.SUPABASE_ANON_KEY
      },
      body: JSON.stringify({
        provider: 'google',
        id_token: googleToken,
        access_token: googleToken
      })
    });

    // Se non funziona con id_token, proviamo con signInWithOAuth callback
    if (!response.ok) {
      // Fallback: usa direttamente le info Google e crea sessione
      // Questo approccio salva le info utente localmente
      console.log('[CAT Dispatcher BG] Fallback: salvo info utente localmente');
      
      // Sessione lunga (7 giorni) - il refresh silenzioso rinnoverà il token quando serve
      const sevenDays = 7 * 24 * 60 * 60 * 1000;
      
      await chrome.storage.local.set({
        catDispatcher_accessToken: googleToken,
        catDispatcher_googleToken: googleToken,
        catDispatcher_expiresAt: Date.now() + sevenDays,
        catDispatcher_user: {
          id: userInfo.sub,
          email: userInfo.email,
          name: userInfo.name,
          picture: userInfo.picture
        }
      });

      return {
        success: true,
        user: {
          id: userInfo.sub,
          email: userInfo.email,
          name: userInfo.name
        }
      };
    }

    const data = await response.json();

    // Salva i token in chrome.storage
    await chrome.storage.local.set({
      catDispatcher_accessToken: data.access_token,
      catDispatcher_refreshToken: data.refresh_token,
      catDispatcher_expiresAt: Date.now() + (data.expires_in * 1000),
      catDispatcher_user: {
        id: data.user.id,
        email: data.user.email
      }
    });

    return {
      success: true,
      user: {
        id: data.user.id,
        email: data.user.email
      }
    };
  } catch (error) {
    console.error('[CAT Dispatcher BG] Errore scambio token:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Verifica se l'utente è bloccato controllando il ruolo tramite API
 * @param {string|null} accessToken - Token Supabase (se null, legge da storage)
 * @returns {Promise<boolean>} true se l'utente è bloccato
 */
async function checkIfUserBlocked(accessToken) {
  try {
    let token = accessToken;
    if (!token) {
      const storage = await chrome.storage.local.get(['catDispatcher_accessToken']);
      token = storage.catDispatcher_accessToken;
    }
    if (!token) return false;

    // Chiama get-admin-data con resource my_roles per verificare il ruolo
    const response = await fetch(`${CONFIG.SUPABASE_URL}/functions/v1/get-admin-data`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        'apikey': CONFIG.SUPABASE_ANON_KEY
      },
      body: JSON.stringify({ resource: 'my_roles' })
    });

    // Se la risposta è 403 con code BLOCKED, l'utente è bloccato
    if (response.status === 403) {
      const data = await response.json().catch(() => ({}));
      if (data.code === 'BLOCKED') {
        console.log('[CAT Dispatcher BG] Utente bloccato dal server');
        return true;
      }
    }

    return false;
  } catch (e) {
    console.warn('[CAT Dispatcher BG] Errore verifica blocked:', e);
    return false;
  }
}

/**
 * Verifica se l'email è autorizzata (solo dominio @actsrl.it)
 * @param {string} email - Email da verificare
 * @returns {boolean} true se autorizzata
 */
function checkEmailAllowed(email) {
  return !!(email && email.toLowerCase().endsWith('@actsrl.it'));
}

/**
 * Effettua il logout cancellando i token salvati
 * @returns {Promise<Object>} Risultato del logout
 */
async function logout() {
  try {
    // Revoca il token Google se presente
    const storage = await chrome.storage.local.get(['catDispatcher_googleToken']);
    if (storage.catDispatcher_googleToken) {
      // Revoca il token tramite API Google
      try {
        await fetch(`https://accounts.google.com/o/oauth2/revoke?token=${storage.catDispatcher_googleToken}`);
      } catch (e) {
        console.warn('[CAT Dispatcher BG] Errore revoca token Google:', e);
      }
    }

    // Pulisci la cache di identity
    await chrome.identity.clearAllCachedAuthTokens();

    await chrome.storage.local.remove([
      'catDispatcher_accessToken',
      'catDispatcher_refreshToken',
      'catDispatcher_googleToken',
      'catDispatcher_expiresAt',
      'catDispatcher_user'
    ]);

    console.log('[CAT Dispatcher BG] Logout completato');

    return { success: true };
  } catch (error) {
    console.error('[CAT Dispatcher BG] Errore logout:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Verifica se l'utente è autenticato
 * Prima controlla la sessione locale, poi tenta sync con il sito
 * @returns {Promise<Object>} Stato dell'autenticazione
 */
async function checkAuth() {
  try {
    const storage = await chrome.storage.local.get([
      'catDispatcher_accessToken',
      'catDispatcher_expiresAt',
      'catDispatcher_user',
      'catDispatcher_refreshToken'
    ]);

    // Nessun token salvato - prova a sincronizzare con il sito
    if (!storage.catDispatcher_accessToken) {
      console.log('[CAT Dispatcher BG] Nessun token, tento sync con sito...');
      const synced = await syncSessionFromWebsite();
      if (synced) {
        return { isLoggedIn: true, user: synced.user };
      }
      return { isLoggedIn: false };
    }

    // Verifica scadenza token
    const now = Date.now();
    const expiresAt = storage.catDispatcher_expiresAt || 0;
    const oneDay = 24 * 60 * 60 * 1000;
    
    // Se il token è scaduto
    if (now >= expiresAt) {
      console.log('[CAT Dispatcher BG] Token scaduto, tento rinnovo...');
      
      // Prima prova sync con il sito
      const synced = await syncSessionFromWebsite();
      if (synced) {
        return { isLoggedIn: true, user: synced.user };
      }
      
      // Poi prova refresh silenzioso del token Google
      const refreshed = await silentTokenRefresh();
      if (refreshed) {
        return { isLoggedIn: true, user: refreshed.user };
      }
      
      console.log('[CAT Dispatcher BG] Impossibile rinnovare, logout');
      await logout();
      return { isLoggedIn: false };
    }
    
    // Se il token scade entro 1 giorno, rinnova in background (non blocca)
    if (now >= expiresAt - oneDay) {
      console.log('[CAT Dispatcher BG] Token in scadenza tra meno di 1 giorno, rinnovo in background...');
      silentTokenRefresh().catch(() => {}); // Non blocca, rinnova in background
    }

    // Token valido
    return {
      isLoggedIn: true,
      user: storage.catDispatcher_user
    };
  } catch (error) {
    console.error('[CAT Dispatcher BG] Errore verifica auth:', error);
    return { isLoggedIn: false, error: error.message };
  }
}

/**
 * Sincronizza la sessione dal sito catdispatcher.it
 * Legge la sessione Supabase dal localStorage del sito.
 * Inietta il content script se necessario (tab aperte prima dell'installazione).
 * @returns {Promise<Object|null>} Dati utente o null
 */
async function syncSessionFromWebsite() {
  try {
    // Cerca tab del sito catdispatcher.it
    const tabs = await chrome.tabs.query({ url: 'https://catdispatcher.it/*' });
    
    if (tabs.length === 0) {
      console.log('[CAT Dispatcher BG] Nessuna tab catdispatcher.it trovata');
      return null;
    }
    
    // Chiedi al content script di leggere la sessione
    for (const tab of tabs) {
      try {
        let response;
        try {
          response = await chrome.tabs.sendMessage(tab.id, {
            action: 'GET_SUPABASE_SESSION'
          });
        } catch (e) {
          // Content script non caricato (tab aperta prima dell'installazione)
          if (e?.message?.includes('Receiving end does not exist') || e?.message?.includes('Could not establish connection')) {
            console.log('[CAT Dispatcher BG] Content script assente, iniezione in tab', tab.id);
            await chrome.scripting.executeScript({
              target: { tabId: tab.id },
              files: ['content-script.js']
            });
            await new Promise(r => setTimeout(r, 300));
            response = await chrome.tabs.sendMessage(tab.id, {
              action: 'GET_SUPABASE_SESSION'
            });
          } else {
            throw e;
          }
        }
        
        if (response?.success && response.session) {
          console.log('[CAT Dispatcher BG] Sessione sincronizzata dal sito');
          
          // Salva la sessione
          await chrome.storage.local.set({
            catDispatcher_accessToken: response.session.access_token,
            catDispatcher_refreshToken: response.session.refresh_token,
            catDispatcher_expiresAt: response.session.expires_at * 1000,
            catDispatcher_user: {
              id: response.session.user.id,
              email: response.session.user.email,
              name: response.session.user.user_metadata?.full_name || response.session.user.email
            }
          });
          
          return { user: response.session.user };
        }
      } catch (e) {
        // Tab non risponde, continua
      }
    }
    
    return null;
  } catch (error) {
    console.error('[CAT Dispatcher BG] Errore sync sessione:', error);
    return null;
  }
}

/**
 * Tenta un refresh silenzioso del token Google (senza popup)
 * @returns {Promise<Object|null>} Dati utente o null
 */
async function silentTokenRefresh() {
  try {
    // Prova launchWebAuthFlow senza interazione
    const manifest = chrome.runtime.getManifest();
    const clientId = manifest.oauth2.client_id;
    const redirectUri = chrome.identity.getRedirectURL();
    const scopes = manifest.oauth2.scopes.join(' ');
    
    const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    authUrl.searchParams.set('client_id', clientId);
    authUrl.searchParams.set('redirect_uri', redirectUri);
    authUrl.searchParams.set('response_type', 'token');
    authUrl.searchParams.set('scope', scopes);
    authUrl.searchParams.set('prompt', 'none'); // Nessun popup se già autenticato
    
    return new Promise((resolve) => {
      chrome.identity.launchWebAuthFlow(
        {
          url: authUrl.toString(),
          interactive: false // Non interattivo
        },
        async (responseUrl) => {
          if (chrome.runtime.lastError || !responseUrl) {
            console.log('[CAT Dispatcher BG] Silent refresh fallito');
            resolve(null);
            return;
          }
          
          // Estrai il token
          const url = new URL(responseUrl);
          const hash = url.hash.substring(1);
          const params = new URLSearchParams(hash);
          const accessToken = params.get('access_token');
          
          if (accessToken) {
            console.log('[CAT Dispatcher BG] Token rinnovato silenziosamente');
            
            // Ottieni info utente
            const userInfoResponse = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
              headers: { 'Authorization': `Bearer ${accessToken}` }
            });
            
            if (userInfoResponse.ok) {
              const userInfo = await userInfoResponse.json();
              
              // Sessione lunga (7 giorni)
              const sevenDays = 7 * 24 * 60 * 60 * 1000;
              
              // Salva nuovo token
              await chrome.storage.local.set({
                catDispatcher_accessToken: accessToken,
                catDispatcher_googleToken: accessToken,
                catDispatcher_expiresAt: Date.now() + sevenDays,
                catDispatcher_user: {
                  id: userInfo.sub,
                  email: userInfo.email,
                  name: userInfo.name,
                  picture: userInfo.picture
                }
              });
              
              resolve({ user: userInfo });
              return;
            }
          }
          
          resolve(null);
        }
      );
    });
  } catch (error) {
    console.error('[CAT Dispatcher BG] Errore silent refresh:', error);
    return null;
  }
}

/**
 * Verifica che il token Google sia ancora valido
 * Se non lo è, tenta un refresh silenzioso
 * @returns {Promise<boolean>} true se il token è valido
 */
async function ensureValidGoogleToken() {
  try {
    const storage = await chrome.storage.local.get(['catDispatcher_googleToken']);
    
    if (!storage.catDispatcher_googleToken) {
      return false;
    }
    
    // Verifica il token facendo una chiamata a Google
    const response = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { 'Authorization': `Bearer ${storage.catDispatcher_googleToken}` }
    });
    
    if (response.ok) {
      return true;
    }
    
    // Token scaduto, prova refresh silenzioso
    console.log('[CAT Dispatcher BG] Token Google non valido, tento refresh...');
    const refreshed = await silentTokenRefresh();
    return !!refreshed;
    
  } catch (error) {
    console.warn('[CAT Dispatcher BG] Errore verifica token:', error);
    return false;
  }
}

// ============================================================================
// CACHE COMUNI -> CAT (OTTIMIZZATA)
// ============================================================================
// La cache viene invalidata automaticamente quando cambia la versione delle
// sospensioni (controllo orario 08-19). Questo permette di cachare TUTTO:
// - CAT normali
// - CAT sospesi
// - Risultati geocodificati per comuni con più CAT
// ============================================================================

const CACHE_KEY_PREFIX = 'catDispatcher_communeCache_';
const CACHE_KEY_ADDRESS_PREFIX = 'catDispatcher_addressCache_';
const CACHE_TTL = 30 * 24 * 60 * 60 * 1000; // 30 giorni (invalidazione gestita da versioning)
const SUSPENSIONS_VERSION_KEY = 'cat_suspensions_version';
const SUSPENSIONS_LAST_CHECK_KEY = 'cat_suspensions_last_check';

/**
 * Normalizza una stringa per uso come chiave cache
 */
function normalizeForCacheKey(str) {
  return (str || '')
    .toLowerCase()
    .trim()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '') // Rimuove accenti
    .replace(/[^a-z0-9]/g, '_'); // Sostituisce caratteri speciali
}

/**
 * Genera una chiave cache per il comune
 */
function getCommuneCacheKey(comune, provincia) {
  const normalizedComune = normalizeForCacheKey(comune);
  const normalizedProvincia = normalizeForCacheKey(provincia).substring(0, 2);
  return `${CACHE_KEY_PREFIX}${normalizedComune}_${normalizedProvincia}`;
}

/**
 * Genera una chiave cache per un indirizzo completo (geocoding)
 */
function getAddressCacheKey(indirizzo, comune, provincia) {
  const normalizedIndirizzo = normalizeForCacheKey(indirizzo);
  const normalizedComune = normalizeForCacheKey(comune);
  const normalizedProvincia = normalizeForCacheKey(provincia).substring(0, 2);
  // Tronca l'indirizzo per evitare chiavi troppo lunghe
  const shortAddress = normalizedIndirizzo.substring(0, 50);
  return `${CACHE_KEY_ADDRESS_PREFIX}${shortAddress}_${normalizedComune}_${normalizedProvincia}`;
}

/**
 * Recupera un risultato dalla cache (comune o indirizzo)
 * @param {string} key - Chiave cache
 * @returns {Object|null} Dati cachati o null
 */
async function getCachedResult(key) {
  try {
    const result = await chrome.storage.local.get([key]);
    const cached = result[key];
    
    if (cached && cached.timestamp && (Date.now() - cached.timestamp < CACHE_TTL)) {
      return cached;
    }
    
    // Cache scaduta, rimuovi
    if (cached) {
      await chrome.storage.local.remove([key]);
    }
  } catch (error) {
    console.warn('[CAT Dispatcher BG] Errore lettura cache:', error);
  }
  
  return null;
}

/**
 * Recupera un risultato dalla cache per comune
 */
async function getCachedCommuneResult(comune, provincia) {
  const key = getCommuneCacheKey(comune, provincia);
  const cached = await getCachedResult(key);
  
  if (cached) {
    console.log('[CAT Dispatcher BG] Cache hit (comune):', comune);
    return cached.data;
  }
  
  return null;
}

/**
 * Recupera un risultato dalla cache per indirizzo (geocoding)
 */
async function getCachedAddressResult(indirizzo, comune, provincia) {
  const key = getAddressCacheKey(indirizzo, comune, provincia);
  const cached = await getCachedResult(key);
  
  if (cached) {
    console.log('[CAT Dispatcher BG] Cache hit (indirizzo):', indirizzo);
    return cached.data;
  }
  
  return null;
}

/**
 * Salva un risultato in cache per comune
 */
async function setCachedCommuneResult(comune, provincia, data, isSuspended = false) {
  const key = getCommuneCacheKey(comune, provincia);
  
  try {
    await chrome.storage.local.set({
      [key]: {
        data,
        timestamp: Date.now(),
        suspended: isSuspended
      }
    });
    console.log('[CAT Dispatcher BG] Cached (comune):', comune, isSuspended ? '[sospeso]' : '');
  } catch (error) {
    console.warn('[CAT Dispatcher BG] Errore salvataggio cache:', error);
  }
}

/**
 * Salva un risultato in cache per indirizzo (geocoding)
 */
async function setCachedAddressResult(indirizzo, comune, provincia, data, isSuspended = false) {
  const key = getAddressCacheKey(indirizzo, comune, provincia);
  
  try {
    await chrome.storage.local.set({
      [key]: {
        data,
        timestamp: Date.now(),
        suspended: isSuspended
      }
    });
    console.log('[CAT Dispatcher BG] Cached (indirizzo):', indirizzo, isSuspended ? '[sospeso]' : '');
  } catch (error) {
    console.warn('[CAT Dispatcher BG] Errore salvataggio cache:', error);
  }
}

/**
 * Pulisce la cache scaduta (comuni e indirizzi)
 */
async function cleanExpiredCache() {
  try {
    const storage = await chrome.storage.local.get(null);
    const keysToRemove = [];
    const now = Date.now();
    
    for (const [key, value] of Object.entries(storage)) {
      // Controlla sia cache comuni che cache indirizzi
      if (key.startsWith(CACHE_KEY_PREFIX) || key.startsWith(CACHE_KEY_ADDRESS_PREFIX)) {
        if (!value.timestamp || (now - value.timestamp >= CACHE_TTL)) {
          keysToRemove.push(key);
        }
      }
    }
    
    if (keysToRemove.length > 0) {
      await chrome.storage.local.remove(keysToRemove);
      console.log('[CAT Dispatcher BG] Pulizia cache:', keysToRemove.length, 'entries rimosse');
    }
  } catch (error) {
    console.warn('[CAT Dispatcher BG] Errore pulizia cache:', error);
  }
}

/**
 * Pulisce TUTTA la cache CAT (comuni e indirizzi)
 * Chiamata quando cambia la versione delle sospensioni
 */
async function clearAllCatCache() {
  try {
    const storage = await chrome.storage.local.get(null);
    const keysToRemove = [];
    
    for (const key of Object.keys(storage)) {
      // Rimuovi sia cache comuni che cache indirizzi
      if (key.startsWith(CACHE_KEY_PREFIX) || key.startsWith(CACHE_KEY_ADDRESS_PREFIX)) {
        keysToRemove.push(key);
      }
    }
    
    if (keysToRemove.length > 0) {
      await chrome.storage.local.remove(keysToRemove);
      console.log('[CAT Dispatcher BG] Cache CAT svuotata:', keysToRemove.length, 'entries rimosse');
    }
    return { success: true, removed: keysToRemove.length };
  } catch (error) {
    console.warn('[CAT Dispatcher BG] Errore svuotamento cache:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Restituisce statistiche sulla cache
 */
async function getCacheStats() {
  try {
    const storage = await chrome.storage.local.get(null);
    let communeCount = 0;
    let addressCount = 0;
    let suspendedCount = 0;
    
    for (const [key, value] of Object.entries(storage)) {
      if (key.startsWith(CACHE_KEY_PREFIX)) {
        communeCount++;
        if (value.suspended) suspendedCount++;
      } else if (key.startsWith(CACHE_KEY_ADDRESS_PREFIX)) {
        addressCount++;
        if (value.suspended) suspendedCount++;
      }
    }
    
    return {
      comuni: communeCount,
      indirizzi: addressCount,
      sospesi: suspendedCount,
      totale: communeCount + addressCount
    };
  } catch (error) {
    return { error: error.message };
  }
}

/**
 * Controlla se la versione delle sospensioni è cambiata
 * Se è cambiata, invalida tutta la cache
 * Chiamata solo:
 * - Ogni ora tra le 08:00 e le 19:00 (tramite allarme)
 * - Manualmente dal tasto "Aggiorna" nel popup
 * @param {boolean} force - Se true, esegue sempre il controllo
 * @returns {Promise<boolean>} true se la cache è stata invalidata
 */
async function checkSuspensionsVersion(force = false) {
  try {
    // Controlla se siamo nell'orario lavorativo (08:00 - 19:00)
    const now = new Date();
    const hour = now.getHours();
    const isWorkingHours = hour >= 8 && hour < 19;
    
    if (!force && !isWorkingHours) {
      console.log('[CAT Dispatcher BG] Fuori orario lavorativo, skip check sospensioni');
      return false;
    }
    
    console.log('[CAT Dispatcher BG] Controllo versione sospensioni...');
    
    const url = `${CONFIG.SUPABASE_URL}/functions/v1/suspensions-version`;
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'apikey': CONFIG.SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${CONFIG.SUPABASE_ANON_KEY}`
      }
    });
    
    if (!response.ok) {
      console.warn('[CAT Dispatcher BG] Errore check versione sospensioni:', response.status);
      return false;
    }
    
    const data = await response.json();
    const newVersion = data.version;
    
    // Recupera la versione salvata
    const stored = await chrome.storage.local.get([SUSPENSIONS_VERSION_KEY]);
    const savedVersion = stored[SUSPENSIONS_VERSION_KEY];
    
    // Salva timestamp ultimo controllo
    await chrome.storage.local.set({ 
      [SUSPENSIONS_VERSION_KEY]: newVersion,
      [SUSPENSIONS_LAST_CHECK_KEY]: Date.now()
    });
    
    if (savedVersion && savedVersion !== newVersion) {
      // Versione cambiata! Invalida la cache
      console.log('[CAT Dispatcher BG] Versione sospensioni cambiata:', savedVersion, '->', newVersion);
      await clearAllCatCache();
      return true;
    }
    
    console.log('[CAT Dispatcher BG] Versione sospensioni:', newVersion, '(invariata)');
    return false;
    
  } catch (error) {
    console.warn('[CAT Dispatcher BG] Errore check versione:', error);
    return false;
  }
}

// ============================================================================
// MAP KEYS E DEOFFUSCAZIONE (stessa sessione del sito)
// ============================================================================

const MAP_KEYS_STORAGE_KEY = 'catDispatcher_mapKeysSession';

function deobfuscateValue(value, reverseMap) {
  if (value === null || value === undefined) return value;
  if (Array.isArray(value)) return value.map(v => deobfuscateValue(v, reverseMap));
  if (typeof value === 'object' && value !== null && !(value instanceof Date)) {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      const realKey = reverseMap[k] ?? k;
      out[realKey] = deobfuscateValue(v, reverseMap);
    }
    return out;
  }
  return value;
}

async function ensureMapKeys() {
  const stored = await chrome.storage.local.get([MAP_KEYS_STORAGE_KEY, 'catDispatcher_accessToken']);
  const token = stored.catDispatcher_accessToken;
  if (!token) return null;
  try {
    const parsed = stored[MAP_KEYS_STORAGE_KEY];
    if (parsed?.sessionKey && parsed?.keys && typeof parsed.keys === 'object') return parsed;
  } catch (e) { /* ignore */ }
  const url = `${CONFIG.SUPABASE_URL}${CONFIG.GET_MAP_KEYS_ENDPOINT}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'apikey': CONFIG.SUPABASE_ANON_KEY, 'Authorization': `Bearer ${token}` },
    body: JSON.stringify({})
  });
  if (!res.ok) return null;
  const data = await res.json();
  if (!data?.sessionKey || !data?.keys) return null;
  const payload = { sessionKey: data.sessionKey, keys: data.keys };
  await chrome.storage.local.set({ [MAP_KEYS_STORAGE_KEY]: payload });
  return payload;
}

// ============================================================================
// FUNZIONI API
// ============================================================================

/**
 * Ottiene il CAT in base all'ubicazione.
 * 
 * STRATEGIA OTTIMIZZATA (riduzione costi ~60%):
 * 1. Cache locale → risposta immediata senza chiamate
 * 2. Edge Function get-cat-by-commune → CAT da comune (JWT + rate limit)
 * 3. Edge Function address-to-cat → SOLO per geocoding (comuni con quartieri)
 * 
 * NOTA: Attualmente nessun comune ha quartieri configurati, quindi
 * il geocoding non viene mai usato. Manteniamo la logica per future espansioni.
 * 
 * @param {Object} ubicazione - Dati dell'ubicazione rischio
 * @returns {Promise<Object>} Risposta con nome CAT o info sospensione
 */
async function getCatByLocation(ubicazione) {
  const comune = ubicazione.citta || '';
  const provincia = ubicazione.provincia || '';
  const indirizzo = ubicazione.indirizzo || '';
  
  // =========================================================================
  // STEP 1: Controlla cache per indirizzo (se abbiamo un indirizzo specifico)
  // =========================================================================
  if (indirizzo) {
    const cachedAddress = await getCachedAddressResult(indirizzo, comune, provincia);
    if (cachedAddress) {
      console.log('[CAT Dispatcher BG] Cache hit (indirizzo) per:', indirizzo);
      if (cachedAddress.suspended) {
        return {
          success: false,
          suspended: true,
          data: cachedAddress
        };
      }
      return {
        success: true,
        data: cachedAddress
      };
    }
  }
  
  // =========================================================================
  // STEP 2: Controlla cache per comune
  // =========================================================================
  const cachedCommune = await getCachedCommuneResult(comune, provincia);
  if (cachedCommune) {
    // Se il comune ha un solo CAT, possiamo usare la cache
    if (!cachedCommune.multiple_cats) {
      console.log('[CAT Dispatcher BG] Cache hit (comune) per:', comune);
      if (cachedCommune.suspended) {
        return {
          success: false,
          suspended: true,
          data: cachedCommune
        };
      }
      return {
        success: true,
        data: cachedCommune
      };
    }
    // Se ha più CAT ma non abbiamo indirizzo, restituiamo comunque il risultato cachato
    if (!indirizzo) {
      console.log('[CAT Dispatcher BG] Cache hit (comune multi-CAT) per:', comune);
      return {
        success: true,
        data: cachedCommune
      };
    }
    // Altrimenti dobbiamo fare geocoding (continua sotto)
  }
  
  // =========================================================================
  // STEP 3: Edge Function get-cat-by-commune (JWT obbligatorio)
  // =========================================================================
  const storage = await chrome.storage.local.get(['catDispatcher_accessToken']);
  const accessToken = storage.catDispatcher_accessToken;
  if (!accessToken) {
    console.error('[CAT Dispatcher BG] Token mancante per get-cat-by-commune');
    throw new Error('Sessione scaduta. Effettua di nuovo l\'accesso.');
  }
  const mapKeys = await ensureMapKeys();
  const getCatUrl = `${CONFIG.SUPABASE_URL}${CONFIG.GET_CAT_BY_COMMUNE_ENDPOINT}`;
  console.log('[CAT Dispatcher BG] Chiamata get-cat-by-commune per:', comune);

  try {
    const body = { comune: comune, provincia: provincia || null };
    if (mapKeys?.sessionKey) body.sessionKey = mapKeys.sessionKey;

    const rpcResponse = await fetch(getCatUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': CONFIG.SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${accessToken}`
      },
      body: JSON.stringify(body)
    });

    if (!rpcResponse.ok) {
      // Gestione errore 403 BLOCKED: utente bloccato
      if (rpcResponse.status === 403) {
        const errData = await rpcResponse.json().catch(() => ({}));
        if (errData.code === 'BLOCKED') {
          await logout();
          return {
            success: false,
            error: 'Il tuo account è stato bloccato. Contatta l\'amministratore.',
            blocked: true
          };
        }
      }
      // Gestione errore 401: nessun CAT assegnato per il comune
      if (rpcResponse.status === 401) {
        const errorMessage = `Nessun CAT assegnato per ${comune}${provincia ? ` (${provincia})` : ''}`;
        console.log('[CAT Dispatcher BG]', errorMessage);
        return {
          success: false,
          error: errorMessage
        };
      }
      throw new Error(`Errore get-cat-by-commune (${rpcResponse.status})`);
    }

    let data = await rpcResponse.json();
    if (data?.code === 'NEED_MAP_KEYS') {
      await chrome.storage.local.remove(MAP_KEYS_STORAGE_KEY);
      if (mapKeys) {
        const retryBody = { comune: comune, provincia: provincia || null };
        const retryRes = await fetch(getCatUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'apikey': CONFIG.SUPABASE_ANON_KEY, 'Authorization': `Bearer ${accessToken}` },
          body: JSON.stringify(retryBody)
        });
        if (retryRes.ok) data = await retryRes.json();
      }
    } else if (mapKeys?.keys && data) {
      data = deobfuscateValue(data, mapKeys.keys);
    }
    
    // =========================================================================
    // Gestione CAT sospeso
    // =========================================================================
    if (data.suspended) {
      console.log('[CAT Dispatcher BG] CAT sospeso:', data.cat_name);
      
      const suspendedResult = {
        cat_name: data.cat_name,
        cat_alias: data.cat_alias || data.cat_name,
        commune_name: data.commune_name,
        suspension_reason: data.suspension_reason,
        suspension_end_date: data.suspension_end_date,
        suspended: true
      };
      
      // CACHE: salva anche i risultati sospesi
      await setCachedCommuneResult(comune, provincia, suspendedResult, true);
      
      return {
        success: false,
        suspended: true,
        data: suspendedResult
      };
    }
    
    // Gestione errori
    if (!data.success) {
      throw new Error(data.error || 'Errore sconosciuto');
    }
    
    console.log('[CAT Dispatcher BG] CAT trovato (RPC):', data.cat_name, 
      data.multiple_cats ? '(comune con più CAT)' : '');

    // =========================================================================
    // STEP 4: Se più CAT e abbiamo indirizzo, usa geocoding (Edge Function)
    // NOTA: Attualmente nessun comune ha quartieri, quindi questo non viene mai eseguito
    // =========================================================================
    if (data.multiple_cats && data.needs_geocoding && indirizzo) {
      console.log('[CAT Dispatcher BG] Più CAT trovati, uso geocoding (Edge Function)...');
      
      const addressParts = [
        indirizzo,
        comune,
        ubicazione.cap,
        provincia,
        ubicazione.nazione
      ].filter(Boolean);
      const fullAddress = addressParts.join(', ');
      
      const storage = await chrome.storage.local.get(['catDispatcher_accessToken']);
      const accessToken = storage.catDispatcher_accessToken;
      if (!accessToken) {
        console.error('[CAT Dispatcher BG] Token Supabase mancante per address-to-cat');
        throw new Error('Sessione scaduta. Effettua di nuovo l\'accesso.');
      }
      const mapKeysAddr = await ensureMapKeys();
      const addressBody = { address: fullAddress, intervention_type: 'sopralluogo' };
      if (mapKeysAddr?.sessionKey) addressBody.sessionKey = mapKeysAddr.sessionKey;
      const geocodeUrl = `${CONFIG.SUPABASE_URL}${CONFIG.ADDRESS_TO_CAT_ENDPOINT}`;
      const geocodeResponse = await fetch(geocodeUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': CONFIG.SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${accessToken}`
        },
        body: JSON.stringify(addressBody)
      });
      
      if (geocodeResponse.ok) {
        let geocodeData = await geocodeResponse.json();
        if (geocodeData?.code === 'NEED_MAP_KEYS') {
          await chrome.storage.local.remove(MAP_KEYS_STORAGE_KEY);
        } else if (mapKeysAddr?.keys && geocodeData) {
          geocodeData = deobfuscateValue(geocodeData, mapKeysAddr.keys);
        }
        
        // Gestione CAT sospeso (da geocoding)
        if (geocodeData.suspended) {
          console.log('[CAT Dispatcher BG] CAT sospeso (geocoding):', geocodeData.cat_name);
          
          const suspendedResult = {
            cat_name: geocodeData.cat_name,
            cat_alias: geocodeData.cat_alias || geocodeData.cat_name,
            commune_name: geocodeData.commune_name,
            suspension_reason: geocodeData.suspension_reason,
            suspension_end_date: geocodeData.suspension_end_date,
            suspended: true
          };
          
          // CACHE: salva risultato geocodificato sospeso
          await setCachedAddressResult(indirizzo, comune, provincia, suspendedResult, true);
          
          return {
            success: false,
            suspended: true,
            data: suspendedResult
          };
        }
        
        if (geocodeData.success && geocodeData.cat_name) {
          console.log('[CAT Dispatcher BG] CAT da geocoding:', geocodeData.cat_name);
          
          const geocodedResult = {
            cat_name: geocodeData.cat_name,
            cat_alias: geocodeData.cat_alias || geocodeData.cat_name,
            commune_name: geocodeData.commune_name,
            multiple_cats: true,
            needs_geocoding: false
          };
          
          // CACHE: salva risultato geocodificato
          await setCachedAddressResult(indirizzo, comune, provincia, geocodedResult, false);
          
          return {
            success: true,
            data: geocodedResult
          };
        }
      }
      // Se geocoding fallisce, usa il risultato del lookup
    }

    // =========================================================================
    // STEP 5: Costruisci e salva risultato finale
    // =========================================================================
    const result = { 
      cat_name: data.cat_name,
      cat_alias: data.cat_alias || data.cat_name,
      commune_name: data.commune_name,
      needs_geocoding: data.needs_geocoding,
      multiple_cats: data.multiple_cats
    };
    
    // CACHE: salva sempre il risultato del comune
    await setCachedCommuneResult(comune, provincia, result, false);

    return {
      success: true,
      data: result
    };
  } catch (error) {
    console.error('[CAT Dispatcher BG] Errore chiamata RPC:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Genera l'URL per aprire la mappa CAT con l'indirizzo come query di ricerca
 * @param {Object} ubicazione - Dati dell'ubicazione rischio
 * @returns {string} URL completo della mappa
 */
function getMapUrl(ubicazione) {
  if (!ubicazione) {
    console.warn('[CAT Dispatcher BG] getMapUrl: ubicazione non definita');
    return CONFIG.MAP_URL;
  }
  
  // Se non abbiamo almeno la città, ritorna l'URL base
  if (!ubicazione.citta && !ubicazione.indirizzo) {
    console.warn('[CAT Dispatcher BG] getMapUrl: nessun dato indirizzo');
    return CONFIG.MAP_URL;
  }
  
  // Usa l'endpoint /api con i parametri specifici
  const params = new URLSearchParams();
  
  if (ubicazione.indirizzo) {
    params.set('via', ubicazione.indirizzo);
  }
  if (ubicazione.citta) {
    params.set('citta', ubicazione.citta);
  }
  if (ubicazione.cap) {
    params.set('cap', ubicazione.cap);
  }
  if (ubicazione.provincia) {
    params.set('provincia', ubicazione.provincia);
  }
  if (ubicazione.nazione) {
    params.set('nazione', ubicazione.nazione);
  }
  
  const fullUrl = `${CONFIG.MAP_URL}/api?${params.toString()}`;
  console.log('[CAT Dispatcher BG] URL mappa generato:', fullUrl);
  
  return fullUrl;
}

// ============================================================================
// GESTIONE MESSAGGI
// ============================================================================

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  console.log('[CAT Dispatcher BG] Messaggio ricevuto:', request);

  // Gestione asincrona dei messaggi
  (async () => {
    switch (request.action) {
      // ===================== AUTENTICAZIONE =====================
      case 'AUTH_LOGIN_GOOGLE':
        // Login con Google OAuth
        const loginResult = await loginWithGoogle();
        sendResponse(loginResult);
        break;

      case 'AUTH_LOGOUT':
        // Logout
        const logoutResult = await logout();
        sendResponse(logoutResult);
        break;

      case 'AUTH_CHECK':
        // Verifica stato autenticazione
        const authStatus = await checkAuth();
        sendResponse(authStatus);
        break;

      case 'AUTH_SYNC':
        // Forza sincronizzazione sessione dal sito
        const synced = await syncSessionFromWebsite();
        if (synced) {
          sendResponse({ success: true, user: synced.user });
        } else {
          // Prova refresh silenzioso
          const refreshed = await silentTokenRefresh();
          if (refreshed) {
            sendResponse({ success: true, user: refreshed.user });
          } else {
            sendResponse({ success: false, error: 'Sincronizzazione fallita' });
          }
        }
        break;

      // ===================== API CAT =====================
      case 'API_GET_CAT':
        // Prima verifica autenticazione
        const authCheck = await checkAuth();
        if (!authCheck.isLoggedIn) {
          sendResponse({ success: false, error: 'NOT_LOGGED_IN' });
          break;
        }
        // Chiama l'API per ottenere il CAT
        const result = await getCatByLocation(request.ubicazione);
        sendResponse(result);
        break;

      case 'GET_MAP_URL':
        // Restituisce l'URL della mappa
        const mapUrl = getMapUrl(request.ubicazione);
        sendResponse({ success: true, url: mapUrl });
        break;

      case 'OPEN_MAP':
        // Prima verifica autenticazione
        const authCheckMap = await checkAuth();
        if (!authCheckMap.isLoggedIn) {
          sendResponse({ success: false, error: 'NOT_LOGGED_IN' });
          break;
        }
        // Apre la mappa in una nuova finestra
        const url = getMapUrl(request.ubicazione || {});
        console.log('[CAT Dispatcher BG] Apertura mappa con URL:', url);
        console.log('[CAT Dispatcher BG] Ubicazione ricevuta:', request.ubicazione);
        chrome.windows.create({
          url: url,
          type: 'popup',
          width: 1200,
          height: 800,
          focused: true
        });
        sendResponse({ success: true, url: url });
        break;

      case 'CLEAR_CAT_CACHE':
        // Pulisce la cache CAT (utile dopo modifiche sospensioni)
        const clearResult = await clearAllCatCache();
        sendResponse(clearResult);
        break;

      case 'REFRESH_SUSPENSIONS':
        // Controllo manuale versione sospensioni (tasto Aggiorna)
        console.log('[CAT Dispatcher BG] Refresh sospensioni manuale');
        const cacheInvalidated = await checkSuspensionsVersion(true);
        sendResponse({ 
          success: true, 
          cacheInvalidated,
          message: cacheInvalidated ? 'Cache aggiornata' : 'Nessuna modifica'
        });
        break;

      case 'GET_CONFIG':
        // Restituisce la configurazione (per debug)
        sendResponse({ 
          success: true, 
          config: {
            supabaseUrl: CONFIG.SUPABASE_URL,
            mapUrl: CONFIG.MAP_URL,
            siteUrl: CONFIG.SITE_URL
          }
        });
        break;

      case 'CHECK_UPDATE':
        // Controlla aggiornamenti manualmente
        const updateResult = await checkForUpdates();
        sendResponse({ success: true, ...updateResult });
        break;

      case 'GET_VERSION':
        // Restituisce la versione corrente
        const updateInfo = await chrome.storage.local.get([
          'catDispatcher_updateAvailable',
          'catDispatcher_latestVersion'
        ]);
        sendResponse({ 
          success: true, 
          currentVersion: CURRENT_VERSION,
          updateAvailable: updateInfo.catDispatcher_updateAvailable || false,
          latestVersion: updateInfo.catDispatcher_latestVersion || CURRENT_VERSION
        });
        break;

      case 'CLEAR_CACHE':
        // Pulisce tutta la cache CAT (comuni e indirizzi)
        const clearCacheResult = await clearAllCatCache();
        sendResponse({ success: true, cleared: clearCacheResult.removed || 0 });
        break;

      case 'GET_CACHE_STATS':
        // Restituisce statistiche sulla cache
        const stats = await getCacheStats();
        sendResponse({ success: true, stats });
        break;

      case 'CAT_SELECTED_FROM_MAP':
        // CAT selezionato dalla mappa - applica alla tab ACT
        console.log('[CAT Dispatcher BG] CAT selezionato dalla mappa:', request.catName);
        
        // Trova tutte le tab ACT aperte
        const actTabs = await chrome.tabs.query({ url: 'https://act.jfish.it/*' });
        console.log('[CAT Dispatcher BG] Tab ACT trovate:', actTabs.length);
        
        if (actTabs.length > 0) {
          // Invia il comando a tutte le tab ACT per impostare il CAT
          for (const tab of actTabs) {
            try {
              // Invia a tutti i frame della tab
              const frames = await chrome.webNavigation.getAllFrames({ tabId: tab.id });
              for (const frame of frames) {
                chrome.tabs.sendMessage(tab.id, {
                  action: 'SET_CAT_BY_LABEL',
                  label: request.catName
                }, { frameId: frame.frameId }, (response) => {
                  if (chrome.runtime.lastError) {
                    // Ignora errori sui frame che non rispondono
                  } else if (response?.success) {
                    console.log('[CAT Dispatcher BG] CAT impostato nel frame', frame.frameId);
                  }
                });
              }
            } catch (e) {
              console.warn('[CAT Dispatcher BG] Errore invio a tab ACT:', e);
            }
          }
          
          // Log di conferma (niente notifica browser, troppo invasiva)
          console.log('[CAT Dispatcher BG] CAT applicato:', request.catName, 'a', actTabs.length, 'tab');
        }
        
        sendResponse({ success: true, tabsUpdated: actTabs.length });
        break;

      case 'GET_PENDING_CAT':
        // Restituisce il CAT pendente da applicare
        const pendingData = await chrome.storage.local.get([
          'catDispatcher_pendingCat',
          'catDispatcher_pendingCatTimestamp'
        ]);
        
        // Verifica che non sia troppo vecchio (5 minuti)
        const maxAge = 5 * 60 * 1000;
        if (pendingData.catDispatcher_pendingCat && 
            pendingData.catDispatcher_pendingCatTimestamp &&
            (Date.now() - pendingData.catDispatcher_pendingCatTimestamp) < maxAge) {
          sendResponse({ 
            success: true, 
            catName: pendingData.catDispatcher_pendingCat 
          });
          // Pulisci dopo aver letto
          await chrome.storage.local.remove(['catDispatcher_pendingCat', 'catDispatcher_pendingCatTimestamp']);
        } else {
          sendResponse({ success: true, catName: null });
        }
        break;

      case 'OPEN_POPUP':
        // Apre il popup dell'estensione
        try {
          const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
          if (tabs[0]) {
            await chrome.action.openPopup();
            sendResponse({ success: true });
          } else {
            sendResponse({ success: false, error: 'Nessuna tab attiva' });
          }
        } catch (error) {
          console.error('[CAT Dispatcher BG] Errore apertura popup:', error);
          sendResponse({ success: false, error: error.message });
        }
        break;

      default:
        sendResponse({ 
          success: false, 
          error: `Azione sconosciuta: ${request.action}` 
        });
    }
  })();

  // Ritorna true per risposta asincrona
  return true;
});

// ============================================================================
// SISTEMA AGGIORNAMENTI
// ============================================================================

const CURRENT_VERSION = '1.6.0';
const UPDATE_CHECK_URL = 'https://catdispatcher.it/extension-version.json';
const UPDATE_CHECK_INTERVAL = 6 * 60 * 60 * 1000; // 6 ore

/**
 * Controlla se è disponibile una nuova versione dell'estensione
 */
async function checkForUpdates() {
  try {
    console.log('[CAT Dispatcher] Controllo aggiornamenti...');
    
    const response = await fetch(UPDATE_CHECK_URL, {
      cache: 'no-cache'
    });
    
    if (!response.ok) {
      console.log('[CAT Dispatcher] Impossibile controllare aggiornamenti');
      return null;
    }
    
    const data = await response.json();
    const latestVersion = data.version;
    
    console.log('[CAT Dispatcher] Versione corrente:', CURRENT_VERSION);
    console.log('[CAT Dispatcher] Ultima versione:', latestVersion);
    
    if (isNewerVersion(latestVersion, CURRENT_VERSION)) {
      console.log('[CAT Dispatcher] Nuova versione disponibile!');
      
      // Salva info aggiornamento
      await chrome.storage.local.set({
        catDispatcher_updateAvailable: true,
        catDispatcher_latestVersion: latestVersion,
        catDispatcher_updateUrl: data.downloadUrl || 'https://catdispatcher.it/install-extension.html',
        catDispatcher_updateNotes: data.notes || ''
      });
      
      // Mostra notifica
      chrome.notifications.create('update-available', {
        type: 'basic',
        iconUrl: 'icons/icon128.png',
        title: 'Aggiornamento CAT Dispatcher',
        message: `È disponibile la versione ${latestVersion}. Clicca per aggiornare.`,
        priority: 2
      });
      
      return {
        available: true,
        version: latestVersion,
        notes: data.notes
      };
    }
    
    // Nessun aggiornamento
    await chrome.storage.local.set({
      catDispatcher_updateAvailable: false
    });
    
    return { available: false };
  } catch (error) {
    console.error('[CAT Dispatcher] Errore controllo aggiornamenti:', error);
    return null;
  }
}

/**
 * Confronta due versioni semver
 */
function isNewerVersion(latest, current) {
  const latestParts = latest.split('.').map(Number);
  const currentParts = current.split('.').map(Number);
  
  for (let i = 0; i < 3; i++) {
    if (latestParts[i] > currentParts[i]) return true;
    if (latestParts[i] < currentParts[i]) return false;
  }
  return false;
}

// Listener per click su notifica
chrome.notifications.onClicked.addListener((notificationId) => {
  if (notificationId === 'update-available') {
    chrome.tabs.create({ url: 'https://catdispatcher.it/install-extension.html' });
  }
});

// ============================================================================
// EVENTI ESTENSIONE
// ============================================================================

// Evento installazione/aggiornamento
chrome.runtime.onInstalled.addListener(async (details) => {
  console.log('[CAT Dispatcher] Estensione installata/aggiornata:', details.reason);
  
  // Controlla aggiornamenti all'avvio
  checkForUpdates();
  
  // Pulisce la cache scaduta
  cleanExpiredCache();
  
  // Inietta il content script nelle tab ACT e catdispatcher.it già aperte
  // Permette sync sessione subito dopo installazione e evita ricarica dopo aggiornamento
  try {
    const [actTabs, siteTabs] = await Promise.all([
      chrome.tabs.query({ url: 'https://act.jfish.it/*' }),
      chrome.tabs.query({ url: 'https://catdispatcher.it/*' })
    ]);
    
    for (const tab of actTabs) {
      try {
        await chrome.scripting.executeScript({
          target: { tabId: tab.id, allFrames: true },
          files: ['content-script.js']
        });
        console.log('[CAT Dispatcher] Content script iniettato in tab ACT:', tab.id);
      } catch (e) {
        console.warn('[CAT Dispatcher] Impossibile iniettare in tab', tab.id, ':', e.message);
      }
    }
    
    for (const tab of siteTabs) {
      try {
        await chrome.scripting.executeScript({
          target: { tabId: tab.id },
          files: ['content-script.js']
        });
        console.log('[CAT Dispatcher] Content script iniettato in tab catdispatcher.it:', tab.id);
      } catch (e) {
        console.warn('[CAT Dispatcher] Impossibile iniettare in tab', tab.id, ':', e.message);
      }
    }
  } catch (e) {
    console.warn('[CAT Dispatcher] Errore iniezione automatica:', e);
  }
});

// Controlla aggiornamenti periodicamente
chrome.alarms.create('check-updates', { periodInMinutes: 360 }); // Ogni 6 ore

// Controlla versione sospensioni ogni 4 ore (08:00-19:00)
// Ridotto da 1 ora a 4 ore per ottimizzare costi Cloud (~75% risparmio su questa chiamata)
chrome.alarms.create('check-suspensions', { periodInMinutes: 240 }); // Ogni 4 ore

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'check-updates') {
    checkForUpdates();
  } else if (alarm.name === 'check-suspensions') {
    // Controlla sospensioni (la funzione verifica internamente l'orario)
    checkSuspensionsVersion(false);
  }
});

console.log('[CAT Dispatcher] Background service worker avviato, versione:', CURRENT_VERSION);
