/**
 * PerX JFish Sync - Background Service Worker
 * Gestisce autenticazione Google OAuth2 e comunicazione con Hub
 */

import { HubClient } from './hub-client.js';

// Configurazione Hub
const HUB_CONFIG = {
  // URL base dell'Hub via TailScale (HTTPS su porta 443 default)
  baseUrl: 'https://mac-mini-di-massimo.tailca58be.ts.net'
};

// Stato globale
let currentUser = null;
let hubClient = null;

/**
 * Inizializza l'estensione
 */
async function init() {
  console.log('[PerX] Inizializzazione estensione...');
  
  // Carica configurazione salvata
  const config = await chrome.storage.local.get(['hubUrl', 'userEmail', 'userName', 'userPicture', 'authToken']);
  
  if (config.hubUrl) {
    HUB_CONFIG.baseUrl = config.hubUrl;
  }
  
  // Ripristina sessione utente se presente
  if (config.userEmail) {
    currentUser = {
      email: config.userEmail,
      name: config.userName || config.userEmail,
      picture: config.userPicture || null,
      token: config.authToken
    };
    console.log('[PerX] Sessione ripristinata:', currentUser.email);
  }
  
  // Inizializza client Hub (HTTPS via Tailscale, porta 443 default)
  hubClient = new HubClient(HUB_CONFIG.baseUrl);
  
  if (currentUser) {
    hubClient.setUserEmail(currentUser.email);
  }
  
  console.log('[PerX] Estensione inizializzata');
}

// Configurazione OAuth
const OAUTH_CONFIG = {
  clientId: '150443834793-5h6bjhh03bcd4mmj8hijkugq50brp53i.apps.googleusercontent.com',
  scopes: ['openid', 'email', 'profile'],
  redirectUri: `https://${chrome.runtime.id}.chromiumapp.org/`
};

/**
 * Effettua login con Google OAuth2 tramite popup
 * @returns {Promise<{email: string, name: string}>}
 */
