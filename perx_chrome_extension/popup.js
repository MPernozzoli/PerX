/**
 * PerX JFish Sync - Popup Script
 * Gestisce l'interfaccia utente del popup
 */

// Elementi DOM
const elements = {
  // Auth
  authSection: document.getElementById('authSection'),
  mainSection: document.getElementById('mainSection'),
  settingsSection: document.getElementById('settingsSection'),
  signInBtn: document.getElementById('signInBtn'),
  signOutBtn: document.getElementById('signOutBtn'),
  userInfo: document.getElementById('userInfo'),
  userAvatar: document.getElementById('userAvatar'),
  userName: document.getElementById('userName'),
  
  // Status
  hubStatus: document.getElementById('hubStatus'),
  pageStatus: document.getElementById('pageStatus'),
  
  // Sinistro
  sinistroCard: document.getElementById('sinistroCard'),
  noSinistro: document.getElementById('noSinistro'),
  sinistroInfo: document.getElementById('sinistroInfo'),
  sinistroRef: document.getElementById('sinistroRef'),
  statoJfish: document.getElementById('statoJfish'),
  diffCount: document.getElementById('diffCount'),
  refreshBtn: document.getElementById('refreshBtn'),
  
  // Actions
  syncDiarioBtn: document.getElementById('syncDiarioBtn'),
  fillPeriziaBtn: document.getElementById('fillPeriziaBtn'),
  importAllBtn: document.getElementById('importAllBtn'),
  exportAllBtn: document.getElementById('exportAllBtn'),
  
  // Settings
  settingsToggle: document.getElementById('settingsToggle'),
  hubUrl: document.getElementById('hubUrl'),
  saveHubBtn: document.getElementById('saveHubBtn'),
  
  // Modals
  diarioModal: document.getElementById('diarioModal'),
  diarioDiff: document.getElementById('diarioDiff'),
  syncDiarioConfirm: document.getElementById('syncDiarioConfirm'),
  periziaModal: document.getElementById('periziaModal'),
  periziaForm: document.getElementById('periziaForm'),
  fillPeriziaConfirm: document.getElementById('fillPeriziaConfirm')
};

// Stato
let state = {
  authenticated: false,
  user: null,
  hubConnected: false,
  currentTab: null,
  contentState: null,
  showSettings: false
};

/**
 * Inizializza il popup
 */
async function init() {
  console.log('[PerX Popup] Inizializzazione...');
  
  // Carica configurazione
  const config = await chrome.storage.local.get(['hubUrl']);
  if (config.hubUrl) {
    elements.hubUrl.value = config.hubUrl;
  }
  
  // Verifica autenticazione
  await checkAuth();
  
  // Verifica connessione Hub
  await checkHub();
  
  // Ottieni stato tab corrente
  await checkCurrentTab();
  
  // Setup event listeners
  setupEventListeners();
  
  console.log('[PerX Popup] Inizializzazione completata');
}

/**
 * Verifica stato autenticazione
 */
async function checkAuth() {
  try {
    const response = await chrome.runtime.sendMessage({ action: 'checkAuth' });
    
    state.authenticated = response.authenticated;
    state.user = response.user;
    
    updateAuthUI();
  } catch (error) {
    console.error('[PerX Popup] Errore checkAuth:', error);
  }
}

/**
 * Verifica connessione Hub
 */
async function checkHub() {
  try {
    const response = await chrome.runtime.sendMessage({ action: 'checkHub' });
    
    state.hubConnected = response.connected;
    
    const dot = elements.hubStatus.querySelector('.status-dot');
    const text = elements.hubStatus.querySelector('.status-text');
    
    if (response.connected) {
      dot.className = 'status-dot connected';
      text.textContent = `Hub: Connesso (v${response.version})`;
    } else {
      dot.className = 'status-dot disconnected';
      text.textContent = `Hub: ${response.error || 'Non connesso'}`;
    }
  } catch (error) {
    console.error('[PerX Popup] Errore checkHub:', error);
  }
}

