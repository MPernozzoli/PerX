/**
 * Content Script per ACT CAT Dispatcher
 * 
 * Questo script viene iniettato in TUTTI i frame di https://act.jfish.it/*
 * grazie a "all_frames": true nel manifest.
 * 
 * Gestisce:
 * - Rilevamento se siamo su una pagina di dettaglio sinistro
 * - Lettura dei campi Ubicazione Rischio dal DOM
 * - Lettura/scrittura del campo "Assegna CAT" (combobox Syncfusion)
 * - Comunicazione con il popup dell'estensione
 */

// Versione corrente dell'estensione (aggiornare ad ogni release)
const EXTENSION_VERSION = '1.6.0';

// Log di caricamento - apparirà nella console della PAGINA, non del popup
console.log('[CAT Dispatcher] Content script caricato in frame:', window.location.href);

// ============================================================================
// MARKER PER RILEVAMENTO ESTENSIONE INSTALLATA
// ============================================================================

/**
 * Inietta un marker nel DOM per permettere alla pagina web di rilevare
 * che l'estensione è installata
 */
function injectExtensionMarker() {
  // Solo nel frame principale
  if (window.self !== window.top) return;
  
  // Crea un elemento nascosto con i dati dell'estensione
  const marker = document.createElement('div');
  marker.id = 'cat-dispatcher-extension-marker';
  marker.style.display = 'none';
  marker.dataset.installed = 'true';
  marker.dataset.version = EXTENSION_VERSION;
  document.documentElement.appendChild(marker);
  
  console.log('[CAT Dispatcher] Marker estensione iniettato, versione:', EXTENSION_VERSION);
}

// Inietta il marker appena possibile
injectExtensionMarker();

// ============================================================================
// LISTENER PER CAT SELEZIONATO DALLA MAPPA
// ============================================================================

/**
 * Ascolta i messaggi postMessage dalla pagina /api
 * Quando l'utente seleziona un CAT nella mappa, lo salva per applicarlo
 */
if (window.location.hostname === 'catdispatcher.it') {
  window.addEventListener('message', (event) => {
    // Verifica origine
    if (event.origin !== 'https://catdispatcher.it') return;
    
    // Controlla se è un messaggio di selezione CAT
    if (event.data?.type === 'CAT_SELECTED' && event.data?.data) {
      const catName = event.data.data;
      console.log('[CAT Dispatcher] CAT selezionato dalla mappa:', catName);
      
      // Salva in storage per essere applicato dalla pagina ACT
      chrome.storage.local.set({
        catDispatcher_pendingCat: catName,
        catDispatcher_pendingCatTimestamp: Date.now()
      }, () => {
        console.log('[CAT Dispatcher] CAT salvato per applicazione:', catName);
      });
      
      // Notifica il background script
      chrome.runtime.sendMessage({
        action: 'CAT_SELECTED_FROM_MAP',
        catName: catName
      });
    }
  });
  
  console.log('[CAT Dispatcher] Listener CAT_SELECTED attivo su catdispatcher.it');
}

/**
 * Legge la sessione Supabase dal localStorage del sito
 * @returns {Object|null} Sessione Supabase o null
 */
function getSupabaseSession() {
  try {
    // Supabase salva la sessione con una chiave che inizia con 'sb-'
    for (const key of Object.keys(localStorage)) {
      if (key.startsWith('sb-') && key.endsWith('-auth-token')) {
        const data = JSON.parse(localStorage.getItem(key));
        if (data?.access_token && data?.user) {
          console.log('[CAT Dispatcher] Sessione Supabase trovata per:', data.user.email);
          return data;
        }
      }
    }
  } catch (e) {
    console.warn('[CAT Dispatcher] Errore lettura sessione Supabase:', e);
  }
  return null;
}

// ============================================================================
// SELETTORI DOM - Gli ID sono dinamici con il numero sinistro come suffisso
// Es: "indirizzoUbicazioneRischio2600947"
// ============================================================================

const SELECTORS = {
  // Identificazione pagina sinistro
  idSinistro: 'input[id^="id_interno_sinistro"]',
  
  // Ubicazione rischio
  indirizzo: 'input[id^="indirizzoUbicazioneRischio"]',
  citta: 'input[id^="cittaUbicazioneRischio"]',
  cap: 'input[id^="capUbicazioneRischio"]',
  provincia: 'input[id^="provinciaUbicazioneRischio"]',
  nazione: 'input[id^="nazioneUbicazioneRischio"]',
  
  // CAT - cerca select con name che contiene "assegnaCat" o "cat"
  selectCat: 'select[id*="assegnaCat"], select[id*="Cat" i]',
  inputCat: 'input[id*="assegnaCat"], input[id*="cat" i][aria-label="dropdownlist"]'
};

// ============================================================================
// GESTIONE TAB MULTIPLE SINISTRI
// ============================================================================

// ID del sinistro attualmente attivo (dalla tab selezionata)
let activeSinistroId = null;

/**
 * Trova l'ID del sinistro dalla tab attiva
 * ACT usa Syncfusion Tab con classe e-active sulla tab selezionata
 * L'ID è nel data-id dell'elemento .e-toolbar-item.e-active
 * @returns {string|null} ID del sinistro attivo o null
 */
function getActiveSinistroIdFromTab() {
  // Cerca la tab attiva - l'ID è nel data-id
  const activeTabItem = document.querySelector('.e-tab-header .e-toolbar-item.e-active[data-id]');
  
  if (activeTabItem) {
    const dataId = activeTabItem.getAttribute('data-id');
    // Verifica che sia un ID numerico (non "tabitem_0" che è la tab principale)
    if (dataId && /^\d{6,}$/.test(dataId)) {
      console.log('[CAT Dispatcher] Tab attiva trovata (data-id):', dataId);
      return dataId;
    }
  }
  
  // Fallback: cerca nel testo della tab
  const activeTabText = document.querySelector('.e-tab-header .e-toolbar-item.e-active .e-tab-text');
  if (activeTabText) {
    const text = activeTabText.innerText || activeTabText.textContent || '';
    const match = text.match(/\b(\d{6,})\b/);
    if (match) {
      console.log('[CAT Dispatcher] Tab attiva trovata (testo):', match[1]);
      return match[1];
    }
  }
  
  console.log('[CAT Dispatcher] Nessuna tab sinistro attiva trovata');
  return null;
}

