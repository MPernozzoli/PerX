/**
 * Popup Script per ACT CAT Dispatcher
 * 
 * Gestisce:
 * - Autenticazione utente via Google OAuth
 * - Comunicazione con il content script per leggere/scrivere dati
 * - Chiamate API tramite il background script
 * - Aggiornamento dell'interfaccia utente
 */

// ============================================================================
// ELEMENTI DOM
// ============================================================================

const elements = {
  // Contenitori principali
  loading: document.getElementById('loading'),
  mainContent: document.getElementById('main-content'),
  invalidPage: document.getElementById('invalid-page'),
  loginForm: document.getElementById('login-form'),
  wrongSite: document.getElementById('wrong-site'),
  
  // Info utente
  userInfo: document.getElementById('user-info'),
  userEmail: document.getElementById('user-email'),
  btnLogout: document.getElementById('btn-logout'),
  
  // Login Google
  btnLoginGoogle: document.getElementById('btn-login-google'),
  
  // Messaggi
  errorMessage: document.getElementById('error-message'),
  errorText: document.getElementById('error-text'),
  successMessage: document.getElementById('success-message'),
  successText: document.getElementById('success-text'),
  
  // Dati ubicazione
  dataIndirizzo: document.getElementById('data-indirizzo'),
  dataCitta: document.getElementById('data-citta'),
  dataProvincia: document.getElementById('data-provincia'),
  
  // CAT corrente
  catLabel: document.getElementById('cat-label'),
  catStatusPill: document.getElementById('cat-status-pill'),
  
  // Fallback per copia manuale
  catFallbackBox: document.getElementById('cat-fallback-box'),
  catFallbackName: document.getElementById('cat-fallback-name'),
  btnCopyCat: document.getElementById('btn-copy-cat'),
  
  // Sospensione CAT
  catSuspendedBox: document.getElementById('cat-suspended-box'),
  suspendedMessage: document.getElementById('suspended-message'),
  btnAssignAnyway: document.getElementById('btn-assign-anyway'),
  actionsSection: document.getElementById('actions-section'),
  
  // Sinistro
  sinistroId: document.getElementById('sinistro-id'),
  btnRefreshInline: document.getElementById('btn-refresh-inline'),
  
  // Pulsanti
  btnAssignPostgrest: document.getElementById('btn-assign-postgrest'),
  btnOpenMap: document.getElementById('btn-open-map')
};

// Stato globale
let currentData = null;
let currentTabId = null;
let currentUser = null;

// ============================================================================
// FUNZIONI UI
// ============================================================================

/**
 * Nasconde tutte le sezioni principali
 */
function hideAllSections() {
  elements.loading.classList.add('hidden');
  elements.mainContent.classList.add('hidden');
  elements.invalidPage.classList.add('hidden');
  elements.loginForm.classList.add('hidden');
  elements.wrongSite.classList.add('hidden');
  elements.userInfo.classList.add('hidden');
}

/**
 * Mostra lo spinner di caricamento
 */
function showLoading() {
  hideAllSections();
  elements.loading.classList.remove('hidden');
  hideMessages();
}

/**
 * Mostra il contenuto principale (utente loggato + pagina valida)
 */
function showMainContent() {
  hideAllSections();
  elements.mainContent.classList.remove('hidden');
  if (currentUser) {
    elements.userInfo.classList.remove('hidden');
    elements.userEmail.textContent = currentUser.email;
  }
}

/**
 * Mostra il form di login
 */
function showLoginForm() {
  hideAllSections();
  elements.loginForm.classList.remove('hidden');
}

/**
 * Mostra messaggio pagina non valida (utente loggato ma pagina sbagliata)
 */
function showInvalidPage() {
  hideAllSections();
  elements.invalidPage.classList.remove('hidden');
  if (currentUser) {
    elements.userInfo.classList.remove('hidden');
    elements.userEmail.textContent = currentUser.email;
  }
}

/**
 * Mostra messaggio sito non supportato
 */