/**
 * Verifica stato tab corrente
 */
async function checkCurrentTab() {
  try {
    // Ottieni tab attiva
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    state.currentTab = tab;
    
    // Chiedi stato al content script
    const response = await chrome.tabs.sendMessage(tab.id, { action: 'getState' });
    state.contentState = response;
    
    updatePageUI();
  } catch (error) {
    // Content script non caricato o errore
    console.log('[PerX Popup] Content script non disponibile');
    state.contentState = null;
    updatePageUI();
  }
}

/**
 * Aggiorna UI in base allo stato auth
 */
function updateAuthUI() {
  if (state.authenticated && state.user) {
    elements.authSection.classList.add('hidden');
    elements.mainSection.classList.remove('hidden');
    
    elements.userInfo.classList.remove('hidden');
    if (state.user.picture) {
      elements.userAvatar.src = state.user.picture;
    }
    elements.userName.textContent = state.user.name || state.user.email;
  } else {
    elements.authSection.classList.remove('hidden');
    elements.mainSection.classList.add('hidden');
    elements.userInfo.classList.add('hidden');
  }
}

/**
 * Aggiorna UI in base allo stato pagina
 */
function updatePageUI() {
  const dot = elements.pageStatus.querySelector('.status-dot');
  const text = elements.pageStatus.querySelector('.status-text');
  
  if (!state.contentState) {
    dot.className = 'status-dot';
    text.textContent = 'Pagina: Non supportata';
    showNoSinistro();
    disableActions();
    return;
  }
  
  if (state.contentState.isJFishPage) {
    // Verifica se siamo nella pagina di dettaglio o solo nel portale
    if (state.contentState.isDetailPage && state.contentState.sinistroId) {
      dot.className = 'status-dot connected';
      text.textContent = 'JFish: Dettaglio sinistro';
      showSinistroInfo(state.contentState);
      enableActions();
    } else {
      dot.className = 'status-dot warning';
      text.textContent = 'JFish: Nessun sinistro aperto';
      showNoSinistro();
      disableActions();
    }
  } else {
    dot.className = 'status-dot';
    text.textContent = 'Pagina: Non JFish';
    showNoSinistro();
    disableActions();
  }
}

/**
 * Mostra placeholder nessun sinistro
 */
function showNoSinistro() {
  elements.noSinistro.classList.remove('hidden');
  elements.sinistroInfo.classList.add('hidden');
}

/**
 * Mostra info sinistro con dati dalla pagina JFish
 */
async function showSinistroInfo(contentState) {
  elements.noSinistro.classList.add('hidden');
  elements.sinistroInfo.classList.remove('hidden');
  
  // Mostra subito i dati già disponibili nel contentState
  elements.sinistroRef.textContent = contentState.sinistroRef || '--';
  
  // Carica dati dettagliati dalla pagina
  try {
    const jfishResponse = await chrome.tabs.sendMessage(state.currentTab.id, { action: 'extractData' });
    
    if (jfishResponse.success && jfishResponse.data) {
      const data = jfishResponse.data;
      
      // Riferimento (unique key) = ID sinistro JFish
      elements.sinistroRef.textContent = data.riferimento || contentState.sinistroRef || '--';
      
      // Stato
      elements.statoJfish.textContent = data.stato || '--';
      
      // Differenze
      if (contentState.differences > 0) {
        elements.diffCount.classList.remove('hidden');
        elements.diffCount.querySelector('.count').textContent = contentState.differences;
      } else {
        elements.diffCount.classList.add('hidden');
      }
      
      console.log('[PerX Popup] Riferimento:', data.riferimento, '- Stato:', data.stato);
    }
  } catch (error) {
    console.error('[PerX Popup] Errore caricamento info sinistro:', error);
  }
}