/**
 * Trova il contenitore del sinistro attivo (il pannello visibile)
 * @returns {HTMLElement|null} Il contenitore visibile o null
 */
function getActiveTabContent() {
  // Prova a trovare il pannello tab attivo (Syncfusion)
  const activePanel = document.querySelector('.e-tab-content > .e-item.e-active');
  if (activePanel) {
    console.log('[CAT Dispatcher] Pannello tab attivo trovato');
    return activePanel;
  }
  
  // Fallback: cerca contenitori visibili con dati sinistro
  const allPanels = document.querySelectorAll('.e-tab-content > .e-item');
  for (const panel of allPanels) {
    // Controlla se è visibile (non display:none e non height:0)
    const style = window.getComputedStyle(panel);
    if (style.display !== 'none' && style.visibility !== 'hidden') {
      const hasIdSinistro = panel.querySelector(SELECTORS.idSinistro);
      if (hasIdSinistro) {
        console.log('[CAT Dispatcher] Pannello visibile trovato con sinistro:', hasIdSinistro.value);
        return panel;
      }
    }
  }
  
  return null;
}

/**
 * Cerca un elemento nel contesto corretto (tab attiva o documento)
 * @param {string} selector - Selettore CSS
 * @param {string|null} sinistroId - ID sinistro per filtrare (opzionale)
 * @returns {HTMLElement|null}
 */
function queryInActiveContext(selector, sinistroId = null) {
  // Cerca tutti gli elementi che matchano il selettore
  const allElements = document.querySelectorAll(selector);
  
  if (allElements.length === 0) {
    return null;
  }
  
  // Se c'è un solo elemento, restituiscilo (caso senza tab multiple)
  if (allElements.length === 1) {
    return allElements[0];
  }
  
  // Se abbiamo un ID sinistro, cerca elementi con quell'ID nell'id/name
  if (sinistroId) {
    for (const el of allElements) {
      const elId = el.id || '';
      const elName = el.name || '';
      if (elId.includes(sinistroId) || elName.includes(sinistroId)) {
        console.log('[CAT Dispatcher] Elemento trovato per sinistro', sinistroId, ':', el.id);
        return el;
      }
    }
  }
  
  // Prova a cercare nel pannello tab attivo
  const activePanel = getActiveTabContent();
  if (activePanel) {
    for (const el of allElements) {
      if (activePanel.contains(el)) {
        console.log('[CAT Dispatcher] Elemento trovato nel pannello attivo:', el.id);
        return el;
      }
    }
  }
  
  // Fallback: cerca il primo elemento visibile
  for (const el of allElements) {
    if (isElementVisible(el)) {
      console.log('[CAT Dispatcher] Fallback: primo elemento visibile:', el.id);
      return el;
    }
  }
  
  // Ultimo fallback: restituisci il primo elemento
  console.log('[CAT Dispatcher] Ultimo fallback: primo elemento:', allElements[0]?.id);
  return allElements[0];
}

/**
 * Verifica se un elemento è visibile (controllo base)
 * @param {HTMLElement} el
 * @returns {boolean}
 */
function isElementVisible(el) {
  if (!el) return false;
  
  // Controllo rapido: se l'elemento ha dimensioni 0, non è visibile
  const rect = el.getBoundingClientRect();
  if (rect.width === 0 && rect.height === 0) {
    // Potrebbe essere un input hidden, controlla il parent
    const parent = el.closest('.e-ddl, .e-input-group, div');
    if (parent) {
      const parentRect = parent.getBoundingClientRect();
      if (parentRect.width === 0 && parentRect.height === 0) {
        return false;
      }
    }
  }
  
  // Controlla display e visibility sull'elemento stesso
  const style = window.getComputedStyle(el);
  if (style.display === 'none' || style.visibility === 'hidden') {
    return false;
  }
  
  // Controlla se è in un pannello tab non attivo (Syncfusion)
  const tabPanel = el.closest('.e-item');
  if (tabPanel && tabPanel.parentElement?.classList?.contains('e-tab-content')) {
    if (!tabPanel.classList.contains('e-active')) {
      return false;
    }
  }
  
  return true;
}

/**
 * Listener per click sulle tab per tracciare il sinistro attivo
 */
function setupTabClickListener() {
  document.addEventListener('click', (event) => {
    // Cerca il toolbar-item cliccato (la tab)
    const tabItem = event.target.closest('.e-tab-header .e-toolbar-item');
    if (!tabItem) return;
    
    // Prova prima con data-id
    const dataId = tabItem.getAttribute('data-id');
    let newId = null;
    
    if (dataId && /^\d{6,}$/.test(dataId)) {
      newId = dataId;
    } else {
      // Fallback: estrai dal testo
      const tabText = tabItem.querySelector('.e-tab-text');
      if (tabText) {
        const text = tabText.innerText || tabText.textContent || '';
        const match = text.match(/\b(\d{6,})\b/);
        if (match) {
          newId = match[1];
        }
      }
    }
    
    if (newId && newId !== activeSinistroId) {
      console.log('[CAT Dispatcher] Tab cliccata, cambio sinistro:', activeSinistroId, '->', newId);
      activeSinistroId = newId;
      
      // Piccolo delay per dare tempo al framework di aggiornare
      setTimeout(() => {
        const visibleId = getFieldFromActiveContext(SELECTORS.idSinistro);
        console.log('[CAT Dispatcher] Sinistro visibile dopo cambio tab:', visibleId);
        
        // Reinietta il pulsante rapido per il nuovo sinistro
        if (isDettaglioSinistro()) {
          injectQuickAssignButton();
        }
      }, 300);
    }
  }, true);
  
  console.log('[CAT Dispatcher] Listener tab click attivato');
}

/**
 * Legge un campo dal contesto attivo (tab corrente)
 * @param {string} selector
 * @returns {string}
 */
function getFieldFromActiveContext(selector) {
  const sinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  const input = queryInActiveContext(selector, sinistroId);
  return input ? input.value.trim() : '';
}