function showWrongSite() {
  hideAllSections();
  elements.wrongSite.classList.remove('hidden');
  if (currentUser) {
    elements.userInfo.classList.remove('hidden');
    elements.userEmail.textContent = currentUser.email;
  }
}

/**
 * Nasconde tutti i messaggi di stato
 */
function hideMessages() {
  elements.errorMessage.classList.add('hidden');
  elements.successMessage.classList.add('hidden');
}

/**
 * Mostra un messaggio di errore
 * @param {string} message - Testo dell'errore
 */
function showError(message) {
  elements.errorText.textContent = message;
  elements.errorMessage.classList.remove('hidden');
  elements.successMessage.classList.add('hidden');
  
  // Auto-hide dopo 10 secondi (tempo maggiore per leggere messaggi dettagliati)
  setTimeout(() => {
    elements.errorMessage.classList.add('hidden');
  }, 10000);
}

/**
 * Mostra un messaggio di successo
 * @param {string} message - Testo del messaggio
 */
function showSuccess(message) {
  elements.successText.textContent = message;
  elements.successMessage.classList.remove('hidden');
  elements.errorMessage.classList.add('hidden');
  
  // Auto-hide dopo 8 secondi (più lungo per conferma visiva)
  setTimeout(() => {
    elements.successMessage.classList.add('hidden');
  }, 8000);
}

/**
 * Aggiorna l'interfaccia con i dati ricevuti
 * @param {Object} data - Dati dalla pagina
 */
function updateUI(data) {
  currentData = data;
  
  // Aggiorna ID Sinistro
  elements.sinistroId.textContent = data.idSinistro || '-';
  
  // Aggiorna ubicazione
  const ub = data.ubicazione || {};
  elements.dataIndirizzo.textContent = ub.indirizzo || '-';
  elements.dataCitta.textContent = ub.citta || '-';
  elements.dataProvincia.textContent = ub.provincia || '-';
  
  // Reset stato CAT
  elements.catStatusPill.classList.add('hidden');
  elements.catStatusPill.classList.remove('success', 'error');
  elements.catFallbackBox.classList.add('hidden');
  
  // Aggiorna CAT corrente
  const cat = data.catCorrente;
  if (cat && cat.label) {
    const label = cat.label.trim();
    const isEmptyOrInvalid = !label || 
                             label === '(Nessun CAT selezionato)' || 
                             label.toLowerCase() === 'sì' ||
                             label.toLowerCase() === 'si' ||
                             label === '-';
    
    if (isEmptyOrInvalid) {
      elements.catLabel.textContent = 'Nessun CAT assegnato';
    } else {
      elements.catLabel.textContent = label;
    }
  } else {
    elements.catLabel.textContent = 'Nessun CAT assegnato';
  }
}

/**
 * Mostra la pill di successo
 */
function showSuccessPill() {
  elements.catStatusPill.textContent = 'Assegnato';
  elements.catStatusPill.classList.remove('hidden', 'error');
  elements.catStatusPill.classList.add('success');
  elements.catFallbackBox.classList.add('hidden');
}

/**
 * Mostra la pill di errore e il box per copia manuale
 * @param {string} catName - Nome del CAT da copiare
 */
function showErrorPill(catName) {
  elements.catStatusPill.textContent = 'Fallito';
  elements.catStatusPill.classList.remove('hidden', 'success');
  elements.catStatusPill.classList.add('error');
  
  // Mostra box fallback
  elements.catFallbackName.textContent = catName;
  elements.catFallbackBox.classList.remove('hidden');
}

/**
 * Abilita/disabilita i pulsanti
 * @param {boolean} enabled - Stato abilitazione
 */
function setButtonsEnabled(enabled) {
  elements.btnAssignPostgrest.disabled = !enabled;
  elements.btnOpenMap.disabled = !enabled;
}

// ============================================================================
// COMUNICAZIONE
// ============================================================================

/**
 * Inietta il content script in tutti i frame della tab
 * @returns {Promise<boolean>} true se l'iniezione è riuscita
 */
