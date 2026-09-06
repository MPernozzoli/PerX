/**
 * PerX Lite - popup.js
 *
 * Tutta la logica gira qui (nessun background service worker): al click
 * sull'icona il popup si apre, legge l'Excel scelto dall'utente con SheetJS
 * (vendor/xlsx.full.min.js, locale, nessuna chiamata di rete), propone una
 * mappatura colonna-etichetta -> campo pagina, e su richiesta inietta
 * filler.js nella tab attiva per compilare i campi e allegare la foto.
 */

const MAPPING_STORAGE_KEY = 'perxLite.fieldMappings';
const IGNORE_VALUE = '__ignore__';

/** @type {{sheetName: string, items: Array<{row:number, col:number, label:string, value:any, normalizedLabel:string}>}} */
let currentExtraction = null;
let workbook = null;
let fieldCatalog = [];
let savedMappings = {};
let photoPayload = null; // { filename, mimeType, base64 }
let activeTabId = null;

const els = {
  excelInput: document.getElementById('excelInput'),
  excelStatus: document.getElementById('excelStatus'),
  sheetSection: document.getElementById('sheetSection'),
  sheetSelect: document.getElementById('sheetSelect'),
  photoInput: document.getElementById('photoInput'),
  photoStatus: document.getElementById('photoStatus'),
  mappingSection: document.getElementById('mappingSection'),
  mappingList: document.getElementById('mappingList'),
  fillButton: document.getElementById('fillButton'),
  fillStatus: document.getElementById('fillStatus'),
  fileInputChoice: document.getElementById('fileInputChoice'),
  fileInputList: document.getElementById('fileInputList'),
};

init();

async function init() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  activeTabId = tab?.id ?? null;

  const stored = await chrome.storage.local.get(MAPPING_STORAGE_KEY);
  savedMappings = stored[MAPPING_STORAGE_KEY] || {};

  try {
    fieldCatalog = await ensureFillerAndCall('getFieldCatalog');
  } catch (err) {
    fieldCatalog = [];
    setStatus(els.excelStatus, 'Impossibile leggere la pagina attiva (apri il dettaglio sinistro su JFish). ' + describeError(err), 'err');
  }

  els.excelInput.addEventListener('change', onExcelSelected);
  els.sheetSelect.addEventListener('change', onSheetChanged);
  els.photoInput.addEventListener('change', onPhotoSelected);
  els.fillButton.addEventListener('click', onFillClicked);
}

/** Inietta filler.js nella tab attiva (idempotente) e invoca una sua funzione. */
async function ensureFillerAndCall(fnName, arg) {
  if (!activeTabId) throw new Error('Nessuna tab attiva');

  await chrome.scripting.executeScript({
    target: { tabId: activeTabId },
    files: ['filler.js'],
  });

  const [{ result }] = await chrome.scripting.executeScript({
    target: { tabId: activeTabId },
    func: (name, a) => window.__perxLite[name](a),
    args: [fnName, arg],
  });
  return result;
}

function describeError(err) {
  return err && err.message ? err.message : String(err);
}

function setStatus(el, text, kind) {
  el.textContent = text;
  el.className = 'status ' + (kind || 'muted');
}

// ---------------------------------------------------------------------------
// Excel
// ---------------------------------------------------------------------------

async function onExcelSelected(e) {
  const file = e.target.files[0];
  if (!file) return;

  setStatus(els.excelStatus, 'Lettura in corso...', 'muted');
  try {
    const buffer = await file.arrayBuffer();
    workbook = XLSX.read(buffer, { type: 'array', cellDates: true });

    els.sheetSelect.innerHTML = '';
    workbook.SheetNames.forEach((name) => {
      const opt = document.createElement('option');
      opt.value = name;
      opt.textContent = name;
      els.sheetSelect.appendChild(opt);
    });
    els.sheetSection.hidden = false;

    setStatus(els.excelStatus, `Caricato: ${file.name} (${workbook.SheetNames.length} fogli)`, 'ok');
    extractAndRender(workbook.SheetNames[0]);
  } catch (err) {
    workbook = null;
    setStatus(els.excelStatus, 'File non leggibile: ' + describeError(err), 'err');
  }
}

function onSheetChanged() {
  extractAndRender(els.sheetSelect.value);
}

function extractAndRender(sheetName) {
  const sheet = workbook.Sheets[sheetName];
  const items = extractLabelValuePairs(sheet, sheetName);
  currentExtraction = { sheetName, items };
  renderMappingList();
  updateFillButtonState();
}