// Inizializza il listener se siamo su ACT
if (window.location.hostname === 'act.jfish.it') {
  setupTabClickListener();
  // Inizializza l'ID del sinistro attivo
  activeSinistroId = getActiveSinistroIdFromTab();
  console.log('[CAT Dispatcher] Sinistro iniziale:', activeSinistroId);
}

// ============================================================================
// FUNZIONI DI RILEVAMENTO PAGINA SINISTRO
// ============================================================================

/**
 * Verifica se siamo sulla lista sinistri (griglia principale)
 * @returns {boolean} true se la griglia sinistri è visibile
 */
function isListaSinistri() {
  const grid = document.getElementById('GridSituazioneSinistri');
  if (!grid) return false;
  
  // Verifica che la griglia sia effettivamente visibile
  const style = window.getComputedStyle(grid);
  const isVisible = style.display !== 'none' && 
                    style.visibility !== 'hidden' && 
                    grid.offsetParent !== null;
  
  if (isVisible) {
    console.log('[CAT Dispatcher] Griglia lista sinistri rilevata e visibile');
  }
  return isVisible;
}

/**
 * Verifica se siamo su una pagina di dettaglio sinistro
 * cercando elementi caratteristici nel DOM (nel contesto attivo)
 * @returns {boolean} true se siamo su una pagina sinistro
 */
function isDettaglioSinistro() {
  // Se siamo sulla lista sinistri, NON siamo su un dettaglio
  if (isListaSinistri()) {
    console.log('[CAT Dispatcher] Siamo sulla lista sinistri, non su un dettaglio');
    return false;
  }
  
  // Prima prova con ricerca nel contesto attivo
  const sinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  
  let idSinistro = queryInActiveContext(SELECTORS.idSinistro, sinistroId);
  let indirizzo = queryInActiveContext(SELECTORS.indirizzo, sinistroId);
  let citta = queryInActiveContext(SELECTORS.citta, sinistroId);
  
  // Basta trovare almeno 2 di questi elementi
  let found = [idSinistro, indirizzo, citta].filter(Boolean).length;
  
  // Se non troviamo abbastanza elementi, prova ricerca diretta (fallback)
  if (found < 2) {
    console.log('[CAT Dispatcher] Ricerca contesto fallita, provo ricerca diretta...');
    idSinistro = document.querySelector(SELECTORS.idSinistro);
    indirizzo = document.querySelector(SELECTORS.indirizzo);
    citta = document.querySelector(SELECTORS.citta);
    found = [idSinistro, indirizzo, citta].filter(Boolean).length;
  }
  
  if (found >= 2) {
    console.log('[CAT Dispatcher] Pagina sinistro rilevata! ID:', idSinistro?.value, 'Elementi trovati:', found);
    return true;
  }
  
  console.log('[CAT Dispatcher] Non è una pagina sinistro. Elementi trovati:', found);
  return false;
}

// ============================================================================
// FUNZIONI DI LETTURA DAL DOM (contesto tab attiva)
// ============================================================================

/**
 * Legge il valore di un campo input tramite selettore (dal contesto attivo)
 * @param {string} selector - Il selettore CSS del campo
 * @returns {string} Il valore del campo o stringa vuota se non trovato
 */
function getFieldBySelector(selector) {
  const sinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  let input = queryInActiveContext(selector, sinistroId);
  
  // Fallback: ricerca diretta
  if (!input) {
    input = document.querySelector(selector);
  }
  
  return input ? input.value.trim() : '';
}

/**
 * Legge tutti i dati dell'Ubicazione Rischio dalla tab attiva
 * @returns {Object} Oggetto con indirizzo, citta, cap, provincia, nazione
 */
function getUbicazioneRischio() {
  return {
    indirizzo: getFieldBySelector(SELECTORS.indirizzo),
    citta: getFieldBySelector(SELECTORS.citta),
    cap: getFieldBySelector(SELECTORS.cap),
    provincia: getFieldBySelector(SELECTORS.provincia),
    nazione: getFieldBySelector(SELECTORS.nazione)
  };
}

/**
 * Legge il CAT attualmente selezionato dalla tab attiva
 * Legge direttamente dall'input visibile Syncfusion
 * @returns {Object|null} Oggetto con value e label del CAT, o null se non trovato
 */
function getCurrentCAT() {
  const sinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  
  // Cerca l'input visibile del dropdown Syncfusion (non il select nascosto)
  let dropdownInput = null;
  
  if (sinistroId) {
    dropdownInput = document.getElementById(`assegnaCat${sinistroId}`);
  }
  
  // Fallback: cerca qualsiasi dropdown CAT
  if (!dropdownInput) {
    const allDropdowns = document.querySelectorAll('input[id^="assegnaCat"]:not([id$="_hidden"]):not([id$="_options"])');
    for (const dd of allDropdowns) {
      // Verifica che sia del sinistro attivo o visibile
      if (sinistroId && dd.id.includes(sinistroId)) {
        dropdownInput = dd;
        break;
      } else if (!sinistroId && isElementVisible(dd)) {
        dropdownInput = dd;
        break;
      }
    }
  }
  
  if (!dropdownInput) {
    console.log('[CAT Dispatcher] Dropdown CAT non trovato per sinistro:', sinistroId);
    return null;
  }
  
  // Leggi il valore dall'input visibile
  const label = dropdownInput.value?.trim() || '';
  
  // Prova a ottenere il value dall'API Syncfusion
  let value = '';
  try {
    if (dropdownInput.ej2_instances && dropdownInput.ej2_instances[0]) {
      const ddlInstance = dropdownInput.ej2_instances[0];
      value = ddlInstance.value || '';
    }
  } catch (e) {
    // Ignora errori API
  }
  
  // Se non abbiamo il value, prova dal select nascosto
  if (!value) {
    const selectCat = document.getElementById(`${dropdownInput.id}_hidden`);
    if (selectCat) {
      value = selectCat.value || '';
    }
  }
  
  console.log('[CAT Dispatcher] CAT corrente:', label, 'value:', value, 'sinistro:', sinistroId);
  
  // Restituisci null se vuoto
  if (!label) {
    return {
      value: '',
      label: ''
    };
  }
  
  return {
    value: value,
    label: label
  };
}

