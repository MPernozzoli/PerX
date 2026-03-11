/**
 * PerX JFish Sync - Content Script
 * Iniettato nelle pagine JFish per scraping/form-filling e icone sync inline
 */

// Protezione contro doppia inizializzazione
// (può accadere se lo script viene iniettato mentre era già caricato)
if (window.__perxContentScriptLoaded) {
  console.log('[PerX Content] Script già caricato, skip');
  
  // Anche se già caricato, rispondi comunque ai messaggi 'ping'
  // per permettere al background di verificare che siamo attivi
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === 'ping') {
      sendResponse({ success: true, version: '1.0.0', alreadyLoaded: true });
      return true;
    }
  });
  
} else {
  window.__perxContentScriptLoaded = true;
  
// === INIZIO CONTENUTO SCRIPT ===

// Stato del content script
const state = {
  isJFishPage: false,
  currentSinistroRef: null,
  perxData: null,
  jfishData: null,
  syncIcons: []
};

// Configurazione JFish - act.jfish.it
const JFISH_CONFIG = {
  // Pattern URL per riconoscere pagine JFish
  urlPatterns: [
    /act\.jfish\.it/i
  ],
  
  // Hostname JFish
  hostname: 'act.jfish.it',
  
  /**
   * Campi del dettaglio sinistro.
   * JFish usa ID dinamici nel formato: nomeCampo{sinistroId}
   * Es: stato2600993, mask_dataSinistro2600993
   */
  fields: {
    // Identificazione sinistro
    idInternoSinistro: 'id_interno_sinistro',      // ID interno JFish
    stato: 'stato',                                  // Stato corrente (dropdown)
    numeroSinistro: 'numeroSinistro',               // Numero sinistro agenzia
    riferimento: 'numeroSinistroCompagnia',         // Numero sinistro compagnia (riferimento)
    
    // Date principali (prefisso mask_ per date picker)
    dataSinistro: 'mask_dataSinistro',
    dataDenunciato: 'mask_denunciato',
    dataIncarico: 'mask_incarico',
    dataSopralluogo: 'mask_dataSopralluogo',
    dataChiusura: 'mask_chiusura',
    dataInvioAtto: 'mask_dataInvioAtto',
    
    // Liquidatore
    liquidatore: 'liquidatore',
    telefonoLiquidatore: 'telefonoLiquidatore',
    emailLiquidatore: 'emailLiquidatore',
    
    // Broker
    broker: 'broker',
    telefonoBroker: 'telefonoBroker',
    emailBroker: 'emailBroker',
    
    // Contraente
    contraente: 'contraente',
    telefonoContraente: 'telefonoContraente',
    emailContraente: 'emailContraente',
    
    // Assicurato
    assicurato: 'assicurato',
    telefonoAssicurato: 'telefonoAssicurato',
    emailAssicurato: 'emailAssicurato',
    
    // Amministratore
    amministratore: 'amministratore',
    telefonoAmministratore: 'telefonoAmministratore',
    emailAmministratore: 'emailAmministratore',
    
    // Danneggiato
    danneggiato: 'danneggiato',
    telefonoDanneggiato: 'telefonoDanneggiato',
    emailDanneggiato: 'emailDanneggiato',
    codiceFiscaleDanneggiato: 'codiceFiscaleDanneggiato',
    partitaIVADanneggiato: 'partitaIVADanneggiato',
    ibanDanneggiato: 'IBANDanneggiato',
    
    // Polizza e garanzia
    gruppo: 'gruppo',
    compagnia: 'compagnia',
    garanzia: 'garanzia',
    ramo: 'ramo',
    numeroPolizza: 'numeroPolizza',
    tipoPolizza: 'tipoPolizza',
    prodotto: 'prodotto',
    
    // Ubicazione rischio
    indirizzoUbicazione: 'indirizzoUbicazioneRischio',
    cittaUbicazione: 'cittaUbicazioneRischio',
    capUbicazione: 'capUbicazioneRischio',
    provinciaUbicazione: 'provinciaUbicazioneRischio',
    nazioneUbicazione: 'nazioneUbicazioneRischio',
    
    // Denuncia
    noteEstrattoDenuncia: 'noteEstrattoDenuncia',   // Rich text
    giustificativiDenuncia: 'giustificativiDenuncia',
    riservaDenuncia: 'riservaDenuncia',             // Importo
    richiestaDenuncia: 'richiestaDenuncia',         // Importo
    
    // Perizia
    esitoPerizia: 'esito',
    importoLiquidato: 'importoLiquidato',
    dannoAccertato: 'dannoAccertato',
    complessita: 'complessita',
    checkRegolaritaAmministrativa: 'checkRegolaritaAmministrativa',
    checkVincoli: 'checkVincoli',
    
    // Checkbox vari
    riapertura: 'riapertura',
    triage: 'triage',
    prontaDefinizione: 'prontaDefinizione',
    noResidui: 'noResidui',
    danniIndiretti: 'danniIndiretti',
    videoperizia: 'videoperizia',
    documentale: 'documentale',
    periziaSemplificata: 'periziaSemplificata',
    piuGaranzieInteressate: 'piuGaranzieInteressate',
    rfsFattibile: 'RFSFattibileContrattualmente',
    richiestaRiparazione: 'richiestaRiparazione',
    sollgiust: 'sollgiust',
    sollatto: 'sollatto',
    
    // Servizio
    tipoServizio: 'tipoServizio',
    dataPagamentoPremio: 'mask_dataPagamentoPremio',
    checkMantenimentoPolizza: 'checkMantenimentoPolizza',
    notaMantenimentoPolizza: 'notaMantenimentoPolizza',
    
    // Assegnazioni
    assegnaCat: 'assegnaCat',
    noteCat: 'noteCat',                             // Rich text
    assegnaPerito: 'assegnaPerito',
    
    // Controllo Referenti (CR)
    assegnaCR: 'assegnaCR',
    dataAssegnCR: 'mask_dataAssegnCR',
    dataContrCR: 'mask_dataContrCR',
    
    // Controllo Qualità (CQ) - fino a 4 livelli
    assegnaCQ1: 'assegnaCQ1',
    dataAssegnCQ1: 'mask_dataAssegnCQ1',
    dataContrCQ1: 'mask_dataContrCQ1',
    
    // Cambio stato
    ddlCambiaStato: 'ddlCambiaStato',
    dataAlert: 'mask_dataAlert',
    
    // Azioni
    ddlAzione: 'ddlAzione',
    ddlAChi: 'ddlAChi',
    ddlCosa: 'ddlCosa',
    
    // Note finali
    noteFin: 'noteFin'                              // Rich text
  },
  
  // Selettori statici per elementi che non dipendono dall'ID sinistro
  staticSelectors: {
    // Container principale del dettaglio
    detailContainer: '#contenutoSituazioneSinistri',
    
    // Grid dei sinistri nella lista
    sinistriGrid: '#GridSituazioneSinistri',
    
    // Tab principale
    tabSinistri: '#TabSituazioneSinistri',
    
    // Diario - cerchiamo la griglia del diario
    diarioGrid: '[id^="GridDiario"]',
    diarioEntry: 'tr[class*="e-row"]',
    
    // Form perizia
    formPerizia: '[id^="FormPerizia"]'
  }
};

// ID del sinistro corrente rilevato dalla pagina
let currentSinistroId = null;

/**
 * Rileva l'ID del sinistro dalla pagina JFish.
 * PRIORITA': Tab attiva nella barra principale (TabSituazioneSinistri)
 * @returns {string|null} L'ID del sinistro o null se non trovato
 */
function detectSinistroId() {
  // METODO PRINCIPALE: Cerca la TAB ATTIVA nella barra principale TabSituazioneSinistri
  // Queste tab hanno data-id con l'ID numerico del sinistro (es. data-id="2600993")
  const activeMainTab = document.querySelector('[id*="TabSituazioneSinistri"] .e-toolbar-item.e-active[data-id]');
  if (activeMainTab) {
    const sinistroId = activeMainTab.getAttribute('data-id');
    // Verifica che sia un numero (non "tabitem_0" o simili)
    if (sinistroId && /^\d+$/.test(sinistroId)) {
      return sinistroId;
    }
  }
  
  // Metodo 2: Cerca la tab attiva anche senza contenitore esplicito
  const anyActiveTab = document.querySelector('.e-toolbar-item.e-active[data-id]');
  if (anyActiveTab) {
    const sinistroId = anyActiveTab.getAttribute('data-id');
    if (sinistroId && /^\d+$/.test(sinistroId)) {
      return sinistroId;
    }
  }
  
  // Metodo 3: Cerca dal testo della tab attiva "Modifica sinistro num. XXXXXXX"
  const activeTabText = document.querySelector('.e-toolbar-item.e-active .e-tab-text');
  if (activeTabText) {
    const match = activeTabText.textContent.match(/sinistro\s+(?:num\.)?\s*(\d+)/i);
    if (match) {
      return match[1];
    }
  }
  
  // Fallback: Cerca elementi con pattern tabDettaglio{sinistroId} visibili
  const tabElements = document.querySelectorAll('[id*="tabDettaglio"]');
  for (const el of tabElements) {
    // Prendi solo elementi visibili
    if (el.offsetParent !== null || el.closest('.e-active')) {
      const match = el.id.match(/tabDettaglio(\d+)/);
      if (match) {
        return match[1];
      }
    }
  }
  
  // ID sinistro non trovato nella pagina
  return null;
}

/**
 * Costruisce il selettore per un campo JFish dato il nome e l'ID sinistro
 * @param {string} fieldName - Nome del campo (es: 'stato', 'mask_dataSinistro')
 * @param {string} sinistroId - ID del sinistro
 * @returns {string} Selettore CSS
 */
function buildFieldSelector(fieldName, sinistroId) {
  const fullId = `${fieldName}${sinistroId}`;
  // Cerca sia per ID che per name, dato che Syncfusion usa entrambi
  return `#${fullId}, [name="${fullId}"], #${fullId}_hidden`;
}

/**
 * Ottiene il valore di un campo JFish
 * @param {string} fieldName - Nome del campo dalla config
 * @param {string} sinistroId - ID del sinistro
 * @returns {{element: Element|null, value: string|null}}
 */
function getFieldValue(fieldName, sinistroId) {
  const jfishFieldName = JFISH_CONFIG.fields[fieldName];
  if (!jfishFieldName) {
    return { element: null, value: null };
  }
  
  const selector = buildFieldSelector(jfishFieldName, sinistroId);
  const element = document.querySelector(selector);
  
  if (!element) {
    return { element: null, value: null };
  }
  
  let value = null;
  const tagName = element.tagName.toLowerCase();
  
  if (tagName === 'input') {
    value = element.value?.trim() || null;
  } else if (tagName === 'select') {
    // Per i dropdown Syncfusion, cerchiamo l'option selezionata
    const selectedOption = element.querySelector('option:checked');
    value = selectedOption?.textContent?.trim() || element.value?.trim() || null;
  } else if (tagName === 'textarea') {
    value = element.value?.trim() || null;
  } else {
    value = element.textContent?.trim() || null;
  }
  
  // Per checkbox, restituisci boolean
  if (element.type === 'checkbox') {
    value = element.checked;
  }
  
  return { element, value };
}

/**
 * Imposta il valore di un campo JFish
 * @param {string} fieldName - Nome del campo dalla config
 * @param {string} sinistroId - ID del sinistro
 * @param {any} value - Valore da impostare
 * @returns {boolean} true se il campo è stato trovato e compilato
 */
function setFieldValue(fieldName, sinistroId, value) {
  const jfishFieldName = JFISH_CONFIG.fields[fieldName];
  if (!jfishFieldName) {
    return false;
  }
  
  const selector = buildFieldSelector(jfishFieldName, sinistroId);
  const element = document.querySelector(selector);
  
  if (!element) {
    console.warn(`[PerX Content] Campo non trovato: ${fieldName} (${selector})`);
    return false;
  }
  
  return fillField(element, value);
}

/**
 * Verifica se siamo nella pagina di dettaglio sinistro
 * @returns {boolean}
 */
function isDetailPage() {
  // Verifica se esistono campi del dettaglio
  return !!detectSinistroId();
}

/**
 * Inizializza il content script
 */
function init() {
  console.log('[PerX Content] Inizializzazione...');
  
  // Verifica se siamo su una pagina JFish
  state.isJFishPage = isJFishPage();
  
  if (!state.isJFishPage) {
    console.log('[PerX Content] Non è una pagina JFish, skip');
    return;
  }
  
  console.log('[PerX Content] Pagina JFish rilevata!');
  
  // Rileva ID sinistro se siamo nel dettaglio
  currentSinistroId = detectSinistroId();
  
  if (currentSinistroId) {
    console.log('[PerX Content] Pagina dettaglio sinistro, ID:', currentSinistroId);
    // Estrai dati dalla pagina
    extractJFishData();
    
    // Se abbiamo un riferimento, carica dati da PerX
    if (state.currentSinistroRef) {
      loadPerXData(state.currentSinistroRef);
    }
  } else {
    console.log('[PerX Content] Pagina lista sinistri o altra pagina');
  }
  
  // Aggiungi badge PerX sulla pagina
  addPerXBadge();
  
  // Osserva cambiamenti DOM per pagine dinamiche
  observeDOMChanges();
}

/**
 * Verifica se la pagina corrente è JFish
 * @returns {boolean}
 */
function isJFishPage() {
  // Controlla hostname
  if (window.location.hostname === JFISH_CONFIG.hostname) {
    return true;
  }
  
  // Controlla pattern URL
  const url = window.location.href;
  for (const pattern of JFISH_CONFIG.urlPatterns) {
    if (pattern.test(url)) {
      return true;
    }
  }
  
  return false;
}

/**
 * Estrae dati dalla pagina JFish (dettaglio sinistro)
 */
function extractJFishData() {
  const data = {};
  
  if (!currentSinistroId) {
    console.log('[PerX Content] Nessun sinistro rilevato, skip estrazione');
    state.jfishData = data;
    return data;
  }
  
  const id = currentSinistroId;
  
  // RIFERIMENTO = ID sinistro JFish (es: 2600993) - UNIQUE KEY per sincronizzazione
  // Questo è l'ID che appare in tutti i campi dinamici come stato2600993, mask_dataSinistro2600993, ecc.
  data.riferimento = id; // 'id' è già il sinistroId rilevato dalla pagina
  state.currentSinistroRef = id;
  
  console.log('[PerX Content] >>> RIFERIMENTO IMPOSTATO:', id, '(versione aggiornata)');
  
  // ID interno (valore del campo id_interno_sinistro, se diverso)
  const { value: idInterno } = getFieldValue('idInternoSinistro', id);
  data.idInternoJFish = idInterno || id;
  
  // Numero sinistro agenzia (campo secondario per visualizzazione)
  const { value: numeroSinistro } = getFieldValue('numeroSinistro', id);
  data.numeroSinistro = numeroSinistro;
  
  // Numero sinistro compagnia (altro campo secondario)
  const { value: numeroCompagnia } = getFieldValue('riferimento', id);
  data.numeroSinistroCompagnia = numeroCompagnia;
  
  console.log('[PerX Content] Riferimento (unique key):', id);
  
  // Stato
  const { value: stato } = getFieldValue('stato', id);
  data.stato = stato;
  
  // Date principali (tutte quelle da sincronizzare)
  const dateFields = [
    'dataSinistro', 'dataDenunciato', 'dataIncarico', 
    'dataSopralluogo', 'dataChiusura', 'dataInvioAtto',
    'dataPagamentoPremio'
  ];
  for (const field of dateFields) {
    const { value, element } = getFieldValue(field, id);
    data[field] = value;
    // Debug: log se il campo non viene trovato
    if (!element) {
      console.log(`[PerX Content] Campo data non trovato: ${field} (cercato: ${JFISH_CONFIG.fields[field]}${id})`);
    }
  }
  
  // Soggetti coinvolti
  const soggetti = ['liquidatore', 'broker', 'contraente', 'assicurato', 'amministratore', 'danneggiato'];
  for (const soggetto of soggetti) {
    const { value: nome } = getFieldValue(soggetto, id);
    const { value: telefono } = getFieldValue(`telefono${capitalize(soggetto)}`, id);
    const { value: email } = getFieldValue(`email${capitalize(soggetto)}`, id);
    
    if (nome || telefono || email) {
      data[soggetto] = { nome, telefono, email };
    }
  }
  
  // Dati aggiuntivi danneggiato
  const { value: cfDanneggiato } = getFieldValue('codiceFiscaleDanneggiato', id);
  const { value: pivaDanneggiato } = getFieldValue('partitaIVADanneggiato', id);
  const { value: ibanDanneggiato } = getFieldValue('ibanDanneggiato', id);
  if (data.danneggiato) {
    data.danneggiato.codiceFiscale = cfDanneggiato;
    data.danneggiato.partitaIVA = pivaDanneggiato;
    data.danneggiato.iban = ibanDanneggiato;
  }
  
  // Polizza e garanzia
  const { value: gruppo } = getFieldValue('gruppo', id);
  const { value: compagnia } = getFieldValue('compagnia', id);
  const { value: garanzia } = getFieldValue('garanzia', id);
  const { value: ramo } = getFieldValue('ramo', id);
  const { value: numeroPolizza } = getFieldValue('numeroPolizza', id);
  const { value: tipoPolizza } = getFieldValue('tipoPolizza', id);
  const { value: prodotto } = getFieldValue('prodotto', id);
  
  data.polizza = {
    gruppo, compagnia, garanzia, ramo,
    numero: numeroPolizza, tipo: tipoPolizza, prodotto
  };
  
  // Ubicazione rischio
  const { value: indirizzo } = getFieldValue('indirizzoUbicazione', id);
  const { value: citta } = getFieldValue('cittaUbicazione', id);
  const { value: cap } = getFieldValue('capUbicazione', id);
  const { value: provincia } = getFieldValue('provinciaUbicazione', id);
  const { value: nazione } = getFieldValue('nazioneUbicazione', id);
  
  data.ubicazione = { indirizzo, citta, cap, provincia, nazione };
  
  // Importi denuncia
  const { value: riservaDenuncia } = getFieldValue('riservaDenuncia', id);
  const { value: richiestaDenuncia } = getFieldValue('richiestaDenuncia', id);
  data.riservaDenuncia = parseImporto(riservaDenuncia);
  data.richiestaDenuncia = parseImporto(richiestaDenuncia);
  
  // Importi perizia
  const { value: importoLiquidato } = getFieldValue('importoLiquidato', id);
  const { value: dannoAccertato } = getFieldValue('dannoAccertato', id);
  data.importoLiquidato = parseImporto(importoLiquidato);
  data.dannoAccertato = parseImporto(dannoAccertato);
  
  // Complessità pratica
  const { value: complessita } = getFieldValue('complessita', id);
  data.complessita = complessita;
  
  // Esito perizia
  const { value: esitoPerizia } = getFieldValue('esitoPerizia', id);
  data.esitoPerizia = esitoPerizia;
  
  // Checkbox vari
  const checkboxFields = [
    'riapertura', 'triage', 'prontaDefinizione', 'noResidui', 
    'danniIndiretti', 'videoperizia', 'documentale', 
    'periziaSemplificata', 'piuGaranzieInteressate', 'rfsFattibile',
    'richiestaRiparazione', 'sollgiust', 'sollatto'
  ];
  data.flags = {};
  for (const field of checkboxFields) {
    const { value } = getFieldValue(field, id);
    if (value !== null) {
      data.flags[field] = value;
    }
  }
  
  // Tipo servizio
  const { value: tipoServizio } = getFieldValue('tipoServizio', id);
  data.tipoServizio = tipoServizio;
  
  state.jfishData = data;
  console.log('[PerX Content] Dati JFish estratti:', data);
  
  return data;
}

/**
 * Capitalizza la prima lettera di una stringa
 */
function capitalize(str) {
  if (!str) return '';
  return str.charAt(0).toUpperCase() + str.slice(1);
}

/**
 * Estrae entry del diario dalla pagina JFish
 * Il diario usa una griglia Syncfusion con ID GridDiario{sinistroId}
 * @returns {Array}
 */
function extractDiarioEntries() {
  const entries = [];
  
  if (!currentSinistroId) {
    console.log('[PerX Content] Nessun sinistro, skip estrazione diario');
    return entries;
  }
  
  // Cerca la griglia del diario
  const diarioGridSelector = `#GridDiario${currentSinistroId}`;
  const diarioGrid = document.querySelector(diarioGridSelector) || 
                     document.querySelector(JFISH_CONFIG.staticSelectors.diarioGrid);
  
  if (!diarioGrid) {
    console.log('[PerX Content] Griglia diario non trovata');
    return entries;
  }
  
  // Le righe del diario sono nella tbody della griglia
  const rows = diarioGrid.querySelectorAll('tbody tr.e-row');
  
  rows.forEach((row, index) => {
    const cells = row.querySelectorAll('td');
    
    // La struttura tipica delle colonne del diario JFish:
    // Data | Ora | Autore | Tipo | Descrizione | ...
    const entry = {
      index,
      // Adattiamo in base alla struttura reale - questi sono placeholder
      data: cells[0]?.textContent?.trim(),
      ora: cells[1]?.textContent?.trim(),
      autore: cells[2]?.textContent?.trim(),
      tipo: cells[3]?.textContent?.trim(),
      descrizione: cells[4]?.textContent?.trim() || cells[3]?.textContent?.trim()
    };
    
    // Cerca attributi aria per capire meglio la struttura
    cells.forEach((cell, cellIndex) => {
      const ariaLabel = cell.getAttribute('aria-label');
      if (ariaLabel) {
        entry[`col${cellIndex}_label`] = ariaLabel;
      }
    });
    
    if (entry.data || entry.descrizione) {
      entries.push(entry);
    }
  });
  
  console.log('[PerX Content] Entry diario estratte:', entries.length);
  return entries;
}

/**
 * Carica dati da PerX per un sinistro
 * @param {string} ref 
 */
async function loadPerXData(ref) {
  console.log('[PerX Content] Caricamento dati PerX per:', ref);
  
  try {
    const response = await chrome.runtime.sendMessage({
      action: 'getSinistro',
      ref: ref
    });
    
    if (response.success) {
      state.perxData = response.data;
      state.perxSinistroExists = true;
      console.log('[PerX Content] Dati PerX caricati:', state.perxData);
    } else {
      // Sinistro non esiste su PerX - tratta come nuovo
      state.perxData = null;
      state.perxSinistroExists = false;
      console.log('[PerX Content] Sinistro non presente su PerX, tutti i campi sono nuovi');
    }
    
    // Inietta icone in entrambi i casi
    injectSyncIcons();
    
  } catch (error) {
    console.error('[PerX Content] Errore comunicazione:', error);
    state.perxData = null;
    state.perxSinistroExists = false;
  }
}

/**
 * Confronta dati JFish con PerX e restituisce differenze
 * @returns {Array<{field: string, jfishValue: any, perxValue: any, element: Element}>}
 */
function findDifferences() {
  const diffs = [];
  
  if (!state.jfishData || !currentSinistroId) {
    return diffs;
  }
  
  // Se perxData è null, il sinistro non esiste su PerX
  // In questo caso tutti i campi JFish con valore sono considerati "nuovi"
  const perxData = state.perxData || {};
  
  // Mappa campi JFish (config name) → PerX (nome nel DTO)
  // NOTA: "data riconsegnato" su JFish = "dataChiusura" su PerX
  const fieldMapping = {
    // Stato
    stato: { perxField: 'stato', type: 'stato', label: 'Stato' },
    
    // Date principali
    dataSinistro: { perxField: 'dataSinistro', type: 'date', label: 'Data Sinistro' },
    dataIncarico: { perxField: 'dataIncarico', type: 'date', label: 'Data Incarico' },
    dataDenunciato: { perxField: 'dataAssegnazione', type: 'date', label: 'Data Assegnazione' },
    dataSopralluogo: { perxField: 'dataSopralluogo', type: 'date', label: 'Data Sopralluogo' },
    dataChiusura: { perxField: 'dataChiusura', type: 'date', label: 'Data Riconsegnato' }, // JFish: riconsegnato → PerX: chiusura
    dataPagamentoPremio: { perxField: 'dataPagamentoPremio', type: 'date', label: 'Data Pagamento Premio' },
    
    // Importi
    riservaDenuncia: { perxField: 'riserva', type: 'importo', label: 'Riserva' },
    richiestaDenuncia: { perxField: 'richiesta', type: 'importo', label: 'Richiesta' },
    
    // Tipo servizio
    tipoServizio: { perxField: 'tipoServizio', type: 'text', label: 'Tipo Servizio' }
  };
  
  for (const [jfishField, config] of Object.entries(fieldMapping)) {
    const jfishValue = state.jfishData[jfishField];
    const perxValue = perxData[config.perxField];
    
    // Salta se entrambi vuoti
    if (isEmpty(jfishValue) && isEmpty(perxValue)) continue;
    
    // Confronta valori in base al tipo
    let isDifferent = false;
    
    switch (config.type) {
      case 'stato':
        isDifferent = !areStatesEquivalent(jfishValue, perxValue);
        break;
      case 'date':
        isDifferent = !areDatesEqual(jfishValue, perxValue);
        break;
      case 'importo':
        const jNum = typeof jfishValue === 'number' ? jfishValue : parseImporto(jfishValue);
        const pNum = typeof perxValue === 'number' ? perxValue : parseImporto(perxValue);
        isDifferent = jNum !== pNum;
        break;
      default:
        isDifferent = String(jfishValue || '') !== String(perxValue || '');
    }
    
    if (isDifferent) {
      // Ottieni l'elemento dal DOM
      const { element } = getFieldValue(jfishField, currentSinistroId);
      
      diffs.push({
        field: jfishField,
        perxField: config.perxField,
        type: config.type,
        jfishValue,
        perxValue,
        element
      });
    }
  }
  
  console.log('[PerX Content] Differenze trovate:', diffs.length);
  return diffs;
}

/**
 * Verifica se un valore è vuoto
 */
function isEmpty(value) {
  if (value === null || value === undefined) return true;
  if (typeof value === 'string' && value.trim() === '') return true;
  if (typeof value === 'object' && Object.keys(value).length === 0) return true;
  return false;
}

/**
 * Inietta icone di sincronizzazione accanto ai campi diversi
 */
function injectSyncIcons() {
  // Rimuovi icone precedenti
  removeSyncIcons();
  
  console.log('[PerX Content] injectSyncIcons() chiamata, sinistroId:', currentSinistroId, 'jfishData:', !!state.jfishData, 'perxData:', !!state.perxData);
  
  const diffs = findDifferences();
  
  console.log('[PerX Content] Differenze da visualizzare:', diffs.map(d => ({ field: d.field, hasElement: !!d.element })));
  
  for (const diff of diffs) {
    if (!diff.element) {
      console.warn('[PerX Content] Elemento non trovato per campo:', diff.field);
      continue;
    }
    
    const icon = createSyncIcon(diff);
    
    // Inserisci dopo l'elemento
    diff.element.parentNode.insertBefore(icon, diff.element.nextSibling);
    
    // Evidenzia il campo
    diff.element.classList.add('perx-field-diff');
    
    state.syncIcons.push({ icon, element: diff.element });
  }
  
  console.log('[PerX Content] Icone sync iniettate:', state.syncIcons.length);
}

/**
 * Crea un'icona di sincronizzazione
 * @param {object} diff 
 * @returns {HTMLElement}
 */
function createSyncIcon(diff) {
  const icon = document.createElement('span');
  icon.className = 'perx-sync-icon';
  icon.setAttribute('data-field', diff.field);
  icon.setAttribute('data-perx-field', diff.perxField);
  
  // Tooltip con info sui valori
  const jfishVal = formatDisplayValue(diff.jfishValue, diff.type);
  const perxVal = formatDisplayValue(diff.perxValue, diff.type);
  icon.setAttribute('data-tooltip', `Clicca per inviare a PerX\nJFish: ${jfishVal}\nPerX: ${perxVal}`);
  icon.setAttribute('title', `Sincronizza ${diff.field}: "${jfishVal}" → PerX`);
  
  // Icona SVG (freccia upload verso cloud)
  icon.innerHTML = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" 
         stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M12 16V4M12 4L8 8M12 4L16 8"/>
      <path d="M20 21H4"/>
    </svg>
  `;
  
  // Click handler
  icon.addEventListener('click', async (e) => {
    e.preventDefault();
    e.stopPropagation();
    
    await handleSyncClick(diff, icon);
  });
  
  return icon;
}

/**
 * Formatta un valore per la visualizzazione
 */
function formatDisplayValue(value, type) {
  if (value === null || value === undefined) return '(vuoto)';
  if (typeof value === 'object') return JSON.stringify(value);
  if (type === 'importo' && typeof value === 'number') return `€ ${value.toFixed(2)}`;
  return String(value) || '(vuoto)';
}

/**
 * Gestisce click su icona sync
 * Invia il valore JFish a PerX (sovrascrive CloudKit)
 * @param {object} diff 
 * @param {HTMLElement} icon 
 */
async function handleSyncClick(diff, icon) {
  // Evita doppio click
  if (icon.classList.contains('syncing') || icon.classList.contains('synced')) {
    return;
  }
  
  icon.classList.add('syncing');
  
  try {
    // Invia valore JFish a PerX (JFish → CloudKit)
    const response = await chrome.runtime.sendMessage({
      action: 'syncField',
      ref: state.currentSinistroRef,
      field: diff.perxField,
      value: diff.jfishValue
    });
    
    if (response.success) {
      icon.classList.remove('syncing');
      icon.classList.add('synced');
      
      // Aggiorna stato locale
      if (state.perxData) {
        state.perxData[diff.perxField] = diff.jfishValue;
      }
      
      // Rimuovi evidenziazione dal campo
      if (diff.element) {
        diff.element.classList.remove('perx-field-diff');
      }
      
      console.log('[PerX Content] Campo sincronizzato:', diff.field, '→', diff.jfishValue);
    } else {
      throw new Error(response.error || 'Errore sconosciuto');
    }
  } catch (error) {
    console.error('[PerX Content] Errore sync:', error);
    icon.classList.remove('syncing');
    icon.classList.add('error');
    icon.setAttribute('data-tooltip', `Errore: ${error.message}`);
    
    setTimeout(() => {
      icon.classList.remove('error');
      icon.setAttribute('data-tooltip', `PerX: ${diff.perxValue || '(vuoto)'}`);
    }, 3000);
  }
}


/**
 * Compila un campo con un valore
 * Gestisce componenti Syncfusion (dropdown, datepicker, checkbox, ecc.)
 * @param {HTMLElement} element 
 * @param {any} value 
 * @returns {boolean} true se il campo è stato compilato con successo
 */
function fillField(element, value) {
  if (!element) return false;
  
  const tagName = element.tagName.toLowerCase();
  const isDisabled = element.disabled || element.readOnly || 
                     element.classList.contains('e-disabled');
  
  if (isDisabled) {
    console.warn('[PerX Content] Campo disabilitato, skip:', element.id || element.name);
    return false;
  }
  
  try {
    // Checkbox
    if (element.type === 'checkbox') {
      const newChecked = !!value;
      if (element.checked !== newChecked) {
        element.checked = newChecked;
        triggerSyncfusionEvents(element, 'checkbox');
      }
      return true;
    }
    
    // Input text e textarea
    if (tagName === 'input' || tagName === 'textarea') {
      // Controlla se è un date picker Syncfusion (ha classe e-datepicker o simile)
      const isDatePicker = element.classList.contains('e-datepicker') || 
                          element.classList.contains('e-daterangepicker') ||
                          element.id?.startsWith('mask_');
      
      if (isDatePicker) {
        // Per i date picker, formattiamo la data in italiano
        const formattedDate = formatDateItalian(value);
        element.value = formattedDate || '';
      } else {
        element.value = value || '';
      }
      
      triggerSyncfusionEvents(element, 'input');
      return true;
    }
    
    // Select (dropdown Syncfusion)
    if (tagName === 'select') {
      const options = element.querySelectorAll('option');
      let found = false;
      
      for (const option of options) {
        if (option.value === value || 
            option.textContent.trim().toLowerCase() === String(value).toLowerCase()) {
          element.value = option.value;
          found = true;
          break;
        }
      }
      
      if (found) {
        triggerSyncfusionEvents(element, 'select');
      } else {
        console.warn('[PerX Content] Valore non trovato nel dropdown:', value);
      }
      return found;
    }
    
    // Rich text editor Syncfusion
    if (element.classList.contains('e-richtexteditor') || 
        element.closest('.e-richtexteditor')) {
      // Cerca l'area editabile
      const editArea = element.querySelector('.e-content') || 
                      element.querySelector('[contenteditable="true"]');
      if (editArea) {
        editArea.innerHTML = value || '';
        triggerSyncfusionEvents(editArea, 'richtext');
        return true;
      }
    }
    
    // Elemento generico
    element.textContent = value || '';
    return true;
    
  } catch (error) {
    console.error('[PerX Content] Errore compilazione campo:', error);
    return false;
  }
}

/**
 * Triggera gli eventi necessari per i componenti Syncfusion
 * @param {HTMLElement} element 
 * @param {string} componentType 
 */
function triggerSyncfusionEvents(element, componentType) {
  // Eventi base per tutti i componenti
  element.dispatchEvent(new Event('input', { bubbles: true }));
  element.dispatchEvent(new Event('change', { bubbles: true }));
  
  // Focus/blur per attivare validazione
  element.dispatchEvent(new FocusEvent('focus', { bubbles: true }));
  element.dispatchEvent(new FocusEvent('blur', { bubbles: true }));
  
  // Per i dropdown, potrebbe servire anche un click
  if (componentType === 'select') {
    // Cerca il wrapper Syncfusion e triggera evento
    const wrapper = element.closest('.e-ddl') || element.closest('.e-control-wrapper');
    if (wrapper) {
      wrapper.dispatchEvent(new Event('change', { bubbles: true }));
    }
  }
}

/**
 * Formatta una data in formato italiano dd/mm/yyyy
 * @param {string|Date} date 
 * @returns {string}
 */
function formatDateItalian(date) {
  if (!date) return '';
  
  let d;
  if (date instanceof Date) {
    d = date;
  } else if (typeof date === 'string') {
    // Prova a parsare come ISO o italiano
    d = parseDate(date);
  }
  
  if (!d || isNaN(d.getTime())) return '';
  
  const day = String(d.getDate()).padStart(2, '0');
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const year = d.getFullYear();
  
  return `${day}/${month}/${year}`;
}

/**
 * Rimuovi tutte le icone sync
 */
function removeSyncIcons() {
  for (const { icon, element } of state.syncIcons) {
    icon.remove();
    element.classList.remove('perx-field-diff');
  }
  state.syncIcons = [];
}

/**
 * Aggiungi badge PerX sulla pagina
 */
function addPerXBadge() {
  // Rimuovi badge esistente
  const existingBadge = document.querySelector('.perx-page-badge');
  if (existingBadge) {
    existingBadge.remove();
  }
  
  const badge = document.createElement('div');
  badge.className = 'perx-page-badge';
  badge.textContent = 'PerX Sync';
  
  badge.addEventListener('click', () => {
    // Apri popup o mostra menu
    chrome.runtime.sendMessage({ action: 'openPopup' });
  });
  
  document.body.appendChild(badge);
}

/**
 * Osserva cambiamenti DOM per pagine SPA (JFish)
 * Monitora navigazione interna e cambiamenti di contenuto
 */
function observeDOMChanges() {
  let lastUrl = window.location.href;
  let lastSinistroId = currentSinistroId;
  let debounceTimer = null;
  
  // Funzione per controllare se l'ID sinistro è cambiato
  function checkForIdChange() {
    const newId = detectSinistroId();
    if (newId && newId !== lastSinistroId) {
      console.log('[PerX Content] ID sinistro cambiato:', lastSinistroId, '->', newId);
      lastSinistroId = newId;
      handlePageChange();
      return true;
    }
    return false;
  }
  
  // Listener diretto sui click delle tab (metodo più affidabile)
  document.addEventListener('click', (event) => {
    const tabItem = event.target.closest('.e-toolbar-item, .e-tab-wrap');
    if (tabItem) {
      // Click su una tab, controlla dopo un breve delay per dare tempo al DOM
      setTimeout(() => {
        checkForIdChange();
      }, 100);
    }
  }, true);
  
  // Polling periodico come fallback (ogni 2 secondi)
  setInterval(() => {
    checkForIdChange();
  }, 2000);
  
  // Observer per cambiamenti DOM (per nuovi sinistri aperti)
  const observer = new MutationObserver((mutations) => {
    // Debounce per evitare troppi refresh
    if (debounceTimer) {
      clearTimeout(debounceTimer);
    }
    
    debounceTimer = setTimeout(() => {
      // Controlla se l'URL è cambiato (navigazione SPA)
      if (window.location.href !== lastUrl) {
        console.log('[PerX Content] Navigazione SPA rilevata:', window.location.href);
        lastUrl = window.location.href;
        lastSinistroId = null;
        handlePageChange();
        return;
      }
      
      // Controlla se l'ID è cambiato
      checkForIdChange();
    }, 300); // Debounce 300ms
  });
  
  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['class', 'aria-selected']
  });
  
  // Intercetta anche history pushState/replaceState per SPA
  const originalPushState = history.pushState;
  const originalReplaceState = history.replaceState;
  
  history.pushState = function(...args) {
    originalPushState.apply(this, args);
    console.log('[PerX Content] pushState rilevato');
    setTimeout(handlePageChange, 300);
  };
  
  history.replaceState = function(...args) {
    originalReplaceState.apply(this, args);
    console.log('[PerX Content] replaceState rilevato');
    setTimeout(handlePageChange, 300);
  };
  
  // Listener per popstate (back/forward)
  window.addEventListener('popstate', () => {
    console.log('[PerX Content] popstate rilevato');
    setTimeout(handlePageChange, 300);
  });
}

/**
 * Gestisce cambio pagina/contenuto
 */
function handlePageChange() {
  console.log('[PerX Content] Aggiornamento pagina...');
  
  // Rimuovi icone precedenti
  removeSyncIcons();
  
  // Reset stato
  state.jfishData = null;
  state.perxData = null;
  state.currentSinistroRef = null;
  
  // Rileva nuovo ID sinistro
  const newId = detectSinistroId();
  
  if (newId !== currentSinistroId) {
    console.log('[PerX Content] Cambio sinistro:', currentSinistroId, '->', newId);
    currentSinistroId = newId;
  }
  
  if (currentSinistroId) {
    // Estrai nuovi dati
    extractJFishData();
    
    // Il riferimento è l'ID stesso (unique key per sincronizzazione)
    const riferimento = currentSinistroId;
    state.currentSinistroRef = riferimento;
    
    // Carica dati PerX
    loadPerXData(riferimento);
    
    // Notifica il background script del cambio pagina
    console.log('[PerX Content] Notifico cambio a background:', riferimento);
    chrome.runtime.sendMessage({
      action: 'pageChanged',
      isDetailPage: true,
      sinistroId: currentSinistroId,
      sinistroRef: riferimento
    }).catch(() => {}); // Ignora errori se il popup non è aperto
  } else {
    // Notifica che siamo fuori dal dettaglio
    chrome.runtime.sendMessage({
      action: 'pageChanged',
      isDetailPage: false
    }).catch(() => {});
  }
}

// === Utility ===

/**
 * Parsa un importo da stringa a numero
 * @param {string} value 
 * @returns {number|null}
 */
function parseImporto(value) {
  if (!value) return null;
  
  // Rimuovi simbolo euro, spazi, e converti virgola in punto
  const cleaned = value
    .replace(/[€\s]/g, '')
    .replace(/\./g, '') // Rimuovi separatore migliaia
    .replace(',', '.'); // Converti decimali
  
  const num = parseFloat(cleaned);
  return isNaN(num) ? null : num;
}

/**
 * Confronta due stati (usa mapping)
 * @param {string} jfishState 
 * @param {string} perxState 
 * @returns {boolean}
 */
function areStatesEquivalent(jfishState, perxState) {
  if (!jfishState && !perxState) return true;
  if (!jfishState || !perxState) return false;
  
  // Confronto diretto normalizzato
  if (jfishState.toUpperCase().trim() === perxState.toUpperCase().trim()) {
    return true;
  }
  
  // TODO: usa StateMapper da hub-client.js
  // Per ora confronto semplice
  return false;
}

/**
 * Confronta due date
 * @param {string} date1 
 * @param {string} date2 
 * @returns {boolean}
 */
function areDatesEqual(date1, date2) {
  if (!date1 && !date2) return true;
  if (!date1 || !date2) return false;
  
  // Parsa date in formato italiano o ISO
  const d1 = parseDate(date1);
  const d2 = parseDate(date2);
  
  if (!d1 || !d2) return false;
  
  return d1.getTime() === d2.getTime();
}

/**
 * Parsa una data da vari formati
 * @param {string} dateStr 
 * @returns {Date|null}
 */
function parseDate(dateStr) {
  if (!dateStr) return null;
  
  // Formato italiano dd/mm/yyyy
  const italianMatch = dateStr.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (italianMatch) {
    const [, day, month, year] = italianMatch;
    return new Date(parseInt(year), parseInt(month) - 1, parseInt(day));
  }
  
  // Formato ISO
  const isoDate = new Date(dateStr);
  if (!isNaN(isoDate.getTime())) {
    // Normalizza a mezzanotte
    return new Date(isoDate.getFullYear(), isoDate.getMonth(), isoDate.getDate());
  }
  
  return null;
}

// === Listener messaggi dal background ===

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('[PerX Content] Messaggio ricevuto:', message.action);
  
  switch (message.action) {
    case 'ping':
      // Usato per verificare se il content script è già iniettato
      sendResponse({ success: true, version: '1.0.0' });
      break;
      
    case 'extractData':
      // Rileva ID se non già fatto
      if (!currentSinistroId) {
        currentSinistroId = detectSinistroId();
      }
      const data = extractJFishData();
      sendResponse({ 
        success: true, 
        data,
        sinistroId: currentSinistroId,
        sinistroRef: state.currentSinistroRef
      });
      break;
      
    case 'extractDiario':
      const entries = extractDiarioEntries();
      sendResponse({ 
        success: true, 
        entries,
        sinistroId: currentSinistroId 
      });
      break;
      
    case 'fillField':
      if (!currentSinistroId) {
        sendResponse({ success: false, error: 'Nessun sinistro rilevato' });
        break;
      }
      const success = setFieldValue(message.field, currentSinistroId, message.value);
      sendResponse({ success, error: success ? null : 'Campo non trovato o non compilabile' });
      break;
      
    case 'fillMultiple':
      if (!currentSinistroId) {
        sendResponse({ success: false, error: 'Nessun sinistro rilevato' });
        break;
      }
      const results = {};
      for (const [field, value] of Object.entries(message.fields)) {
        results[field] = setFieldValue(field, currentSinistroId, value);
      }
      const allSuccess = Object.values(results).every(r => r);
      sendResponse({ success: allSuccess, results });
      break;
      
    case 'refresh':
      handlePageChange();
      sendResponse({ 
        success: true,
        sinistroId: currentSinistroId,
        sinistroRef: state.currentSinistroRef
      });
      break;
      
    case 'getState':
      // Assicurati che l'ID sia aggiornato prima di rispondere
      if (!currentSinistroId) {
        currentSinistroId = detectSinistroId();
      }
      // Usa direttamente currentSinistroId come riferimento
      sendResponse({
        isJFishPage: state.isJFishPage,
        isDetailPage: !!currentSinistroId,
        sinistroId: currentSinistroId,
        sinistroRef: currentSinistroId, // Riferimento = ID sinistro
        hasPerxData: !!state.perxData,
        hasJFishData: !!state.jfishData,
        jfishData: state.jfishData,
        differences: findDifferences().length
      });
      break;
      
    case 'getDifferences':
      const diffs = findDifferences();
      sendResponse({ 
        success: true, 
        differences: diffs.map(d => ({
          field: d.field,
          perxField: d.perxField,
          type: d.type,
          jfishValue: d.jfishValue,
          perxValue: d.perxValue,
          hasElement: !!d.element
        }))
      });
      break;
      
    case 'syncField':
      // Sincronizza un singolo campo da PerX a JFish
      if (!currentSinistroId) {
        sendResponse({ success: false, error: 'Nessun sinistro rilevato' });
        break;
      }
      const syncSuccess = setFieldValue(message.field, currentSinistroId, message.value);
      sendResponse({ success: syncSuccess });
      break;
      
    case 'injectSyncIcons':
      // Inietta manualmente le icone di sync
      injectSyncIcons();
      sendResponse({ success: true, count: state.syncIcons.length });
      break;
      
    default:
      sendResponse({ success: false, error: 'Azione sconosciuta' });
  }
  
  return true;
});

// Inizializza quando il DOM è pronto
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

} // Chiusura del blocco else per protezione doppia inizializzazione