/**
 * Abilita pulsanti azione
 */
function enableActions() {
  elements.syncDiarioBtn.disabled = !state.hubConnected;
  elements.fillPeriziaBtn.disabled = !state.hubConnected;
  elements.importAllBtn.disabled = !state.hubConnected;
  elements.exportAllBtn.disabled = !state.hubConnected;
}

/**
 * Disabilita pulsanti azione
 */
function disableActions() {
  elements.syncDiarioBtn.disabled = true;
  elements.fillPeriziaBtn.disabled = true;
  elements.importAllBtn.disabled = true;
  elements.exportAllBtn.disabled = true;
}

/**
 * Setup event listeners
 */
function setupEventListeners() {
  // Auth
  elements.signInBtn.addEventListener('click', handleSignIn);
  elements.signOutBtn.addEventListener('click', handleSignOut);
  
  // Refresh
  elements.refreshBtn.addEventListener('click', handleRefresh);
  
  // Actions
  elements.syncDiarioBtn.addEventListener('click', handleSyncDiario);
  elements.fillPeriziaBtn.addEventListener('click', handleFillPerizia);
  elements.importAllBtn.addEventListener('click', handleImportAll);
  elements.exportAllBtn.addEventListener('click', handleExportAll);
  
  // Settings
  elements.settingsToggle.addEventListener('click', toggleSettings);
  elements.saveHubBtn.addEventListener('click', handleSaveHub);
  
  // Modal close buttons
  document.querySelectorAll('.modal-close').forEach(btn => {
    btn.addEventListener('click', closeModals);
  });
  
  // Modal confirm buttons
  elements.syncDiarioConfirm.addEventListener('click', confirmSyncDiario);
  elements.fillPeriziaConfirm.addEventListener('click', confirmFillPerizia);
  
  // Ascolta cambiamenti dello storage per aggiornamenti quando cambia sinistro
  chrome.storage.onChanged.addListener((changes, areaName) => {
    if (areaName === 'local') {
      if (changes.currentSinistroId || changes.currentSinistroRef) {
        console.log('[PerX Popup] Storage cambiato, ricarico stato...');
        
        const newId = changes.currentSinistroId?.newValue;
        const newRef = changes.currentSinistroRef?.newValue;
        const isDetailPage = changes.isDetailPage?.newValue;
        
        if (newId && newId !== state.contentState?.sinistroId) {
          console.log('[PerX Popup] Nuovo sinistro:', newId);
          
          // Aggiorna stato e UI
          state.contentState = {
            ...state.contentState,
            isJFishPage: true,
            isDetailPage: isDetailPage !== false,
            sinistroId: newId,
            sinistroRef: newRef || newId
          };
          
          updatePageUI();
        }
      }
    }
  });
}

// === Handlers ===

async function handleSignIn() {
  elements.signInBtn.disabled = true;
  elements.signInBtn.classList.add('spinning');
  
  try {
    const response = await chrome.runtime.sendMessage({ action: 'signIn' });
    
    if (response.success) {
      state.authenticated = true;
      state.user = response.user;
      updateAuthUI();
      await checkHub();
      await checkCurrentTab();
    } else {
      alert('Errore login: ' + response.error);
    }
  } catch (error) {
    alert('Errore: ' + error.message);
  } finally {
    elements.signInBtn.disabled = false;
    elements.signInBtn.classList.remove('spinning');
  }
}

async function handleSignOut() {
  try {
    await chrome.runtime.sendMessage({ action: 'signOut' });
    state.authenticated = false;
    state.user = null;
    updateAuthUI();
    toggleSettings(); // Torna alla vista principale
  } catch (error) {
    console.error('[PerX Popup] Errore signOut:', error);
  }
}