/**
 * Ottiene tutte le opzioni CAT disponibili nel dropdown della tab attiva
 * @returns {Array} Array di oggetti {value, label}
 */
function getAllCATOptions() {
  const sinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  const activePanel = getActiveTabContent();
  const searchContext = activePanel || document;
  
  // Cerca il select CAT nel contesto corretto
  const selects = searchContext.querySelectorAll('select.e-ddl-hidden[name^="assegnaCat"]');
  
  for (const selectCat of selects) {
    // Verifica che appartenga al sinistro attivo
    if (sinistroId && !selectCat.id.includes(sinistroId) && !selectCat.name.includes(sinistroId)) {
      continue;
    }
    
    return Array.from(selectCat.options).map(opt => ({
      value: opt.value,
      label: opt.text.trim()
    }));
  }
  
  return [];
}

// ============================================================================
// FUNZIONI DI SCRITTURA NEL DOM (contesto tab attiva)
// ============================================================================

/**
 * Trova il select CAT della tab attiva
 * @returns {HTMLSelectElement|null}
 */
function getActiveSelectCat() {
  const sinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  const activePanel = getActiveTabContent();
  const searchContext = activePanel || document;
  
  // Cerca il select CAT nel contesto corretto
  const selects = searchContext.querySelectorAll('select.e-ddl-hidden[name^="assegnaCat"]');
  
  for (const selectCat of selects) {
    // Se abbiamo l'ID sinistro, verifica che corrisponda
    if (sinistroId) {
      if (selectCat.id.includes(sinistroId) || selectCat.name.includes(sinistroId)) {
        console.log('[CAT Dispatcher] Select CAT trovato per sinistro:', sinistroId);
        return selectCat;
      }
    } else {
      // Senza ID, prendi il primo visibile
      if (isElementVisible(selectCat.closest('.e-ddl') || selectCat)) {
        return selectCat;
      }
    }
  }
  
  // Fallback: prova senza filtro sinistro
  if (sinistroId && selects.length > 0) {
    console.log('[CAT Dispatcher] Fallback: uso primo select CAT trovato');
    return selects[0];
  }
  
  return null;
}

/**
 * Imposta il CAT nel combobox Syncfusion usando il value (ID)
 * @param {string|number} valueCat - L'ID del CAT da selezionare
 * @returns {boolean} true se l'operazione è riuscita
 */
function setAssegnaCatByValue(valueCat) {
  const selectCat = getActiveSelectCat();
  
  if (!selectCat) {
    console.error('[CAT Dispatcher] Select "Assegna CAT" non trovato nella tab attiva');
    return false;
  }

  const optionExists = Array.from(selectCat.options).some(
    opt => opt.value === String(valueCat)
  );

  if (!optionExists) {
    console.error(`[CAT Dispatcher] CAT con value "${valueCat}" non trovato`);
    return false;
  }

  selectCat.value = String(valueCat);
  selectCat.dispatchEvent(new Event('input', { bubbles: true }));
  selectCat.dispatchEvent(new Event('change', { bubbles: true }));
  updateSyncfusionDropdownVisual(selectCat);

  const sinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  console.log(`[CAT Dispatcher] CAT impostato con value: ${valueCat} per sinistro: ${sinistroId}`);
  return true;
}

/**
 * Imposta il CAT nel combobox Syncfusion usando la label (nome)
 * Usa direttamente l'API Syncfusion ej2_instances
 * @param {string} labelCat - Il nome del CAT da selezionare
 * @returns {boolean} true se l'operazione è riuscita
 */
function setAssegnaCatByLabel(labelCat) {
  const sinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  console.log('[CAT Dispatcher] setAssegnaCatByLabel:', labelCat, 'per sinistro:', sinistroId);
  
  // Trova l'input del dropdown Syncfusion
  let dropdownInput = null;
  
  if (sinistroId) {
    dropdownInput = document.getElementById(`assegnaCat${sinistroId}`);
  }
  
  // Fallback: cerca qualsiasi dropdown CAT visibile
  if (!dropdownInput) {
    const allDropdowns = document.querySelectorAll('input[id^="assegnaCat"]:not([id$="_hidden"]):not([id$="_options"]):not([id$="_popup"])');
    for (const dd of allDropdowns) {
      if (dd.id && !dd.id.includes('_')) {
        dropdownInput = dd;
        break;
      }
    }
  }
  
  if (!dropdownInput) {
    console.error('[CAT Dispatcher] Dropdown CAT non trovato');
    return false;
  }
  
  console.log('[CAT Dispatcher] Dropdown trovato:', dropdownInput.id);
  
  // Prova ad usare l'API Syncfusion ej2_instances
  try {
    if (dropdownInput.ej2_instances && dropdownInput.ej2_instances[0]) {
      const ddlInstance = dropdownInput.ej2_instances[0];
      
      // Cerca nella dataSource del dropdown
      let targetValue = null;
      let targetText = null;
      
      if (ddlInstance.dataSource && Array.isArray(ddlInstance.dataSource)) {
        console.log('[CAT Dispatcher] Cerco in dataSource con', ddlInstance.dataSource.length, 'items');
        
        for (const item of ddlInstance.dataSource) {
          // Gli item possono essere oggetti {text, value} o stringhe
          let itemText = '';
          let itemValue = '';
          
          if (typeof item === 'object') {
            itemText = item.text || item.Text || item[ddlInstance.fields?.text] || '';
            itemValue = item.value || item.Value || item[ddlInstance.fields?.value] || '';
          } else {
            itemText = String(item);
            itemValue = String(item);
          }
          
          if (itemText.toLowerCase() === labelCat.trim().toLowerCase()) {
            targetValue = itemValue;
            targetText = itemText;
            console.log('[CAT Dispatcher] Trovato in dataSource:', targetText, 'value:', targetValue);
            break;
          }
        }
      }
      
      if (targetValue !== null && targetValue !== undefined) {
        // Imposta il valore
        ddlInstance.value = targetValue;
        ddlInstance.dataBind();
        console.log('[CAT Dispatcher] CAT impostato via API Syncfusion:', targetText);
        return true;
      } else {
        console.log('[CAT Dispatcher] Non trovato in dataSource, provo con text diretto');
        // Prova a impostare direttamente il text
        ddlInstance.text = labelCat;
        ddlInstance.dataBind();
        console.log('[CAT Dispatcher] CAT impostato via text:', labelCat);
        return true;
      }
    }
  } catch (e) {
    console.warn('[CAT Dispatcher] Errore API Syncfusion:', e);
  }
  
  // Fallback: imposta manualmente l'input visibile
  console.log('[CAT Dispatcher] Fallback: impostazione manuale input');
  dropdownInput.value = labelCat;
  dropdownInput.dispatchEvent(new Event('input', { bubbles: true }));
  dropdownInput.dispatchEvent(new Event('change', { bubbles: true }));
  
  return true;
}