async function injectContentScriptIfNeeded() {
  console.log('[CAT Dispatcher Popup] Iniezione content script in tab', currentTabId);
  try {
    const result = await chrome.scripting.executeScript({
      target: { tabId: currentTabId, allFrames: true },
      files: ['content-script.js']
    });
    console.log('[CAT Dispatcher Popup] Content script iniettato in', result.length, 'frame');
    await new Promise(resolve => setTimeout(resolve, 500));
    return true;
  } catch (error) {
    console.error('[CAT Dispatcher Popup] Errore iniezione:', error.message);
    return false;
  }
}

/**
 * Invia un messaggio a TUTTI i frame e restituisce la prima risposta valida
 * @param {Object} message - Messaggio da inviare
 * @returns {Promise<Object>} Risposta dal content script
 */
async function sendToContentScript(message) {
  // Ottieni tutti i frame della tab
  const frames = await chrome.webNavigation.getAllFrames({ tabId: currentTabId });
  console.log('[CAT Dispatcher Popup] Invio messaggio a', frames.length, 'frame...');
  
  // Invia a tutti i frame in parallelo e raccogli le risposte
  const responses = await Promise.all(
    frames.map(frame => 
      new Promise((resolve) => {
        chrome.tabs.sendMessage(currentTabId, message, { frameId: frame.frameId }, (resp) => {
          if (chrome.runtime.lastError) {
            resolve(null);
          } else {
            resolve({ frameId: frame.frameId, response: resp });
          }
        });
      })
    )
  );
  
  // Trova la prima risposta valida con isValidPage: true
  for (const item of responses) {
    if (item?.response?.success && item?.response?.data?.isValidPage) {
      console.log('[CAT Dispatcher Popup] Risposta valida dal frame', item.frameId);
      return item.response;
    }
  }
  
  // Nessun frame ha una pagina valida
  console.log('[CAT Dispatcher Popup] Nessun frame con pagina sinistro valida');
  return {
    success: true,
    data: { isValidPage: false }
  };
}

/**
 * Invia un messaggio al background script
 * @param {Object} message - Messaggio da inviare
 * @returns {Promise<Object>} Risposta dal background script
 */
async function sendToBackground(message) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(message, (response) => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      } else {
        resolve(response);
      }
    });
  });
}

// ============================================================================
// AUTENTICAZIONE
// ============================================================================

/**
 * Verifica lo stato di autenticazione
 * @returns {Promise<Object>} Stato auth
 */
async function checkAuth() {
  const response = await sendToBackground({ action: 'AUTH_CHECK' });
  return response;
}

/**
 * Effettua il login con Google
 */
async function handleGoogleLogin() {
  elements.btnLoginGoogle.disabled = true;
  elements.btnLoginGoogle.innerHTML = `
    <div class="spinner" style="width: 18px; height: 18px; border-width: 2px;"></div>
    Accesso in corso...
  `;
  hideMessages();
  
  try {
    const response = await sendToBackground({ action: 'AUTH_LOGIN_GOOGLE' });
    
    if (!response.success) {
      throw new Error(response.error || 'Errore durante il login');
    }
    
    currentUser = response.user;
    showSuccess('Login effettuato!');
    
    // Ricarica per mostrare il contenuto principale
    await loadPageData();
    
  } catch (error) {
    console.error('[CAT Dispatcher Popup] Errore login:', error);
    showError(error.message);
    showLoginForm();
  } finally {
    elements.btnLoginGoogle.disabled = false;
    elements.btnLoginGoogle.innerHTML = `
      <svg class="google-icon" viewBox="0 0 24 24" width="20" height="20">
        <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
        <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
        <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
        <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
      </svg>
      Accedi con Google
    `;
  }
}

/**
 * Effettua il logout
 */
async function handleLogout() {
  try {
    await sendToBackground({ action: 'AUTH_LOGOUT' });
    currentUser = null;
    showLoginForm();
    showSuccess('Logout effettuato');
  } catch (error) {
    console.error('[CAT Dispatcher Popup] Errore logout:', error);
    showError(error.message);
  }
}