async function handleRefresh() {
  elements.refreshBtn.classList.add('spinning');
  
  try {
    await chrome.tabs.sendMessage(state.currentTab.id, { action: 'refresh' });
    await checkCurrentTab();
  } catch (error) {
    console.error('[PerX Popup] Errore refresh:', error);
  } finally {
    elements.refreshBtn.classList.remove('spinning');
  }
}

async function handleSyncDiario() {
  elements.diarioModal.classList.remove('hidden');
  elements.diarioDiff.innerHTML = '<p class="loading">Caricamento differenze...</p>';
  
  try {
    // Ottieni diario JFish
    const jfishResponse = await chrome.tabs.sendMessage(state.currentTab.id, { action: 'extractDiario' });
    const jfishEntries = jfishResponse.success ? jfishResponse.entries : [];
    
    // Ottieni diario PerX tramite API JFish
    const perxResponse = await chrome.runtime.sendMessage({
      action: 'jfishGetDiario',
      ref: state.contentState.sinistroRef
    });
    const perxEntries = perxResponse.success ? perxResponse.data : [];
    
    // Salva per uso in confirmSyncDiario
    state.diarioData = { jfishEntries, perxEntries };
    
    // Mostra differenze
    showDiarioDiff(jfishEntries, perxEntries);
    
  } catch (error) {
    elements.diarioDiff.innerHTML = `<p class="error">Errore: ${error.message}</p>`;
  }
}

function showDiarioDiff(jfishEntries, perxEntries) {
  if (jfishEntries.length === 0 && perxEntries.length === 0) {
    elements.diarioDiff.innerHTML = '<p class="placeholder-text">Nessuna entry nel diario</p>';
    return;
  }
  
  let html = '';
  
  // Entry in PerX ma non in JFish
  for (const entry of perxEntries) {
    const inJfish = jfishEntries.some(e => e.data === entry.timestamp || e.testo === entry.testo);
    if (!inJfish) {
      html += `
        <div class="diario-entry-diff missing-jfish">
          <label>
            <input type="checkbox" data-type="toJfish" data-id="${entry.id}">
            <strong>${entry.timestamp || ''}</strong>: ${entry.testo?.substring(0, 100) || ''}...
          </label>
        </div>
      `;
    }
  }
  
  // Entry in JFish ma non in PerX
  for (const entry of jfishEntries) {
    const inPerx = perxEntries.some(e => e.timestamp === entry.data || e.testo === entry.testo);
    if (!inPerx) {
      html += `
        <div class="diario-entry-diff missing-perx">
          <label>
            <input type="checkbox" data-type="toPerx" data-index="${entry.index}">
            <strong>${entry.data || ''}</strong>: ${entry.testo?.substring(0, 100) || ''}...
          </label>
        </div>
      `;
    }
  }
  
  if (!html) {
    html = '<p class="placeholder-text">Diario sincronizzato</p>';
  }
  
  elements.diarioDiff.innerHTML = html;
  elements.syncDiarioConfirm.disabled = !html.includes('checkbox');
}

async function confirmSyncDiario() {
  const checkboxes = elements.diarioDiff.querySelectorAll('input[type="checkbox"]:checked');
  
  if (checkboxes.length === 0) {
    alert('Seleziona almeno una entry da sincronizzare');
    return;
  }
  
  // Raccogli entry da sincronizzare verso PerX
  const entriesToSync = [];
  
  for (const checkbox of checkboxes) {
    const type = checkbox.dataset.type;
    const index = parseInt(checkbox.dataset.index, 10);
    
    if (type === 'toPerx' && state.diarioData?.jfishEntries) {
      // Entry JFish da importare in PerX
      const entry = state.diarioData.jfishEntries[index];
      if (entry) {
        entriesToSync.push({
          data: entry.data,
          tipo: entry.tipo || 'nota',
          nota: entry.nota || entry.testo
        });
      }
    }
    // type === 'toJfish' non supportato (solo JFish → PerX)
  }
  
  if (entriesToSync.length === 0) {
    alert('Nessuna entry selezionata per l\'import verso PerX');
    closeModals();
    return;
  }
  
  try {
    // Sincronizza diario
    const response = await chrome.runtime.sendMessage({
      action: 'jfishSyncDiario',
      ref: state.contentState.sinistroRef,
      entries: entriesToSync
    });
    
    if (response.success) {
      const data = response.data;
      alert(`Sincronizzazione completata!\n\n• Entry aggiunte: ${data.addedEntries}\n• Entry già presenti: ${data.skippedEntries}`);
    } else {
      throw new Error(response.error || 'Errore sincronizzazione');
    }
    
  } catch (error) {
    alert('Errore: ' + error.message);
  }
  
  closeModals();
  await handleRefresh();
}