/**
 * Aggiorna l'input visibile del dropdown Syncfusion
 * @param {HTMLSelectElement} selectCat - L'elemento select nascosto
 * @param {string} textOverride - Testo da mostrare (opzionale)
 */
function updateSyncfusionDropdownVisual(selectCat, textOverride = null) {
  const selectId = selectCat.id.replace('_hidden', '');
  const visibleInput = document.getElementById(selectId);
  
  // Determina il testo da mostrare
  let displayText = textOverride;
  if (!displayText) {
    const selectedOption = selectCat.options[selectCat.selectedIndex];
    if (selectedOption) {
      displayText = selectedOption.text.trim();
    }
  }
  
  // Aggiorna l'input visibile
  if (visibleInput && displayText) {
    visibleInput.value = displayText;
    console.log('[CAT Dispatcher] Input visibile aggiornato:', displayText);
  }

  // Notifica il wrapper
  const wrapper = selectCat.closest('.e-ddl');
  if (wrapper) {
    wrapper.dispatchEvent(new Event('change', { bubbles: true }));
  }

  // Prova ad aggiornare tramite API Syncfusion
  try {
    const ejInstance = document.getElementById(selectId);
    if (ejInstance?.ej2_instances?.[0]) {
      const ddlInstance = ejInstance.ej2_instances[0];
      const newValue = selectCat.value;
      if (ddlInstance.value !== newValue) {
        ddlInstance.value = newValue;
        if (displayText) {
          ddlInstance.text = displayText;
        }
        ddlInstance.dataBind();
        console.log('[CAT Dispatcher] Syncfusion DropDownList aggiornato via API');
      }
    }
  } catch (e) {
    console.warn('[CAT Dispatcher] Impossibile aggiornare Syncfusion via API:', e);
  }
}

// ============================================================================
// GESTIONE MESSAGGI DAL POPUP
// ============================================================================

/**
 * Listener per i messaggi in arrivo dal popup
 * 
 * IMPORTANTE: Questo listener viene registrato in OGNI frame.
 * Solo il frame che contiene il dettaglio sinistro risponderà con successo.
 */
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  console.log('[CAT Dispatcher] Messaggio ricevuto in frame:', request.action);

  switch (request.action) {
    case 'GET_SUPABASE_SESSION':
      // Restituisce la sessione Supabase dal localStorage del sito
      if (window.location.hostname === 'catdispatcher.it') {
        const session = getSupabaseSession();
        sendResponse({ 
          success: !!session, 
          session: session 
        });
      } else {
        sendResponse({ success: false, error: 'Non su catdispatcher.it' });
      }
      break;

    case 'PING':
      // Risponde solo se siamo su una pagina di dettaglio sinistro
      const isValid = isDettaglioSinistro();
      console.log('[CAT Dispatcher] PING - isDettaglioSinistro:', isValid);
      sendResponse({ 
        success: true, 
        isDettaglioSinistro: isValid,
        frameUrl: window.location.href
      });
      break;

    case 'GET_PAGE_DATA':
      // Verifica se siamo su un dettaglio sinistro
      if (!isDettaglioSinistro()) {
        console.log('[CAT Dispatcher] GET_PAGE_DATA - Non siamo su un dettaglio sinistro');
        sendResponse({
          success: true,
          data: {
            isValidPage: false,
            url: window.location.href
          }
        });
        break;
      }

      // Leggi i dati dalla pagina
      const idSinistro = getFieldBySelector(SELECTORS.idSinistro);
      const ubicazione = getUbicazioneRischio();
      const catCorrente = getCurrentCAT();
      const catOptions = getAllCATOptions();
      
      console.log('[CAT Dispatcher] GET_PAGE_DATA - Dati letti:', {
        idSinistro,
        ubicazione,
        catCorrente: catCorrente?.label,
        catOptionsCount: catOptions.length
      });
      
      sendResponse({
        success: true,
        data: {
          idSinistro,
          ubicazione,
          catCorrente,
          catOptions,
          isValidPage: true,
          url: window.location.href
        }
      });
      break;

    case 'SET_CAT_BY_VALUE':
      const successByValue = setAssegnaCatByValue(request.value);
      sendResponse({ 
        success: successByValue,
        message: successByValue 
          ? `CAT impostato (ID: ${request.value})`
          : `Errore impostazione CAT ID: ${request.value}`
      });
      break;

    case 'SET_CAT_BY_LABEL':
      const successByLabel = setAssegnaCatByLabel(request.label);
      sendResponse({ 
        success: successByLabel,
        message: successByLabel 
          ? `CAT impostato: ${request.label}`
          : `Errore impostazione CAT: ${request.label}`
      });
      break;

    default:
      sendResponse({ 
        success: false, 
        message: `Azione sconosciuta: ${request.action}` 
      });
  }

  // Ritorna true per risposta asincrona
  return true;
});

// ============================================================================
// INIEZIONE PULSANTE RAPIDO NEL DOM
// ============================================================================

let quickAssignButton = null;
let isAssigning = false;

/**
 * Trova il campo "Assegna CAT" e il testo "apparecchi da verificare" nel DOM
 * @returns {Object|null} Oggetto con { catField, container, beforeElement } o null
 */
