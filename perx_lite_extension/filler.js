/**
 * PerX Lite - filler.js
 *
 * Iniettato on-demand (via chrome.scripting) nella pagina JFish attiva quando
 * l'utente clicca "Compila pagina" nel popup. Nessun listener persistente,
 * nessuna osservazione DOM continua: gira una volta, fa il suo lavoro, finisce.
 *
 * Espone window.__perxLite con le funzioni richiamate dal popup.
 */
(function () {
  if (window.__perxLite) {
    // Già iniettato in questa pagina in questa sessione: riusa l'istanza.
    return;
  }

  /**
   * Mappa campo logico -> nome campo JFish (senza suffisso id sinistro).
   * Portata 1:1 da perx_chrome_extension/content.js (JFISH_CONFIG.fields),
   * l'unica parte del vecchio content script riusata qui perché già
   * verificata sul gestionale reale.
   */
  const JFISH_FIELDS = {
    idInternoSinistro: 'id_interno_sinistro',
    stato: 'stato',
    numeroSinistro: 'numeroSinistro',
    riferimento: 'numeroSinistroCompagnia',

    dataSinistro: 'mask_dataSinistro',
    dataDenunciato: 'mask_denunciato',
    dataIncarico: 'mask_incarico',
    dataSopralluogo: 'mask_dataSopralluogo',
    dataChiusura: 'mask_chiusura',
    dataInvioAtto: 'mask_dataInvioAtto',

    liquidatore: 'liquidatore',
    telefonoLiquidatore: 'telefonoLiquidatore',
    emailLiquidatore: 'emailLiquidatore',

    broker: 'broker',
    telefonoBroker: 'telefonoBroker',
    emailBroker: 'emailBroker',

    contraente: 'contraente',
    telefonoContraente: 'telefonoContraente',
    emailContraente: 'emailContraente',

    assicurato: 'assicurato',
    telefonoAssicurato: 'telefonoAssicurato',
    emailAssicurato: 'emailAssicurato',

    amministratore: 'amministratore',
    telefonoAmministratore: 'telefonoAmministratore',
    emailAmministratore: 'emailAmministratore',

    danneggiato: 'danneggiato',
    telefonoDanneggiato: 'telefonoDanneggiato',
    emailDanneggiato: 'emailDanneggiato',
    codiceFiscaleDanneggiato: 'codiceFiscaleDanneggiato',
    partitaIVADanneggiato: 'partitaIVADanneggiato',
    ibanDanneggiato: 'IBANDanneggiato',

    gruppo: 'gruppo',
    compagnia: 'compagnia',
    garanzia: 'garanzia',
    ramo: 'ramo',
    numeroPolizza: 'numeroPolizza',
    tipoPolizza: 'tipoPolizza',
    prodotto: 'prodotto',

    indirizzoUbicazione: 'indirizzoUbicazioneRischio',
    cittaUbicazione: 'cittaUbicazioneRischio',
    capUbicazione: 'capUbicazioneRischio',
    provinciaUbicazione: 'provinciaUbicazioneRischio',
    nazioneUbicazione: 'nazioneUbicazioneRischio',

    noteEstrattoDenuncia: 'noteEstrattoDenuncia',
    giustificativiDenuncia: 'giustificativiDenuncia',
    riservaDenuncia: 'riservaDenuncia',
    richiestaDenuncia: 'richiestaDenuncia',

    esitoPerizia: 'esito',
    importoLiquidato: 'importoLiquidato',
    dannoAccertato: 'dannoAccertato',
    complessita: 'complessita',
    checkRegolaritaAmministrativa: 'checkRegolaritaAmministrativa',
    checkVincoli: 'checkVincoli',

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

    tipoServizio: 'tipoServizio',
    dataPagamentoPremio: 'mask_dataPagamentoPremio',
    checkMantenimentoPolizza: 'checkMantenimentoPolizza',
    notaMantenimentoPolizza: 'notaMantenimentoPolizza',

    assegnaCat: 'assegnaCat',
    noteCat: 'noteCat',
    assegnaPerito: 'assegnaPerito',

    assegnaCR: 'assegnaCR',
    dataAssegnCR: 'mask_dataAssegnCR',
    dataContrCR: 'mask_dataContrCR',

    assegnaCQ1: 'assegnaCQ1',
    dataAssegnCQ1: 'mask_dataAssegnCQ1',
    dataContrCQ1: 'mask_dataContrCQ1',

    ddlCambiaStato: 'ddlCambiaStato',
    dataAlert: 'mask_dataAlert',

    ddlAzione: 'ddlAzione',
    ddlAChi: 'ddlAChi',
    ddlCosa: 'ddlCosa',

    noteFin: 'noteFin',
  };

  /** Etichette leggibili per la UI del popup (mostrate nel menu di mappatura). */
  const JFISH_FIELD_LABELS = {
    idInternoSinistro: 'ID interno JFish',
    stato: 'Stato',
    numeroSinistro: 'Numero sinistro (agenzia)',
    riferimento: 'Numero sinistro compagnia',
    dataSinistro: 'Data sinistro',
    dataDenunciato: 'Data denuncia',
    dataIncarico: 'Data incarico',
    dataSopralluogo: 'Data sopralluogo',
    dataChiusura: 'Data chiusura',
    dataInvioAtto: 'Data invio atto',
    liquidatore: 'Liquidatore',
    telefonoLiquidatore: 'Telefono liquidatore',
    emailLiquidatore: 'Email liquidatore',
    broker: 'Broker',
    telefonoBroker: 'Telefono broker',
    emailBroker: 'Email broker',
    contraente: 'Contraente',
    telefonoContraente: 'Telefono contraente',
    emailContraente: 'Email contraente',
    assicurato: 'Assicurato',
    telefonoAssicurato: 'Telefono assicurato',
    emailAssicurato: 'Email assicurato',
    amministratore: 'Amministratore',
    telefonoAmministratore: 'Telefono amministratore',
    emailAmministratore: 'Email amministratore',
    danneggiato: 'Danneggiato',
    telefonoDanneggiato: 'Telefono danneggiato',
    emailDanneggiato: 'Email danneggiato',
    codiceFiscaleDanneggiato: 'Codice fiscale danneggiato',
    partitaIVADanneggiato: 'Partita IVA danneggiato',
    ibanDanneggiato: 'IBAN danneggiato',
    gruppo: 'Gruppo',
    compagnia: 'Compagnia',
    garanzia: 'Garanzia',
    ramo: 'Ramo',
    numeroPolizza: 'Numero polizza',
    tipoPolizza: 'Tipo polizza',
    prodotto: 'Prodotto',
    indirizzoUbicazione: 'Indirizzo ubicazione rischio',
    cittaUbicazione: 'Città ubicazione rischio',
    capUbicazione: 'CAP ubicazione rischio',
    provinciaUbicazione: 'Provincia ubicazione rischio',
    nazioneUbicazione: 'Nazione ubicazione rischio',
    noteEstrattoDenuncia: 'Note estratto denuncia',
    giustificativiDenuncia: 'Giustificativi denuncia',
    riservaDenuncia: 'Riserva denuncia',
    richiestaDenuncia: 'Richiesta denuncia',
    esitoPerizia: 'Esito perizia',
    importoLiquidato: 'Importo liquidato',
    dannoAccertato: 'Danno accertato',
    complessita: 'Complessità',
    checkRegolaritaAmministrativa: 'Regolarità amministrativa (check)',
    checkVincoli: 'Vincoli (check)',
    riapertura: 'Riapertura (check)',
    triage: 'Triage (check)',
    prontaDefinizione: 'Pronta definizione (check)',
    noResidui: 'No residui (check)',
    danniIndiretti: 'Danni indiretti (check)',
    videoperizia: 'Videoperizia (check)',
    documentale: 'Documentale (check)',
    periziaSemplificata: 'Perizia semplificata (check)',
    piuGaranzieInteressate: 'Più garanzie interessate (check)',
    rfsFattibile: 'RFS fattibile contrattualmente (check)',
    richiestaRiparazione: 'Richiesta riparazione (check)',
    sollgiust: 'Sollecito giustificativi (check)',
    sollatto: 'Sollecito atto (check)',
    tipoServizio: 'Tipo servizio',
    dataPagamentoPremio: 'Data pagamento premio',
    checkMantenimentoPolizza: 'Mantenimento polizza (check)',
    notaMantenimentoPolizza: 'Nota mantenimento polizza',
    assegnaCat: 'Assegna CAT',
    noteCat: 'Note CAT',
    assegnaPerito: 'Assegna perito',
    assegnaCR: 'Assegna CR',
    dataAssegnCR: 'Data assegnazione CR',
    dataContrCR: 'Data controllo CR',
    assegnaCQ1: 'Assegna CQ1',
    dataAssegnCQ1: 'Data assegnazione CQ1',
    dataContrCQ1: 'Data controllo CQ1',
    ddlCambiaStato: 'Cambia stato',
    dataAlert: 'Data alert',
    ddlAzione: 'Azione',
    ddlAChi: 'A chi',
    ddlCosa: 'Cosa',
    noteFin: 'Note finali',
  };

  const CHECKBOX_FIELDS = new Set([
    'checkRegolaritaAmministrativa', 'checkVincoli', 'riapertura', 'triage',
    'prontaDefinizione', 'noResidui', 'danniIndiretti', 'videoperizia',
    'documentale', 'periziaSemplificata', 'piuGaranzieInteressate',
    'rfsFattibile', 'richiestaRiparazione', 'sollgiust', 'sollatto',
    'checkMantenimentoPolizza',
  ]);

  const RICHTEXT_FIELDS = new Set(['noteEstrattoDenuncia', 'noteCat', 'noteFin']);

  function isDateField(key) {
    return JFISH_FIELDS[key] ? JFISH_FIELDS[key].startsWith('mask_') : false;
  }

  /** Elenco ordinato usato dal popup per popolare i menu di mappatura. */
  function getFieldCatalog() {
    return Object.keys(JFISH_FIELDS).map((key) => ({
      key,
      label: JFISH_FIELD_LABELS[key] || key,
      type: CHECKBOX_FIELDS.has(key) ? 'checkbox' : (isDateField(key) ? 'date' : (RICHTEXT_FIELDS.has(key) ? 'richtext' : 'text')),
    }));
  }

  /**
   * Rileva l'ID del sinistro dalla pagina JFish (tab attiva).
   * Stessa strategia a cascata del vecchio content.js.
   */
  function detectSinistroId() {
    const activeMainTab = document.querySelector('[id*="TabSituazioneSinistri"] .e-toolbar-item.e-active[data-id]');
    if (activeMainTab) {
      const id = activeMainTab.getAttribute('data-id');
      if (id && /^\d+$/.test(id)) return id;
    }
    const anyActiveTab = document.querySelector('.e-toolbar-item.e-active[data-id]');
    if (anyActiveTab) {
      const id = anyActiveTab.getAttribute('data-id');
      if (id && /^\d+$/.test(id)) return id;
    }
    const activeTabText = document.querySelector('.e-toolbar-item.e-active .e-tab-text');
    if (activeTabText) {
      const match = activeTabText.textContent.match(/sinistro\s+(?:num\.)?\s*(\d+)/i);
      if (match) return match[1];
    }
    const tabElements = document.querySelectorAll('[id*="tabDettaglio"]');
    for (const el of tabElements) {
      if (el.offsetParent !== null || el.closest('.e-active')) {
        const match = el.id.match(/tabDettaglio(\d+)/);
        if (match) return match[1];
      }
    }
    return null;
  }

  function buildFieldSelector(jfishFieldName, sinistroId) {
    const fullId = `${jfishFieldName}${sinistroId}`;
    return `#${CSS.escape(fullId)}, [name="${fullId}"], #${CSS.escape(fullId)}_hidden`;
  }

  function triggerSyncfusionEvents(element, componentType) {
    element.dispatchEvent(new Event('input', { bubbles: true }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
    element.dispatchEvent(new FocusEvent('focus', { bubbles: true }));
    element.dispatchEvent(new FocusEvent('blur', { bubbles: true }));
    if (componentType === 'select') {
      const wrapper = element.closest('.e-ddl') || element.closest('.e-control-wrapper');
      if (wrapper) wrapper.dispatchEvent(new Event('change', { bubbles: true }));
    }
  }

  function formatDateItalian(value) {
    if (!value) return '';
    let d;
    if (value instanceof Date) {
      d = value;
    } else if (typeof value === 'string') {
      // Prova prima ISO/parsabile nativamente, poi gg/mm/aaaa
      d = new Date(value);
      if (isNaN(d.getTime())) {
        const m = value.match(/^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})$/);
        if (m) d = new Date(Number(m[3].length === 2 ? '20' + m[3] : m[3]), Number(m[2]) - 1, Number(m[1]));
      }
    }
    if (!d || isNaN(d.getTime())) return '';
    const day = String(d.getDate()).padStart(2, '0');
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const year = d.getFullYear();
    return `${day}/${month}/${year}`;
  }

  function formatAmountItalian(value) {
    if (value === null || value === undefined || value === '') return '';
    const num = typeof value === 'number' ? value : Number(String(value).replace(',', '.'));
    if (isNaN(num)) return String(value);
    return num.toFixed(2).replace('.', ',');
  }

  function toBoolean(value) {
    if (typeof value === 'boolean') return value;
    const s = String(value).trim().toLowerCase();
    return s === 'si' || s === 'sì' || s === 'true' || s === '1' || s === 'x' || s === 'yes';
  }

  function fillField(element, rawValue, fieldKey) {
    if (!element) return false;
    const tagName = element.tagName.toLowerCase();
    const isDisabled = element.disabled || element.readOnly || element.classList.contains('e-disabled');
    if (isDisabled) return false;

    try {
      if (element.type === 'checkbox' || CHECKBOX_FIELDS.has(fieldKey)) {
        const newChecked = toBoolean(rawValue);
        if (element.checked !== newChecked) {
          element.checked = newChecked;
          triggerSyncfusionEvents(element, 'checkbox');
        }
        return true;
      }

      if (tagName === 'input' || tagName === 'textarea') {
        const isDatePicker = isDateField(fieldKey) ||
          element.classList.contains('e-datepicker') ||
          element.classList.contains('e-daterangepicker') ||
          (element.id && element.id.startsWith('mask_'));

        let value;
        if (isDatePicker) {
          value = formatDateItalian(rawValue);
        } else if (fieldKey === 'importoLiquidato' || fieldKey === 'dannoAccertato' ||
                   fieldKey === 'riservaDenuncia' || fieldKey === 'richiestaDenuncia') {
          value = formatAmountItalian(rawValue);
        } else if (rawValue instanceof Date) {
          value = formatDateItalian(rawValue);
        } else {
          value = rawValue === null || rawValue === undefined ? '' : String(rawValue);
        }

        element.value = value;
        triggerSyncfusionEvents(element, 'input');
        return true;
      }

      if (tagName === 'select') {
        const options = element.querySelectorAll('option');
        let found = false;
        for (const option of options) {
          if (option.value === rawValue ||
              option.textContent.trim().toLowerCase() === String(rawValue).toLowerCase()) {
            element.value = option.value;
            found = true;
            break;
          }
        }
        if (found) triggerSyncfusionEvents(element, 'select');
        return found;
      }

      if (element.classList.contains('e-richtexteditor') || element.closest('.e-richtexteditor')) {
        const editArea = element.querySelector('.e-content') || element.querySelector('[contenteditable="true"]');
        if (editArea) {
          editArea.innerHTML = rawValue || '';
          triggerSyncfusionEvents(editArea, 'richtext');
          return true;
        }
      }

      element.textContent = rawValue === null || rawValue === undefined ? '' : String(rawValue);
      return true;
    } catch (err) {
      console.error('[PerX Lite] Errore compilazione campo', fieldKey, err);
      return false;
    }
  }

  /**
   * Compila un set di campi sulla pagina.
   * @param {Object} payload - { fields: { [fieldKey]: value } }
   * @returns {{sinistroId: string|null, results: Array<{key, ok, reason}>}}
   */
  function fillTextFields(payload) {
    const sinistroId = detectSinistroId();
    const results = [];

    if (!sinistroId) {
      return { sinistroId: null, results: [], error: 'ID sinistro non rilevato sulla pagina. Apri il dettaglio del sinistro prima di compilare.' };
    }

    for (const [fieldKey, value] of Object.entries(payload.fields || {})) {
      const jfishFieldName = JFISH_FIELDS[fieldKey];
      if (!jfishFieldName) {
        results.push({ key: fieldKey, ok: false, reason: 'Campo sconosciuto' });
        continue;
      }
      const selector = buildFieldSelector(jfishFieldName, sinistroId);
      const element = document.querySelector(selector);
      if (!element) {
        results.push({ key: fieldKey, ok: false, reason: 'Campo non trovato sulla pagina' });
        continue;
      }
      const ok = fillField(element, value, fieldKey);
      results.push({ key: fieldKey, ok, reason: ok ? null : 'Compilazione fallita (campo disabilitato o valore non valido)' });
    }

    return { sinistroId, results };
  }

  /** Individua un'etichetta leggibile vicina a un input[type=file] per aiutare l'utente a riconoscerlo. */
  function labelForFileInput(input) {
    if (input.id) {
      const explicit = document.querySelector(`label[for="${CSS.escape(input.id)}"]`);
      if (explicit && explicit.textContent.trim()) return explicit.textContent.trim();
    }
    const wrapper = input.closest('.e-upload, .e-file-select-wrap, td, div');
    if (wrapper) {
      const text = wrapper.textContent.replace(/\s+/g, ' ').trim();
      if (text) return text.slice(0, 80);
    }
    return input.name || input.id || '(input file senza etichetta)';
  }

  /** Elenca tutti gli input file visibili sulla pagina, per farli scegliere all'utente nel popup. */
  function scanFileInputs() {
    const inputs = Array.from(document.querySelectorAll('input[type="file"]'));
    return inputs.map((input, index) => ({
      index,
      label: labelForFileInput(input),
      visible: input.offsetParent !== null,
    }));
  }

  function base64ToFile(base64, mimeType, filename) {
    const byteChars = atob(base64);
    const byteNumbers = new Array(byteChars.length);
    for (let i = 0; i < byteChars.length; i++) byteNumbers[i] = byteChars.charCodeAt(i);
    const byteArray = new Uint8Array(byteNumbers);
    return new File([byteArray], filename, { type: mimeType });
  }

  /**
   * Carica la foto nell'input file scelto dall'utente.
   * @param {Object} payload - { index, base64, mimeType, filename }
   */
  function fillFileInputAtIndex(payload) {
    const inputs = Array.from(document.querySelectorAll('input[type="file"]'));
    const input = inputs[payload.index];
    if (!input) return { ok: false, reason: 'Campo file non più presente sulla pagina' };

    try {
      const file = base64ToFile(payload.base64, payload.mimeType, payload.filename);
      const dataTransfer = new DataTransfer();
      dataTransfer.items.add(file);
      input.files = dataTransfer.files;

      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
      // Alcuni uploader (drag&drop, Syncfusion) ascoltano 'drop' invece di 'change'.
      const dropEvent = new Event('drop', { bubbles: true, cancelable: true });
      Object.defineProperty(dropEvent, 'dataTransfer', { value: dataTransfer });
      input.dispatchEvent(dropEvent);

      return { ok: true };
    } catch (err) {
      console.error('[PerX Lite] Errore caricamento foto', err);
      return { ok: false, reason: String(err) };
    }
  }

  window.__perxLite = {
    getFieldCatalog,
    fillTextFields,
    scanFileInputs,
    fillFileInputAtIndex,
  };
})();