async function handleFillPerizia() {
  elements.periziaModal.classList.remove('hidden');
  elements.periziaForm.innerHTML = '<p class="loading">Caricamento dati perizia...</p>';
  
  try {
    const response = await chrome.runtime.sendMessage({
      action: 'getSinistro',
      ref: state.contentState.sinistroRef
    });
    
    if (response.success && response.data.perizia) {
      showPeriziaForm(response.data.perizia);
    } else {
      elements.periziaForm.innerHTML = '<p class="placeholder-text">Nessun dato perizia disponibile</p>';
    }
  } catch (error) {
    elements.periziaForm.innerHTML = `<p class="error">Errore: ${error.message}</p>`;
  }
}

function showPeriziaForm(perizia) {
  const fields = [
    { key: 'descrizioneRischio', label: 'Descrizione Rischio' },
    { key: 'strutturaPortante', label: 'Struttura Portante' },
    { key: 'tamponamenti', label: 'Tamponamenti' },
    { key: 'copertura', label: 'Copertura' },
    { key: 'stimaDannoIndennizzabile', label: 'Stima Danno Indennizzabile' }
  ];
  
  let html = '';
  
  for (const field of fields) {
    const value = perizia[field.key];
    if (value !== undefined && value !== null) {
      html += `
        <div class="perizia-field">
          <label>
            <input type="checkbox" data-field="${field.key}" checked>
            ${field.label}
          </label>
          <div class="value">${value}</div>
        </div>
      `;
    }
  }
  
  if (!html) {
    html = '<p class="placeholder-text">Nessun campo perizia da compilare</p>';
  }
  
  elements.periziaForm.innerHTML = html;
  elements.fillPeriziaConfirm.disabled = !html.includes('checkbox');
}

async function confirmFillPerizia() {
  const checkboxes = elements.periziaForm.querySelectorAll('input[type="checkbox"]:checked');
  const fields = {};
  
  for (const checkbox of checkboxes) {
    const field = checkbox.dataset.field;
    const valueEl = checkbox.closest('.perizia-field').querySelector('.value');
    fields[field] = valueEl.textContent;
  }
  
  try {
    await chrome.tabs.sendMessage(state.currentTab.id, {
      action: 'fillMultiple',
      fields
    });
  } catch (error) {
    console.error('[PerX Popup] Errore fill perizia:', error);
  }
  
  closeModals();
}