function findCatFieldAndPosition() {
  const sinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  
  // Trova l'input del dropdown CAT
  let catInput = null;
  if (sinistroId) {
    catInput = document.getElementById(`assegnaCat${sinistroId}`);
  }
  
  if (!catInput) {
    const allDropdowns = document.querySelectorAll('input[id^="assegnaCat"]:not([id$="_hidden"]):not([id$="_options"]):not([id$="_popup"])');
    for (const dd of allDropdowns) {
      if (dd.id && !dd.id.includes('_') && isElementVisible(dd)) {
        catInput = dd;
        break;
      }
    }
  }
  
  if (!catInput) {
    return null;
  }
  
  // Trova il contenitore (label o div parent)
  let container = catInput.closest('div[class*="e-input-group"], div[class*="form-group"], td, .e-ddl');
  if (!container) {
    container = catInput.parentElement;
  }
  
  // Cerca "apparecchi da verificare" nel DOM vicino (case-insensitive)
  const allText = Array.from(document.querySelectorAll('label, span, div, td, th, p')).filter(el => {
    const text = (el.textContent || '').toLowerCase().trim();
    return text.includes('apparecchi da verificare') || 
           text.includes('apparecchi da verificare') ||
           text === 'apparecchi da verificare';
  });
  
  let beforeElement = null;
  if (allText.length > 0) {
    // Trova l'elemento più vicino al campo CAT (stessa riga o subito dopo)
    const catRect = catInput.getBoundingClientRect();
    let minDistance = Infinity;
    let bestElement = null;
    
    for (const el of allText) {
      const elRect = el.getBoundingClientRect();
      // Preferisci elementi sulla stessa riga o poco sotto
      const verticalDiff = Math.abs(catRect.top - elRect.top);
      const horizontalDiff = Math.abs(catRect.left - elRect.left);
      const distance = verticalDiff * 2 + horizontalDiff; // Pesa di più la distanza verticale
      
      // Se è sulla stessa riga o poco sotto (max 50px), è un buon candidato
      if (verticalDiff < 50 && distance < minDistance) {
        minDistance = distance;
        bestElement = el;
      }
    }
    
    beforeElement = bestElement || allText[0];
  }
  
  return {
    catField: catInput,
    container: container,
    beforeElement: beforeElement
  };
}

/**
 * Crea il pulsante rapido per assegnazione CAT
 * @returns {HTMLElement} Elemento button creato
 */
function createQuickAssignButton() {
  const button = document.createElement('button');
  button.id = 'cat-dispatcher-quick-assign';
  button.type = 'button';
  button.setAttribute('aria-label', 'Assegna CAT automaticamente');
  button.title = 'Assegna CAT automaticamente';
  
  // Stili inline per evitare conflitti
  button.style.cssText = `
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    min-width: 28px;
    min-height: 28px;
    padding: 0;
    margin-left: 8px;
    margin-right: 0;
    border: 1px solid #ccc;
    border-radius: 4px;
    background: #fff;
    cursor: pointer;
    vertical-align: middle;
    transition: all 0.2s;
    flex-shrink: 0;
    box-shadow: 0 1px 2px rgba(0,0,0,0.1);
  `;
  
  // Icona PNG dell'estensione
  const iconImg = document.createElement('img');
  iconImg.src = chrome.runtime.getURL('icons/quick-assign-icon.png');
  iconImg.alt = 'Assegna CAT';
  iconImg.style.cssText = `
    width: 20px;
    height: 20px;
    pointer-events: none;
    display: block;
  `;
  button.appendChild(iconImg);
  
  // Hover effect
  button.addEventListener('mouseenter', () => {
    if (!isAssigning) {
      button.style.background = '#f0f0f0';
      button.style.borderColor = '#999';
    }
  });
  
  button.addEventListener('mouseleave', () => {
    if (!isAssigning) {
      button.style.background = '#fff';
      button.style.borderColor = '#ccc';
    }
  });
  
  // Click handler
  button.addEventListener('click', async (e) => {
    e.preventDefault();
    e.stopPropagation();
    
    if (isAssigning) return;
    
    await handleQuickAssign();
  });
  
  return button;
}

/**
 * Gestisce l'assegnazione rapida CAT senza aprire il popup
 */