async function googleSignIn() {
  // Costruisci URL di autorizzazione
  const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  authUrl.searchParams.set('client_id', OAUTH_CONFIG.clientId);
  authUrl.searchParams.set('redirect_uri', OAUTH_CONFIG.redirectUri);
  authUrl.searchParams.set('response_type', 'token');
  authUrl.searchParams.set('scope', OAUTH_CONFIG.scopes.join(' '));
  authUrl.searchParams.set('prompt', 'select_account');
  
  return new Promise((resolve, reject) => {
    chrome.identity.launchWebAuthFlow(
      {
        url: authUrl.toString(),
        interactive: true
      },
      async (redirectUrl) => {
        if (chrome.runtime.lastError) {
          console.error('[PerX] Errore OAuth:', chrome.runtime.lastError.message);
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        
        if (!redirectUrl) {
          reject(new Error('Autenticazione annullata'));
          return;
        }
        
        try {
          // Estrai access token dalla URL
          const url = new URL(redirectUrl);
          const hashParams = new URLSearchParams(url.hash.substring(1));
          const accessToken = hashParams.get('access_token');
          
          if (!accessToken) {
            throw new Error('Token non trovato nella risposta');
          }
          
          // Ottieni info utente da Google
          const response = await fetch(
            'https://www.googleapis.com/oauth2/v2/userinfo',
            {
              headers: { Authorization: `Bearer ${accessToken}` }
            }
          );
          
          if (!response.ok) {
            throw new Error('Errore recupero info utente');
          }
          
          const userInfo = await response.json();
          
          currentUser = {
            email: userInfo.email,
            name: userInfo.name,
            picture: userInfo.picture,
            token: accessToken
          };
          
          // Salva in storage
          await chrome.storage.local.set({
            userEmail: currentUser.email,
            userName: currentUser.name,
            userPicture: currentUser.picture,
            authToken: accessToken
          });
          
          // Configura client Hub con email utente
          if (hubClient) {
            hubClient.setUserEmail(currentUser.email);
          }
          
          console.log('[PerX] Login effettuato:', currentUser.email);
          resolve(currentUser);
          
        } catch (error) {
          console.error('[PerX] Errore fetch userinfo:', error);
          reject(error);
        }
      }
    );
  });
}

/**
 * Effettua logout
 */
async function signOut() {
  try {
    // Recupera token salvato
    const stored = await chrome.storage.local.get(['authToken']);
    
    if (stored.authToken) {
      // Revoca il token su Google
      await fetch(`https://accounts.google.com/o/oauth2/revoke?token=${stored.authToken}`);
    }
    
    // Pulisci storage locale
    await chrome.storage.local.remove(['userEmail', 'userName', 'userPicture', 'authToken']);
    
    currentUser = null;
    
    console.log('[PerX] Logout effettuato');
  } catch (error) {
    console.error('[PerX] Errore logout:', error);
    // Pulisci comunque lo storage locale
    await chrome.storage.local.remove(['userEmail', 'userName', 'userPicture', 'authToken']);
    currentUser = null;
  }
}

/**
 * Verifica stato autenticazione
 * Non verifica il token ad ogni chiamata per evitare disconnessioni frequenti
 * @returns {Promise<{authenticated: boolean, user: object|null}>}
 */
async function checkAuth() {
  // Se abbiamo già l'utente in memoria, usalo direttamente
  if (currentUser && currentUser.email) {
    return { authenticated: true, user: currentUser };
  }
  
  // Controlla storage locale
  const stored = await chrome.storage.local.get(['userEmail', 'userName', 'userPicture', 'authToken']);
  
  if (stored.userEmail) {
    // Ricostruisci utente dai dati salvati senza verificare il token
    currentUser = {
      email: stored.userEmail,
      name: stored.userName || stored.userEmail,
      picture: stored.userPicture || null,
      token: stored.authToken
    };
    
    if (hubClient) {
      hubClient.setUserEmail(currentUser.email);
    }
    
    console.log('[PerX] Sessione ripristinata per:', currentUser.email);
    return { authenticated: true, user: currentUser };
  }
  
  // Non autenticato
  currentUser = null;
  return { authenticated: false, user: null };
}

/**
 * Verifica se il token è ancora valido (chiamato solo quando necessario)
 * @returns {Promise<boolean>}
 */
async function validateToken() {
  if (!currentUser?.token) return false;
  
  try {
    const response = await fetch(
      'https://www.googleapis.com/oauth2/v2/userinfo',
      { headers: { Authorization: `Bearer ${currentUser.token}` } }
    );
    return response.ok;
  } catch {
    return false;
  }
}

/**
 * Rinnova il token se scaduto (richiede nuovo login)
 * @returns {Promise<boolean>}
 */
async function refreshTokenIfNeeded() {
  const isValid = await validateToken();
  if (isValid) return true;
  
  // Token scaduto, richiedi nuovo login
  console.log('[PerX] Token scaduto, richiedo nuovo login...');
  try {
    await googleSignIn();
    return true;
  } catch (error) {
    console.error('[PerX] Errore refresh token:', error);
    return false;
  }
}

/**
 * Verifica connessione con Hub
 * @returns {Promise<{connected: boolean, version: string|null}>}
 */
async function checkHubConnection() {
  if (!hubClient) {
    return { connected: false, version: null, error: 'Client non inizializzato' };
  }
  
  try {
    const health = await hubClient.health();
    return { connected: true, version: health.version, uptime: health.uptime };
  } catch (error) {
    return { connected: false, version: null, error: error.message };
  }
}

/**
 * Gestisce messaggi dal popup e content script
 */
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('[PerX] Messaggio ricevuto:', message.action);
  
  // Gestione asincrona
  (async () => {
    try {
      switch (message.action) {
        
        // === Auth ===
        case 'signIn':
          const user = await googleSignIn();
          sendResponse({ success: true, user });
          break;
          
        case 'signOut':
          await signOut();
          sendResponse({ success: true });
          break;
          
        case 'checkAuth':
          const authStatus = await checkAuth();
          sendResponse(authStatus);
          break;
          
        // === Hub ===
        case 'checkHub':
          const hubStatus = await checkHubConnection();
          sendResponse(hubStatus);
          break;
          
        case 'setHubUrl':
          HUB_CONFIG.baseUrl = message.url;
          hubClient = new HubClient(message.url);
          if (currentUser) {
            hubClient.setUserEmail(currentUser.email);
          }
          await chrome.storage.local.set({ hubUrl: message.url });
          sendResponse({ success: true });
          break;
          
        // === Sinistri ===
        case 'getSinistro':
          if (!hubClient) throw new Error('Hub non connesso');
          const sinistro = await hubClient.getSinistro(message.ref);
          sendResponse({ success: true, data: sinistro });
          break;
          
        case 'getSinistri':
          if (!hubClient || !currentUser) throw new Error('Non autenticato');
          const sinistri = await hubClient.getSinistri(currentUser.email);
          sendResponse({ success: true, data: sinistri });
          break;
          
        case 'updateSinistro':
          if (!hubClient) throw new Error('Hub non connesso');
          await hubClient.updateSinistro(message.ref, message.data);
          sendResponse({ success: true });
          break;
          
        // === Diario ===
        case 'getDiario':
          if (!hubClient) throw new Error('Hub non connesso');
          const diario = await hubClient.getDiario(message.ref);
          sendResponse({ success: true, data: diario });
          break;
          
        case 'addDiarioEntry':
          if (!hubClient) throw new Error('Hub non connesso');
          await hubClient.addDiarioEntry(message.ref, message.entry);
          sendResponse({ success: true });
          break;
          
        // === JFish Sync ===
        case 'jfishCompare':
          if (!hubClient) throw new Error('Hub non connesso');
          const compareResult = await hubClient.jfishCompare(message.jfishData);
          sendResponse({ success: true, data: compareResult });
          break;
          
        case 'jfishGetSinistro':
          if (!hubClient) throw new Error('Hub non connesso');
          const jfishSinistro = await hubClient.jfishGetSinistro(message.ref);
          sendResponse({ success: true, data: jfishSinistro, found: jfishSinistro !== null });
          break;
          
        case 'jfishUpdateSinistro':
          if (!hubClient) throw new Error('Hub non connesso');
          const updateResult = await hubClient.jfishUpdateSinistro(message.ref, message.fields);
          sendResponse({ success: updateResult.success, data: updateResult });
          break;
          
        case 'jfishImportAll':
          if (!hubClient) throw new Error('Hub non connesso');
          const importResult = await hubClient.jfishImportAll(message.ref, message.jfishData);
          sendResponse({ success: importResult.success, data: importResult });
          break;
          
        case 'jfishGetDiario':
          if (!hubClient) throw new Error('Hub non connesso');
          const jfishDiario = await hubClient.jfishGetDiario(message.ref);
          sendResponse({ success: true, data: jfishDiario });
          break;
          
        case 'jfishSyncDiario':
          if (!hubClient) throw new Error('Hub non connesso');
          const diarioResult = await hubClient.jfishSyncDiario(message.ref, message.entries);
          sendResponse({ success: diarioResult.success, data: diarioResult });
          break;
          
        // === Sync ===
        case 'syncField':
          if (!hubClient) throw new Error('Hub non connesso');
          await hubClient.updateSinistroField(message.ref, message.field, message.value);
          sendResponse({ success: true });
          break;
          
        // === Page Change (relay to popup) ===
        case 'pageChanged':
          // Il content script notifica un cambio pagina
          // Broadcast a tutti i popup aperti (non fa nulla se il popup è chiuso)
          console.log('[PerX] Cambio pagina rilevato:', message.sinistroId);
          
          // Salva lo stato corrente per quando il popup si apre
          await chrome.storage.local.set({
            currentSinistroId: message.sinistroId,
            currentSinistroRef: message.sinistroRef,
            isDetailPage: message.isDetailPage
          });
          
          sendResponse({ success: true });
          break;
          
        default:
          sendResponse({ success: false, error: 'Azione sconosciuta' });
      }
    } catch (error) {
      console.error('[PerX] Errore:', error);
      sendResponse({ success: false, error: error.message });
    }
  })();
  
  // Indica che la risposta sarà asincrona
  return true;
});