/**
 * Estrae coppie (etichetta, valore) da un foglio.
 *
 * Regola: ogni cella numerica/data/booleana è un valore candidato "sicuro"
 * (mai ambiguo con un'etichetta). Una cella testuale è un valore candidato
 * solo se la cella a sinistra (o sopra) termina con ":" — per non spezzare
 * titoli/prosa in coppie inventate. L'etichetta è sempre la cella non vuota
 * più vicina a sinistra, poi sopra; se non c'è, si usa la coordinata.
 */
function extractLabelValuePairs(sheet, sheetName) {
  const ref = sheet['!ref'];
  if (!ref) return [];
  const range = XLSX.utils.decode_range(ref);
  const items = [];

  const cellAt = (r, c) => sheet[XLSX.utils.encode_cell({ r, c })];
  const textOf = (cell) => (cell && typeof cell.v === 'string' ? cell.v.trim() : null);

  for (let r = range.s.r; r <= range.e.r; r++) {
    for (let c = range.s.c; c <= range.e.c; c++) {
      const cell = cellAt(r, c);
      if (!cell || cell.v === undefined || cell.v === null || cell.v === '') continue;

      const isTypedValue = cell.t === 'n' || cell.t === 'd' || cell.t === 'b';
      let isColonQualifiedText = false;
      if (!isTypedValue && cell.t === 's') {
        const left = textOf(cellAt(r, c - 1));
        const above = textOf(cellAt(r - 1, c));
        isColonQualifiedText = /:\s*$/.test(left || '') || /:\s*$/.test(above || '');
      }
      if (!isTypedValue && !isColonQualifiedText) continue;

      const leftLabel = textOf(cellAt(r, c - 1));
      const aboveLabel = textOf(cellAt(r - 1, c));
      const rawLabel = leftLabel || aboveLabel;
      const cleanLabel = rawLabel ? rawLabel.replace(/:\s*$/, '').trim() : null;
      const label = cleanLabel || `${sheetName} - riga ${r + 1}, colonna ${XLSX.utils.encode_col(c)}`;

      items.push({
        row: r,
        col: c,
        label,
        value: cell.v,
        displayValue: cell.w || String(cell.v),
        normalizedLabel: normalizeLabel(label),
      });
    }
  }

  return items;
}

function normalizeLabel(label) {
  return label
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '') // rimuove accenti
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

// ---------------------------------------------------------------------------
// Mappatura
// ---------------------------------------------------------------------------

function renderMappingList() {
  els.mappingList.innerHTML = '';
  els.mappingSection.hidden = !currentExtraction || currentExtraction.items.length === 0;

  if (!currentExtraction) return;

  currentExtraction.items.forEach((item, idx) => {
    const row = document.createElement('div');
    row.className = 'mapping-row';

    const info = document.createElement('div');
    info.className = 'cell-info';
    const labelEl = document.createElement('div');
    labelEl.className = 'cell-label';
    labelEl.textContent = item.label;
    labelEl.title = item.label;
    const valueEl = document.createElement('div');
    valueEl.className = 'cell-value';
    valueEl.textContent = item.displayValue;
    valueEl.title = item.displayValue;
    info.appendChild(labelEl);
    info.appendChild(valueEl);

    const select = document.createElement('select');
    select.dataset.index = String(idx);

    const ignoreOpt = document.createElement('option');
    ignoreOpt.value = IGNORE_VALUE;
    ignoreOpt.textContent = '-- non compilare --';
    select.appendChild(ignoreOpt);

    fieldCatalog.forEach((f) => {
      const opt = document.createElement('option');
      opt.value = f.key;
      opt.textContent = f.label;
      select.appendChild(opt);
    });

    const saved = savedMappings[item.normalizedLabel];
    if (saved && fieldCatalog.some((f) => f.key === saved)) {
      select.value = saved;
    }

    select.addEventListener('change', () => onMappingChanged(item, select.value));

    row.appendChild(info);
    row.appendChild(select);
    els.mappingList.appendChild(row);
  });
}

async function onMappingChanged(item, fieldKey) {
  if (fieldKey === IGNORE_VALUE) {
    delete savedMappings[item.normalizedLabel];
  } else {
    savedMappings[item.normalizedLabel] = fieldKey;
  }
  await chrome.storage.local.set({ [MAPPING_STORAGE_KEY]: savedMappings });
}