// ============================================================================
// CARICAMENTO DATI
// ============================================================================

/**
 * Carica i dati dalla pagina corrente
 * @param {boolean} refreshSuspensions - Se true, forza il refresh della cache sospensioni
 */
async function loadPageData(refreshSuspensions = false) {
  showLoading();
  
  // Verifica se c'è un errore pendente dal pulsante rapido
  const pendingError = await chrome.storage.local.get('catDispatcher_pendingError');
  if (pendingError.catDispatcher_pendingError) {
    // Pulisci l'errore pendente
    await chrome.storage.local.remove('catDispatcher_pendingError');
    
    // Se c'è un errore pendente, carica i dati e poi mostra l'errore/esegui assegnazione
    const errorData = pendingError.catDispatcher_pendingError;
    
    // Carica i dati normalmente prima
    try {
      await loadPageDataInternal(refreshSuspensions);
      
      // Se c'è un CAT sospeso, mostra la box di sospensione
      if (errorData.suspended && errorData.data) {
        currentSuspendedCat = errorData.data;
        showSuspensionBox(errorData.data);
        return;
      }
      
      // Se abbiamo un errore, mostra l'errore e simula il click sul pulsante per mostrare lo stato
      if (errorData.error) {
        // Mostra l'errore come se avessimo premuto il pulsante
        setButtonsEnabled(false);
        hideMessages();
        hideSuspensionBox();
        showError(errorData.error);
        setButtonsEnabled(true);
        return;
      }
      
      // Se non c'è errore ma abbiamo i dati, esegui l'assegnazione
      if (currentData?.ubicazione) {
        await handleAssignPostgrest();
      }
    } catch (e) {
      // Se il caricamento fallisce, mostra comunque l'errore
      console.error('[CAT Dispatcher Popup] Errore caricamento con errore pendente:', e);
      showError(errorData.error || 'Errore sconosciuto');
      showInvalidPage();
    }
    return;
  }
  
  // Nessun errore pendente, carica normalmente
  await loadPageDataInternal(refreshSuspensions);
}

/**
 * Carica i dati dalla pagina corrente (implementazione interna)
 * @param {boolean} refreshSuspensions - Se true, forza il refresh della cache sospensioni
 */
async function loadPageDataInternal(refreshSuspensions = false) {
  try {
    // 0. Se richiesto, aggiorna la cache sospensioni
    if (refreshSuspensions) {
      console.log('[CAT Dispatcher Popup] Refresh cache sospensioni...');
      try {
        const refreshResult = await sendToBackground({ action: 'REFRESH_SUSPENSIONS' });
        if (refreshResult?.cacheInvalidated) {
          console.log('[CAT Dispatcher Popup] Cache sospensioni aggiornata');
        }
      } catch (e) {
        console.warn('[CAT Dispatcher Popup] Errore refresh sospensioni:', e);
      }
    }
    
    // 1. Verifica autenticazione Cat Dispatcher
    console.log('[CAT Dispatcher Popup] Step 1: Verifica auth...');
    const authStatus = await checkAuth();
    
    if (!authStatus.isLoggedIn) {
      console.log('[CAT Dispatcher Popup] Non autenticato, mostro login');
      showLoginForm();
      return;
    }
    
    currentUser = authStatus.user;
    console.log('[CAT Dispatcher Popup] Step 2: Autenticato come', currentUser.email);
    
    // 2. Ottieni la tab attiva
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    
    if (!tab) {
      throw new Error('Nessuna tab attiva trovata');
    }
    
    currentTabId = tab.id;
    console.log('[CAT Dispatcher Popup] Step 3: Tab attiva:', tab.url);
    
    // 3. Verifica che siamo su ACT
    if (!tab.url?.includes('act.jfish.it')) {
      console.log('[CAT Dispatcher Popup] Non su ACT, mostro wrong site');
      showWrongSite();
      return;
    }
    
    // 4. Richiedi dati al content script
    console.log('[CAT Dispatcher Popup] Step 4: Invio GET_PAGE_DATA al content script...');
    const response = await sendToContentScript({ action: 'GET_PAGE_DATA' });
    console.log('[CAT Dispatcher Popup] Step 5: Risposta content script:', response);
    
    if (!response?.success) {
      throw new Error(response?.message || 'Errore nella lettura dei dati');
    }
    
    if (!response.data.isValidPage) {
      console.log('[CAT Dispatcher Popup] Pagina non valida, isValidPage =', response.data.isValidPage);
      showInvalidPage();
      return;
    }
    
    // 5. Aggiorna UI con i dati
    console.log('[CAT Dispatcher Popup] Step 6: Pagina valida, mostro contenuto');
    updateUI(response.data);
    showMainContent();
    
  } catch (error) {
    console.error('[CAT Dispatcher Popup] Errore:', error);
    
    // Content script non caricato
    if (error.message.includes('Could not establish connection') ||
        error.message.includes('Receiving end does not exist')) {
      showError('Ricarica la pagina ACT e riprova');
      showInvalidPage();
    } else {
      showError(error.message);
      showInvalidPage();
    }
  }
}