async function handleQuickAssign() {
  if (isAssigning) return;
  
  isAssigning = true;
  const button = document.getElementById('cat-dispatcher-quick-assign');
  
  if (button) {
    button.style.opacity = '0.6';
    button.style.cursor = 'wait';
    button.style.pointerEvents = 'none';
  }
  
  try {
    // Leggi l'ubicazione dalla pagina
    const ubicazione = getUbicazioneRischio();
    
    if (!ubicazione.citta && !ubicazione.indirizzo) {
      throw new Error('Dati ubicazione non disponibili');
    }
    
    // Chiama il background script per ottenere il CAT
    const apiResponse = await chrome.runtime.sendMessage({
      action: 'API_GET_CAT',
      ubicazione: ubicazione
    });
    
    // Gestione CAT sospeso - apri popup
    if (apiResponse?.suspended) {
      // Salva i dati del CAT sospeso per mostrarlo nel popup
      await chrome.storage.local.set({
        catDispatcher_pendingError: {
          suspended: true,
          data: apiResponse.data,
          ubicazione: ubicazione
        }
      });
      chrome.runtime.sendMessage({ action: 'OPEN_POPUP' });
      showQuickAssignError('CAT sospeso - apri estensione per dettagli');
      return;
    }
    
    if (!apiResponse?.success) {
      if (apiResponse?.error === 'NOT_LOGGED_IN') {
        // Salva l'errore per mostrarlo nel popup
        await chrome.storage.local.set({
          catDispatcher_pendingError: {
            error: apiResponse.error,
            ubicazione: ubicazione
          }
        });
        chrome.runtime.sendMessage({ action: 'OPEN_POPUP' });
        showQuickAssignError('Login richiesto - apri estensione');
        return;
      }
      
      // Salva l'errore per mostrarlo nel popup
      await chrome.storage.local.set({
        catDispatcher_pendingError: {
          error: apiResponse.error || 'Errore nella chiamata API',
          ubicazione: ubicazione
        }
      });
      chrome.runtime.sendMessage({ action: 'OPEN_POPUP' });
      showQuickAssignError(apiResponse.error || 'Errore - apri estensione per dettagli');
      return;
    }
    
    const catData = apiResponse.data;
    
    if (!catData?.cat_name && !catData?.cat_alias) {
      throw new Error('Nome CAT non trovato nella risposta');
    }
    
    // Usa l'alias JFISH se disponibile, altrimenti il nome
    const catAlias = catData.cat_alias || catData.cat_name;
    
    // Assegna il CAT alla pagina
    const success = setAssegnaCatByLabel(catAlias);
    
    if (!success) {
      throw new Error('Impossibile assegnare il CAT');
    }
    
    // Verifica che l'assegnazione sia andata a buon fine
    await new Promise(resolve => setTimeout(resolve, 500));
    const catCorrente = getCurrentCAT();
    
    if (catCorrente?.label) {
      const assignedCat = catCorrente.label.trim();
      
      if (assignedCat && assignedCat.toLowerCase() === catAlias.toLowerCase()) {
        // Successo - mostra breve feedback positivo
        showQuickAssignSuccess();
        return;
      }
    }
    
    // Se la verifica fallisce, potrebbe essere comunque assegnato
    // Non mostriamo errore per non disturbare
    console.log('[CAT Dispatcher] Assegnazione completata, verifica non confermata');
    
  } catch (error) {
    console.error('[CAT Dispatcher] Errore assegnazione rapida:', error);
    
    // Salva l'errore per mostrarlo nel popup
    const ubicazione = getUbicazioneRischio();
    await chrome.storage.local.set({
      catDispatcher_pendingError: {
        error: error.message,
        ubicazione: ubicazione
      }
    });
    
    showQuickAssignError(error.message);
    // In caso di errore, apri il popup per dettagli
    chrome.runtime.sendMessage({ action: 'OPEN_POPUP' });
  } finally {
    // Piccolo delay prima di permettere nuove assegnazioni per evitare rimozioni immediate
    setTimeout(() => {
      isAssigning = false;
      if (button) {
        button.style.opacity = '1';
        button.style.cursor = 'pointer';
        button.style.pointerEvents = 'auto';
      }
    }, 200);
  }
}

/**
 * Mostra un messaggio di successo temporaneo
 */
function showQuickAssignSuccess() {
  const button = document.getElementById('cat-dispatcher-quick-assign');
  if (!button) return;
  
  const originalBg = button.style.background;
  button.style.background = '#d4edda';
  button.style.borderColor = '#28a745';
  
  setTimeout(() => {
    button.style.background = originalBg;
    button.style.borderColor = '#ccc';
  }, 1500);
}

/**
 * Mostra un messaggio di errore temporaneo
 */
function showQuickAssignError(message) {
  const button = document.getElementById('cat-dispatcher-quick-assign');
  if (!button) return;
  
  const originalBg = button.style.background;
  button.style.background = '#f8d7da';
  button.style.borderColor = '#dc3545';
  button.title = message || 'Errore assegnazione';
  
  setTimeout(() => {
    button.style.background = originalBg;
    button.style.borderColor = '#ccc';
    button.title = 'Assegna CAT automaticamente';
  }, 3000);
}

/**
 * Inietta il pulsante rapido nel DOM
 */
function injectQuickAssignButton() {
  // Non reiniettare se siamo in fase di assegnazione
  if (isAssigning) {
    return;
  }
  
  // Solo su pagine dettaglio sinistro
  if (!isDettaglioSinistro()) {
    // Rimuovi pulsante se non siamo più su un dettaglio sinistro (solo se non stiamo assegnando)
    const existing = document.getElementById('cat-dispatcher-quick-assign');
    if (existing && !isAssigning) {
      existing.remove();
    }
    return;
  }
  
  const currentSinistroId = activeSinistroId || getActiveSinistroIdFromTab() || '';
  
  // Verifica se il pulsante esistente è nel contesto corretto
  const existing = document.getElementById('cat-dispatcher-quick-assign');
  if (existing) {
    // Verifica che il pulsante sia associato al sinistro corretto
    const existingSinistroId = existing.dataset.sinistroId || '';
    
    // Normalizza per confronto (stringa vuota = nessun sinistro)
    const normalizedExisting = existingSinistroId || '';
    const normalizedCurrent = currentSinistroId || '';
    
    // Se sono uguali, verifica che il pulsante sia ancora nel posto giusto
    if (normalizedExisting === normalizedCurrent) {
      // Verifica che il pulsante sia ancora nel DOM corretto
      const position = findCatFieldAndPosition();
      if (position && position.catField) {
        // Verifica che il pulsante sia ancora vicino al campo CAT corretto
        const catWrapper = position.catField.closest('.e-input-group, .e-ddl');
        if (catWrapper) {
          // Controlla se il pulsante è nel parent del wrapper o come sibling
          const isNearField = catWrapper.contains(existing) || 
                             catWrapper.nextSibling === existing ||
                             catWrapper.parentElement?.contains(existing);
          if (isNearField) {
            // Il pulsante è già nel posto giusto, non fare nulla
            return;
          }
        }
      }
    }
    // Il sinistro è cambiato o il pulsante non è più nel posto giusto, rimuovi il vecchio
    existing.remove();
  }
  
  // Trova posizione nel DOM
  const position = findCatFieldAndPosition();
  if (!position) {
    console.log('[CAT Dispatcher] Campo CAT non trovato per iniezione pulsante');
    return;
  }
  
  // Crea il pulsante
  const button = createQuickAssignButton();
  // Associa il pulsante al sinistro corrente
  button.dataset.sinistroId = currentSinistroId || '';
  quickAssignButton = button;
  
  // Trova il wrapper del campo CAT (Syncfusion usa .e-input-group o .e-ddl)
  const catWrapper = position.catField.closest('.e-input-group, .e-ddl');
  
  if (catWrapper) {
    // Inserisci il pulsante subito dopo il wrapper del campo CAT
    if (catWrapper.parentElement) {
      catWrapper.parentElement.insertBefore(button, catWrapper.nextSibling);
    } else {
      catWrapper.appendChild(button);
    }
  } else {
    // Fallback: inserisci dopo il campo stesso
    if (position.catField.parentElement) {
      position.catField.parentElement.insertBefore(button, position.catField.nextSibling);
    } else {
      position.container.appendChild(button);
    }
  }
  
  console.log('[CAT Dispatcher] Pulsante rapido iniettato nel DOM');
}