async function handleImportAll() {
  if (!confirm('Importare tutti i dati da JFish a PerX?\n\nQuesta operazione aggiornerà il sinistro PerX con i dati attuali di JFish.')) return;
  
  try {
    // Estrai dati da JFish
    const jfishResponse = await chrome.tabs.sendMessage(state.currentTab.id, { action: 'extractData' });
    
    if (!jfishResponse.success) {
      throw new Error('Impossibile estrarre dati da JFish');
    }
    
    // Prima verifica le differenze
    const compareResponse = await chrome.runtime.sendMessage({
      action: 'jfishCompare',
      jfishData: jfishResponse.data
    });
    
    if (!compareResponse.success) {
      throw new Error(compareResponse.error || 'Errore confronto dati');
    }
    
    const result = compareResponse.data;
    
    if (!result.sinistroExists) {
      alert('Sinistro non trovato in PerX.\n\nVerifica che il sinistro esista nel database PerX.');
      return;
    }
    
    if (result.differences.length === 0) {
      alert('Nessuna differenza rilevata.\n\nI dati JFish e PerX sono già sincronizzati.');
      return;
    }
    
    // Mostra riepilogo differenze
    const diffSummary = result.differences.map(d => `• ${d.field}: "${d.perxValue}" → "${d.jfishValue}"`).join('\n');
    
    if (!confirm(`Trovate ${result.differences.length} differenze:\n\n${diffSummary}\n\nProcedere con l'import?`)) {
      return;
    }
    
    // Esegui import
    const importResponse = await chrome.runtime.sendMessage({
      action: 'jfishImportAll',
      ref: state.contentState.sinistroRef,
      jfishData: jfishResponse.data
    });
    
    if (importResponse.success) {
      const data = importResponse.data;
      let message = `Import completato!\n\nAggiornati ${data.updatedFields.length} campi.`;
      
      if (data.failedFields && data.failedFields.length > 0) {
        message += `\n\n⚠️ ${data.failedFields.length} campi non aggiornati:\n${data.failedFields.join('\n')}`;
      }
      
      alert(message);
      
      // Aggiorna UI
      await handleRefresh();
    } else {
      throw new Error(importResponse.error || 'Errore durante l\'import');
    }
    
  } catch (error) {
    alert('Errore: ' + error.message);
  }
}

async function handleExportAll() {
  if (!confirm('Compilare tutti i campi JFish con i dati PerX?')) return;
  
  try {
    const response = await chrome.runtime.sendMessage({
      action: 'getSinistro',
      ref: state.contentState.sinistroRef
    });
    
    if (response.success) {
      await chrome.tabs.sendMessage(state.currentTab.id, {
        action: 'fillMultiple',
        fields: response.data
      });
      
      alert('Campi compilati con successo!');
    }
  } catch (error) {
    alert('Errore: ' + error.message);
  }
}

function toggleSettings() {
  state.showSettings = !state.showSettings;
  
  if (state.showSettings) {
    elements.mainSection.classList.add('hidden');
    elements.settingsSection.classList.remove('hidden');
  } else {
    elements.mainSection.classList.remove('hidden');
    elements.settingsSection.classList.add('hidden');
  }
}

async function handleSaveHub() {
  const url = elements.hubUrl.value.trim();
  if (!url) {
    alert('Inserisci un URL valido');
    return;
  }
  
  elements.saveHubBtn.disabled = true;
  
  try {
    await chrome.runtime.sendMessage({
      action: 'setHubUrl',
      url: url
    });
    
    await checkHub();
    
    if (state.hubConnected) {
      alert('Hub connesso con successo!');
    } else {
      alert('Impossibile connettersi all\'Hub');
    }
  } catch (error) {
    alert('Errore: ' + error.message);
  } finally {
    elements.saveHubBtn.disabled = false;
  }
}

function closeModals() {
  elements.diarioModal.classList.add('hidden');
  elements.periziaModal.classList.add('hidden');
}

/**
 * Mostra toast notification
 */
function showToast(message, type = 'success') {
  // Rimuovi toast esistente
  const existing = document.querySelector('.toast');
  if (existing) existing.remove();
  
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  toast.style.cssText = `
    position: fixed;
    bottom: 60px;
    left: 50%;
    transform: translateX(-50%);
    padding: 8px 16px;
    background-color: ${type === 'success' ? 'var(--success)' : 'var(--danger)'};
    color: white;
    border-radius: 6px;
    font-size: 12px;
    z-index: 2000;
    animation: fadeInOut 2s ease;
  `;
  
  document.body.appendChild(toast);
  
  setTimeout(() => toast.remove(), 2000);
}

// Inizializza
init();