// ============================================================================
// GESTORI EVENTI PULSANTI
// ============================================================================

// Stato per gestire la sospensione
let currentSuspendedCat = null;

/**
 * Handler per "Assegna CAT automaticamente"
 */
async function handleAssignPostgrest() {
  if (!currentData?.ubicazione) {
    showError('Dati ubicazione non disponibili');
    return;
  }
  
  setButtonsEnabled(false);
  hideMessages();
  hideSuspensionBox();
  
  let catAlias = null;
  let catDisplayName = null;
  
  try {
    // Chiama l'API tramite background script
    const apiResponse = await sendToBackground({
      action: 'API_GET_CAT',
      ubicazione: currentData.ubicazione
    });
    
    // Gestione CAT sospeso
    if (apiResponse?.suspended) {
      const catData = apiResponse.data;
      console.log('[CAT Dispatcher Popup] CAT sospeso:', catData);
      
      currentSuspendedCat = catData;
      showSuspensionBox(catData);
      setButtonsEnabled(true);
      return;
    }
    
    if (!apiResponse?.success) {
      if (apiResponse?.error === 'NOT_LOGGED_IN') {
        showLoginForm();
        return;
      }
      throw new Error(apiResponse?.error || 'Errore nella chiamata API');
    }
    
    const catData = apiResponse.data;
    
    if (!catData?.cat_name && !catData?.cat_alias) {
      throw new Error('Nome CAT non trovato nella risposta');
    }
    
    // Usa l'alias JFISH se disponibile, altrimenti il nome
    catAlias = catData.cat_alias || catData.cat_name;
    catDisplayName = catData.cat_name;
    console.log('[CAT Dispatcher Popup] CAT da assegnare:', catAlias, '(display:', catDisplayName, ')');
    
    await assignCatToPage(catAlias, catDisplayName);
    
  } catch (error) {
    console.error('[CAT Dispatcher Popup] Errore assegnazione:', error);
    if (catAlias) {
      showErrorPill(catAlias);
      showError('Errore. Copia il CAT e inseriscilo manualmente.');
    } else {
      showError(error.message);
    }
  } finally {
    setButtonsEnabled(true);
  }
}

/**
 * Assegna il CAT alla pagina
 */