/**
 * Traccia l'ID del sinistro corrente per rilevare cambiamenti
 */
let lastTrackedSinistroId = null;

/**
 * Verifica se il sinistro è cambiato e reinietta il pulsante se necessario
 */
function checkSinistroChange() {
  const currentSinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  
  // Solo se c'è un cambiamento reale (non null/undefined)
  if (currentSinistroId !== lastTrackedSinistroId && 
      (currentSinistroId || lastTrackedSinistroId)) {
    console.log('[CAT Dispatcher] Sinistro cambiato:', lastTrackedSinistroId, '->', currentSinistroId);
    lastTrackedSinistroId = currentSinistroId;
    
    // Reinietta il pulsante per il nuovo sinistro solo se siamo su una pagina valida
    if (isDettaglioSinistro()) {
      injectQuickAssignButton();
    } else {
      // Se non siamo più su un dettaglio sinistro, rimuovi il pulsante
      const existing = document.getElementById('cat-dispatcher-quick-assign');
      if (existing) {
        existing.remove();
      }
    }
  }
}

/**
 * Observer per rilevare cambiamenti nel DOM e reiniettare il pulsante se necessario
 */
function setupQuickAssignObserver() {
  // Solo nel frame principale
  if (window.self !== window.top) return;
  
  // Inizializza il tracking del sinistro
  lastTrackedSinistroId = activeSinistroId || getActiveSinistroIdFromTab();
  
  // Observer per cambiamenti DOM
  const observer = new MutationObserver((mutations) => {
    // Verifica se il sinistro è cambiato solo se ci sono cambiamenti rilevanti
    const hasRelevantChanges = mutations.some(mutation => {
      // Ignora cambiamenti di attributi non rilevanti
      if (mutation.type === 'attributes') {
        const attrName = mutation.attributeName;
        // Solo attributi rilevanti per il cambio sinistro
        return attrName === 'class' || attrName === 'data-id';
      }
      // Cambiamenti di nodi sono sempre rilevanti
      return mutation.type === 'childList';
    });
    
    if (hasRelevantChanges) {
      // Verifica se il sinistro è cambiato
      checkSinistroChange();
      
      const hasButton = document.getElementById('cat-dispatcher-quick-assign');
      
      // Se il pulsante non esiste e siamo su una pagina sinistro, reiniettalo
      // Ma solo se non stiamo già assegnando
      if (!hasButton && isDettaglioSinistro() && !isAssigning) {
        // Debounce per evitare troppe chiamate
        clearTimeout(window._catDispatcherReinjectTimeout);
        window._catDispatcherReinjectTimeout = setTimeout(() => {
          // Verifica di nuovo prima di reiniettare
          if (!document.getElementById('cat-dispatcher-quick-assign') && !isAssigning) {
            injectQuickAssignButton();
          }
        }, 500);
      }
    }
  });
  
  // Osserva cambiamenti nel body
  if (document.body) {
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'data-id']
    });
  } else {
    // Se il body non esiste ancora, aspetta
    document.addEventListener('DOMContentLoaded', () => {
      if (document.body) {
        observer.observe(document.body, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['class', 'data-id']
        });
      }
    });
  }
  
  // Listener per cambio tab sinistro (già gestito in setupTabClickListener, ma aggiungiamo anche qui)
  // Usa un listener più specifico per evitare troppe chiamate
  document.addEventListener('click', (e) => {
    // Solo se è un click su una tab
    const tabItem = e.target.closest('.e-tab-header .e-toolbar-item');
    if (tabItem) {
      setTimeout(() => {
        checkSinistroChange();
        if (isDettaglioSinistro()) {
          injectQuickAssignButton();
        }
      }, 300);
    }
  }, true);
  
  // Polling periodico per verificare cambiamenti sinistro (backup) - meno frequente
  setInterval(() => {
    // Solo se non c'è un pulsante visibile e non stiamo assegnando
    const hasButton = document.getElementById('cat-dispatcher-quick-assign');
    if (!hasButton && isDettaglioSinistro() && !isAssigning) {
      checkSinistroChange();
      injectQuickAssignButton();
    }
  }, 2000);
}

// Inizializza l'iniezione del pulsante
if (window.location.hostname === 'act.jfish.it') {
  // Funzione di inizializzazione
  function initializeQuickAssign() {
    // Solo nel frame principale
    if (window.self !== window.top) return;
    
    // Attendi che il DOM sia completamente caricato
    const tryInit = () => {
      if (document.body && document.querySelector('input[id^="assegnaCat"]')) {
        console.log('[CAT Dispatcher] Inizializzazione pulsante rapido...');
        injectQuickAssignButton();
        setupQuickAssignObserver();
      } else {
        // Riprova dopo un breve delay
        setTimeout(tryInit, 500);
      }
    };
    
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => {
        setTimeout(tryInit, 500);
      });
    } else {
      setTimeout(tryInit, 500);
    }
  }
  
  initializeQuickAssign();
}

// Log finale
if (isDettaglioSinistro()) {
  const ubicazione = getUbicazioneRischio();
  console.log('[CAT Dispatcher] ✅ Pagina dettaglio sinistro rilevata!');
  console.log('[CAT Dispatcher] ID Sinistro:', getFieldBySelector(SELECTORS.idSinistro));
  console.log('[CAT Dispatcher] Indirizzo:', ubicazione.indirizzo);
  console.log('[CAT Dispatcher] Città:', ubicazione.citta);
  console.log('[CAT Dispatcher] CAP:', ubicazione.cap);
  console.log('[CAT Dispatcher] Provincia:', ubicazione.provincia);
} else {
  console.log('[CAT Dispatcher] ℹ️ Non siamo su un dettaglio sinistro (frame:', window.location.href, ')');
}