/**
 * Gestisce click sull'icona estensione
 */
chrome.action.onClicked.addListener((tab) => {
  // Il popup si apre automaticamente, questo è solo per eventuali azioni aggiuntive
  console.log('[PerX] Click su icona, tab:', tab.url);
});

/**
 * Gestisce installazione/aggiornamento estensione
 */
chrome.runtime.onInstalled.addListener(async (details) => {
  console.log('[PerX] Installazione:', details.reason);
  
  if (details.reason === 'install') {
    // Prima installazione
    console.log('[PerX] Benvenuto! Configura l\'estensione dal popup.');
  } else if (details.reason === 'update') {
    console.log('[PerX] Aggiornato alla versione', chrome.runtime.getManifest().version);
  }
  
  // Inietta content script nelle tab JFish già aperte
  await injectContentScriptInExistingTabs();
});

/**
 * Gestisce avvio di Chrome (quando ci sono tab già aperte)
 */
chrome.runtime.onStartup.addListener(async () => {
  console.log('[PerX] Chrome avviato, controllo tab esistenti...');
  await injectContentScriptInExistingTabs();
});

/**
 * Inietta il content script nelle tab JFish già aperte
 * Usato quando l'estensione viene installata/aggiornata con pagine già aperte
 */
async function injectContentScriptInExistingTabs() {
  try {
    // Cerca tutte le tab che matchano JFish
    const tabs = await chrome.tabs.query({ url: 'https://act.jfish.it/*' });
    
    console.log(`[PerX] Trovate ${tabs.length} tab JFish aperte`);
    
    for (const tab of tabs) {
      if (!tab.id) continue;
      
      try {
        // Verifica se il content script è già iniettato
        const results = await chrome.tabs.sendMessage(tab.id, { action: 'ping' }).catch(() => null);
        
        if (results) {
          console.log(`[PerX] Tab ${tab.id} già ha il content script`);
          continue;
        }
        
        console.log(`[PerX] Iniettando content script in tab ${tab.id}: ${tab.url}`);
        
        // Inietta prima il CSS
        await chrome.scripting.insertCSS({
          target: { tabId: tab.id },
          files: ['content-styles.css']
        });
        
        // Poi inietta il JS
        await chrome.scripting.executeScript({
          target: { tabId: tab.id },
          files: ['content.js']
        });
        
        console.log(`[PerX] Content script iniettato in tab ${tab.id}`);
        
      } catch (error) {
        console.warn(`[PerX] Errore iniezione tab ${tab.id}:`, error.message);
      }
    }
  } catch (error) {
    console.error('[PerX] Errore ricerca tab:', error);
  }
}

// Inizializza al caricamento
init();