async function assignCatToPage(catAlias, catDisplayName) {
  // Invia comando al content script per impostare il CAT usando l'alias JFISH
  const setResponse = await sendToContentScript({
    action: 'SET_CAT_BY_LABEL',
    label: catAlias
  });
  
  if (!setResponse?.success) {
    // Assegnazione fallita - mostra pill rossa e box copia
    showErrorPill(catAlias);
    showError(`Impossibile assegnare "${catAlias}". Copialo e inseriscilo manualmente nel campo Assegna CAT.`);
    return;
  }
  
  // Verifica che l'assegnazione sia andata a buon fine rileggendo i dati
  // Attendi un po' più a lungo per dare tempo al framework Syncfusion
  await new Promise(resolve => setTimeout(resolve, 500));
  const verifyResponse = await sendToContentScript({ action: 'GET_PAGE_DATA' });
  
  if (verifyResponse?.success && verifyResponse?.data?.catCorrente) {
    const assignedCat = verifyResponse.data.catCorrente.label?.trim() || '';
    
    // Verifica che il CAT assegnato corrisponda
    if (assignedCat && assignedCat.toLowerCase() === catAlias.toLowerCase()) {
      // Successo! Mostra pill verde
      elements.catLabel.textContent = assignedCat;
      showSuccessPill();
      showSuccess(`CAT assegnato: ${catDisplayName}`);
    } else if (assignedCat && assignedCat.length > 0 && 
               assignedCat !== 'Nessun CAT assegnato' &&
               assignedCat.toLowerCase() !== 'sì' &&
               assignedCat.toLowerCase() !== 'si') {
      // Un CAT è stato assegnato (potrebbe essere diverso per formattazione)
      // Verifica che non sia completamente diverso
      const aliasNorm = catAlias.toLowerCase().replace(/\s+/g, '');
      const assignedNorm = assignedCat.toLowerCase().replace(/\s+/g, '');
      
      if (aliasNorm.includes(assignedNorm) || assignedNorm.includes(aliasNorm) || 
          assignedNorm.startsWith(aliasNorm.substring(0, 5))) {
        // Sembrano corrispondere (magari con differenze minori)
        elements.catLabel.textContent = assignedCat;
        showSuccessPill();
        showSuccess(`CAT assegnato: ${assignedCat}`);
      } else {
        // Il valore impostato è diverso da quello atteso
        console.warn('[CAT Dispatcher] Mismatch CAT:', { atteso: catAlias, trovato: assignedCat });
        showAssignmentMismatchError(catAlias, assignedCat);
      }
    } else {
      // Il campo è ancora vuoto - fallimento
      showErrorPill(catAlias);
      showError(`Impossibile assegnare "${catAlias}". Copialo e inseriscilo manualmente nel campo Assegna CAT.`);
    }
  } else {
    // Non riesco a verificare - mostra errore invece di assumere successo
    console.warn('[CAT Dispatcher] Verifica fallita, risposta:', verifyResponse);
    showErrorPill(catAlias);
    showError(`Non è stato possibile verificare l'assegnazione di "${catAlias}". Controlla che sia stato impostato, altrimenti copialo e inseriscilo manualmente.`);
  }
}

/**
 * Mostra errore quando il valore impostato è diverso da quello atteso
 * @param {string} expected - CAT atteso
 * @param {string} found - CAT trovato nel campo
 */
function showAssignmentMismatchError(expected, found) {
  elements.catStatusPill.textContent = 'Verifica';
  elements.catStatusPill.classList.remove('hidden', 'success');
  elements.catStatusPill.classList.add('error');
  
  // Mostra box fallback con il CAT corretto
  elements.catFallbackName.textContent = expected;
  elements.catFallbackBox.classList.remove('hidden');
  
  showError(`Attenzione: il CAT da assegnare è "${expected}" ma nel campo risulta "${found}". Verifica e correggi manualmente se necessario.`);
}

/**
 * Mostra il box di sospensione CAT
 */
function showSuspensionBox(catData) {
  const { cat_name, commune_name, suspension_reason, suspension_end_date } = catData;
  
  // Formatta la data
  const endDate = new Date(suspension_end_date).toLocaleDateString('it-IT', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric'
  });
  
  // Costruisci il messaggio
  let message = '';
  if (suspension_reason === 'disattivato') {
    message = `${cat_name} per ${commune_name} è attualmente disattivato`;
  } else if (suspension_reason === 'malattia') {
    message = `${cat_name} per ${commune_name} non è disponibile per malattia fino al ${endDate}`;
  } else if (suspension_reason === 'ferie') {
    message = `${cat_name} per ${commune_name} non è disponibile per ferie fino al ${endDate}`;
  } else if (suspension_end_date) {
    message = `${cat_name} per ${commune_name} non è disponibile fino al ${endDate}`;
  } else {
    message = `${cat_name} per ${commune_name} non è disponibile`;
  }
  
  elements.suspendedMessage.textContent = message;
  elements.catSuspendedBox.classList.remove('hidden');
  elements.actionsSection.classList.add('hidden');
}