// ---------------------------------------------------------------------------
// Foto
// ---------------------------------------------------------------------------

async function onPhotoSelected(e) {
  const file = e.target.files[0];
  if (!file) {
    photoPayload = null;
    setStatus(els.photoStatus, 'Nessuna foto selezionata', 'muted');
    return;
  }

  const base64 = await fileToBase64(file);
  photoPayload = { filename: file.name, mimeType: file.type || 'image/jpeg', base64 };
  setStatus(els.photoStatus, `Selezionata: ${file.name}`, 'ok');
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const dataUrl = reader.result;
      const base64 = String(dataUrl).split(',')[1];
      resolve(base64);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

// ---------------------------------------------------------------------------
// Compilazione pagina
// ---------------------------------------------------------------------------

function updateFillButtonState() {
  els.fillButton.disabled = !currentExtraction || currentExtraction.items.length === 0;
}

async function onFillClicked() {
  els.fillButton.disabled = true;
  els.fileInputChoice.hidden = true;
  setStatus(els.fillStatus, 'Compilazione in corso...', 'muted');

  try {
    const fields = {};
    for (const [idx, select] of Array.from(els.mappingList.querySelectorAll('select')).entries()) {
      if (select.value === IGNORE_VALUE) continue;
      const item = currentExtraction.items[idx];
      fields[select.value] = item.value instanceof Date ? item.value.toISOString() : item.value;
    }

    if (Object.keys(fields).length === 0) {
      setStatus(els.fillStatus, 'Nessun campo mappato: scegli almeno una destinazione sopra.', 'err');
      els.fillButton.disabled = false;
      return;
    }

    const fillResult = await ensureFillerAndCall('fillTextFields', { fields });
    renderFillResult(fillResult);

    if (photoPayload) {
      await handlePhotoUpload();
    }
  } catch (err) {
    setStatus(els.fillStatus, 'Errore: ' + describeError(err), 'err');
  } finally {
    els.fillButton.disabled = false;
  }
}

function renderFillResult(fillResult) {
  if (fillResult.error) {
    setStatus(els.fillStatus, fillResult.error, 'err');
    return;
  }

  const ok = fillResult.results.filter((r) => r.ok).length;
  const total = fillResult.results.length;
  const failed = fillResult.results.filter((r) => !r.ok);

  let text = `Sinistro ${fillResult.sinistroId}: ${ok}/${total} campi compilati.`;
  if (failed.length) {
    text += ' Non riusciti: ' + failed.map((f) => `${f.key} (${f.reason})`).join(', ');
  }
  setStatus(els.fillStatus, text, failed.length ? 'err' : 'ok');
}

async function handlePhotoUpload() {
  const fileInputs = await ensureFillerAndCall('scanFileInputs');

  if (!fileInputs || fileInputs.length === 0) {
    appendFillStatusLine('Nessun campo per allegare la foto trovato in pagina.', 'err');
    return;
  }

  if (fileInputs.length === 1) {
    await uploadPhotoToIndex(fileInputs[0].index);
    return;
  }

  els.fileInputChoice.hidden = false;
  els.fileInputList.innerHTML = '';
  fileInputs.forEach((info) => {
    const row = document.createElement('div');
    row.className = 'file-input-option';
    const label = document.createElement('span');
    label.textContent = info.label + (info.visible ? '' : ' (nascosto)');
    const btn = document.createElement('button');
    btn.textContent = 'Usa questo';
    btn.addEventListener('click', async () => {
      await uploadPhotoToIndex(info.index);
      els.fileInputChoice.hidden = true;
    });
    row.appendChild(label);
    row.appendChild(btn);
    els.fileInputList.appendChild(row);
  });
}

async function uploadPhotoToIndex(index) {
  const result = await ensureFillerAndCall('fillFileInputAtIndex', {
    index,
    base64: photoPayload.base64,
    mimeType: photoPayload.mimeType,
    filename: photoPayload.filename,
  });
  appendFillStatusLine(
    result.ok ? 'Foto caricata.' : 'Foto non caricata: ' + result.reason,
    result.ok ? 'ok' : 'err'
  );
}

function appendFillStatusLine(text, kind) {
  const line = document.createElement('div');
  line.className = 'result-row';
  line.style.color = kind === 'err' ? 'var(--err)' : 'var(--ok)';
  line.textContent = text;
  els.fillStatus.appendChild(line);
}