/**
 * Nasconde il box di sospensione CAT
 */
function hideSuspensionBox() {
  elements.catSuspendedBox.classList.add('hidden');
  elements.actionsSection.classList.remove('hidden');
  currentSuspendedCat = null;
}

/**
 * Handler per "Assegna comunque" (CAT sospeso)
 */
async function handleAssignAnyway() {
  if (!currentSuspendedCat) {
    showError('Nessun CAT sospeso da assegnare');
    return;
  }
  
  const catAlias = currentSuspendedCat.cat_alias || currentSuspendedCat.cat_name;
  const catDisplayName = currentSuspendedCat.cat_name;
  
  setButtonsEnabled(false);
  hideMessages();
  
  try {
    await assignCatToPage(catAlias, catDisplayName);
    hideSuspensionBox();
  } catch (error) {
    console.error('[CAT Dispatcher Popup] Errore assegnazione comunque:', error);
    showErrorPill(catAlias);
    showError('Errore. Copia il CAT e inseriscilo manualmente.');
  } finally {
    setButtonsEnabled(true);
  }
}

/**
 * Handler per "Apri mappa CAT"
 */
async function handleOpenMap() {
  if (!currentData?.ubicazione) {
    showError('Dati ubicazione non disponibili');
    return;
  }
  
  setButtonsEnabled(false);
  
  try {
    // Chiedi al background di aprire la mappa
    const response = await sendToBackground({
      action: 'OPEN_MAP',
      ubicazione: currentData.ubicazione
    });
    
    if (!response?.success) {
      if (response?.error === 'NOT_LOGGED_IN') {
        showLoginForm();
        return;
      }
      throw new Error(response?.error || 'Errore nell\'apertura della mappa');
    }
    
    showSuccess('Mappa CAT aperta');
    
  } catch (error) {
    console.error('[CAT Dispatcher Popup] Errore apertura mappa:', error);
    showError(error.message);
  } finally {
    setButtonsEnabled(true);
  }
}

// ============================================================================
// INIZIALIZZAZIONE
// ============================================================================

/**
 * Copia il CAT negli appunti
 */
async function handleCopyCat() {
  const catName = elements.catFallbackName.textContent;
  if (!catName) return;
  
  try {
    await navigator.clipboard.writeText(catName);
    elements.btnCopyCat.classList.add('copied');
    elements.btnCopyCat.innerHTML = `
      <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2">
        <polyline points="20 6 9 17 4 12"></polyline>
      </svg>
    `;
    
    // Reset dopo 2 secondi
    setTimeout(() => {
      elements.btnCopyCat.classList.remove('copied');
      elements.btnCopyCat.innerHTML = `
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2">
          <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
          <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
        </svg>
      `;
    }, 2000);
  } catch (e) {
    console.error('[CAT Dispatcher Popup] Errore copia:', e);
  }
}

// Event listeners
elements.btnAssignPostgrest.addEventListener('click', handleAssignPostgrest);
elements.btnOpenMap.addEventListener('click', handleOpenMap);
elements.btnRefreshInline.addEventListener('click', () => loadPageData(true)); // true = forza refresh cache sospensioni
elements.btnLogout.addEventListener('click', handleLogout);
elements.btnLoginGoogle.addEventListener('click', handleGoogleLogin);
elements.btnCopyCat.addEventListener('click', handleCopyCat);
elements.btnAssignAnyway.addEventListener('click', handleAssignAnyway);

// Carica i dati all'apertura del popup
document.addEventListener('DOMContentLoaded', loadPageData);

console.log('[CAT Dispatcher Popup] Script caricato');
