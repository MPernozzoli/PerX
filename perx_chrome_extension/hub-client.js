/**
 * PerX JFish Sync - Hub API Client
 * Client per comunicazione con PerXHub via HTTP
 */

export class HubClient {
  constructor(baseUrl) {
    this.baseUrl = baseUrl;
    this.userEmail = null;
    this.timeout = 30000; // 30 secondi
  }
  
  /**
   * Imposta l'email utente per le richieste
   * @param {string} email 
   */
  setUserEmail(email) {
    this.userEmail = email;
  }
  
  /**
   * Effettua una richiesta HTTP all'Hub
   * @param {string} endpoint 
   * @param {object} options 
   * @returns {Promise<any>}
   */
  async request(endpoint, options = {}) {
    const url = `${this.baseUrl}${endpoint}`;
    
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeout);
    
    const headers = {
      'Content-Type': 'application/json',
      ...options.headers
    };
    
    // Aggiungi email utente come header se disponibile
    if (this.userEmail) {
      headers['X-User-Email'] = this.userEmail;
    }
    
    try {
      const response = await fetch(url, {
        ...options,
        headers,
        signal: controller.signal
      });
      
      clearTimeout(timeoutId);
      
      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`HTTP ${response.status}: ${errorText}`);
      }
      
      // Alcuni endpoint non restituiscono JSON
      const contentType = response.headers.get('content-type');
      if (contentType && contentType.includes('application/json')) {
        return await response.json();
      }
      
      return await response.text();
      
    } catch (error) {
      clearTimeout(timeoutId);
      
      if (error.name === 'AbortError') {
        throw new Error('Timeout: Hub non raggiungibile');
      }
      
      throw error;
    }
  }
  
  // === Health & Status ===
  
  /**
   * Verifica stato dell'Hub
   * @returns {Promise<{status: string, version: string, uptime: number}>}
   */
  async health() {
    return this.request('/health');
  }
  
  /**
   * Invia heartbeat per segnalare presenza client
   */
  async heartbeat() {
    if (!this.userEmail) {
      throw new Error('Email utente non impostata');
    }
    
    return this.request('/heartbeat', {
      method: 'POST',
      body: JSON.stringify({
        user_id: this.userEmail,
        client_info: 'PerX Chrome Extension'
      })
    });
  }
  
  // === Sinistri ===
  
  /**
   * Ottiene lista sinistri per l'utente corrente
   * @param {string} userEmail 
   * @returns {Promise<Array>}
   */
  async getSinistri(userEmail) {
    const email = userEmail || this.userEmail;
    if (!email) {
      throw new Error('Email utente non specificata');
    }
    
    return this.request(`/sinistri?user=${encodeURIComponent(email)}`);
  }
  
  /**
   * Ottiene dettaglio singolo sinistro
   * @param {string} ref - Riferimento sinistro
   * @returns {Promise<object>}
   */
  async getSinistro(ref) {
    if (!ref) {
      throw new Error('Riferimento sinistro richiesto');
    }
    
    // Usa l'endpoint JFish per ottenere dati sinistro con riferimento JFish
    return this.request(`/jfish/sinistro/${encodeURIComponent(ref)}`);
  }
  
  /**
   * Aggiorna un sinistro
   * @param {string} ref - Riferimento sinistro
   * @param {object} data - Dati da aggiornare
   * @returns {Promise<object>}
   */
  async updateSinistro(ref, data) {
    if (!ref) {
      throw new Error('Riferimento sinistro richiesto');
    }
    
    return this.request(`/sinistri/${encodeURIComponent(ref)}`, {
      method: 'PUT',
      body: JSON.stringify(data)
    });
  }
  
  /**
   * Aggiorna un singolo campo del sinistro
   * @param {string} ref - Riferimento sinistro
   * @param {string} field - Nome campo
   * @param {any} value - Nuovo valore
   * @returns {Promise<object>}
   */
  async updateSinistroField(ref, field, value) {
    // Usa l'endpoint JFish per aggiornare singoli campi
    return this.jfishUpdateSinistro(ref, [{ field, value: String(value ?? '') }]);
  }
  
  /**
   * Cambia stato di un sinistro
   * @param {string} ref - Riferimento sinistro
   * @param {string} newState - Nuovo stato (descrizione PerX)
   * @returns {Promise<object>}
   */
  async changeStato(ref, newState) {
    return this.request(`/sinistri/${encodeURIComponent(ref)}/stato`, {
      method: 'POST',
      body: JSON.stringify({ stato: newState })
    });
  }
  
  // === Diario ===
  
  /**
   * Ottiene entry del diario per un sinistro
   * @param {string} ref - Riferimento sinistro
   * @returns {Promise<Array>}
   */
  async getDiario(ref) {
    if (!ref) {
      throw new Error('Riferimento sinistro richiesto');
    }
    
    return this.request(`/sinistri/${encodeURIComponent(ref)}/diario`);
  }
  
  /**
   * Aggiunge una entry al diario
   * @param {string} ref - Riferimento sinistro
   * @param {object} entry - Entry da aggiungere
   * @returns {Promise<object>}
   */
  async addDiarioEntry(ref, entry) {
    if (!ref) {
      throw new Error('Riferimento sinistro richiesto');
    }
    
    return this.request(`/sinistri/${encodeURIComponent(ref)}/diario`, {
      method: 'POST',
      body: JSON.stringify(entry)
    });
  }
  
  /**
   * Aggiorna una entry del diario
   * @param {string} ref - Riferimento sinistro
   * @param {string} entryId - ID entry
   * @param {object} data - Dati da aggiornare
   * @returns {Promise<object>}
   */
  async updateDiarioEntry(ref, entryId, data) {
    return this.request(`/sinistri/${encodeURIComponent(ref)}/diario/${encodeURIComponent(entryId)}`, {
      method: 'PUT',
      body: JSON.stringify(data)
    });
  }
  
  // === Perizia ===
  
  /**
   * Ottiene dati perizia per un sinistro
   * @param {string} ref - Riferimento sinistro
   * @returns {Promise<object>}
   */
  async getPerizia(ref) {
    const sinistro = await this.getSinistro(ref);
    return sinistro.perizia || null;
  }
  
  /**
   * Aggiorna dati perizia
   * @param {string} ref - Riferimento sinistro
   * @param {object} periziaData - Dati perizia
   * @returns {Promise<object>}
   */
  async updatePerizia(ref, periziaData) {
    return this.updateSinistro(ref, { perizia: periziaData });
  }
  
  // === JFish Sync ===
  
  /**
   * Confronta dati JFish con PerX e restituisce differenze
   * @param {object} jfishData - Dati estratti da JFish
   * @returns {Promise<{riferimento: string, sinistroExists: boolean, differences: Array, message: string}>}
   */
  async jfishCompare(jfishData) {
    if (!jfishData || !jfishData.riferimento) {
      throw new Error('Dati JFish non validi');
    }
    
    return this.request('/jfish/compare', {
      method: 'POST',
      body: JSON.stringify(jfishData)
    });
  }
  
  /**
   * Recupera dati sinistro da PerX per confronto con JFish
   * @param {string} ref - Riferimento sinistro (ID JFish)
   * @returns {Promise<object|null>}
   */
  async jfishGetSinistro(ref) {
    if (!ref) {
      throw new Error('Riferimento sinistro richiesto');
    }
    
    try {
      return await this.request(`/jfish/sinistro/${encodeURIComponent(ref)}`);
    } catch (error) {
      // 404 = sinistro non trovato
      if (error.message.includes('404')) {
        return null;
      }
      throw error;
    }
  }
  
  /**
   * Aggiorna sinistro PerX con dati da JFish
   * @param {string} ref - Riferimento sinistro
   * @param {Array<{field: string, value: string}>} fields - Campi da aggiornare
   * @returns {Promise<{success: boolean, updatedFields: Array, failedFields: Array, message: string}>}
   */
  async jfishUpdateSinistro(ref, fields) {
    if (!ref) {
      throw new Error('Riferimento sinistro richiesto');
    }
    
    return this.request(`/jfish/sinistro/${encodeURIComponent(ref)}`, {
      method: 'PUT',
      body: JSON.stringify({ fields })
    });
  }
  
  /**
   * Importa tutti i dati da JFish a PerX
   * @param {string} ref - Riferimento sinistro
   * @param {object} jfishData - Tutti i dati JFish
   * @returns {Promise<{success: boolean, updatedFields: Array, message: string}>}
   */
  async jfishImportAll(ref, jfishData) {
    if (!ref || !jfishData) {
      throw new Error('Riferimento e dati JFish richiesti');
    }
    
    return this.request(`/jfish/sinistro/${encodeURIComponent(ref)}/import`, {
      method: 'POST',
      body: JSON.stringify(jfishData)
    });
  }
  
  /**
   * Recupera diario da PerX per confronto con JFish
   * @param {string} ref - Riferimento sinistro
   * @returns {Promise<Array>}
   */
  async jfishGetDiario(ref) {
    if (!ref) {
      throw new Error('Riferimento sinistro richiesto');
    }
    
    return this.request(`/jfish/sinistro/${encodeURIComponent(ref)}/diario`);
  }
  
  /**
   * Sincronizza diario da JFish a PerX
   * @param {string} ref - Riferimento sinistro
   * @param {Array<{data: string, tipo: string, nota: string}>} entries - Entry da sincronizzare
   * @returns {Promise<{success: boolean, addedEntries: number, skippedEntries: number, message: string}>}
   */
  async jfishSyncDiario(ref, entries) {
    if (!ref) {
      throw new Error('Riferimento sinistro richiesto');
    }
    
    return this.request(`/jfish/sinistro/${encodeURIComponent(ref)}/diario/sync`, {
      method: 'POST',
      body: JSON.stringify({ entries })
    });
  }
}

/**
 * Mapping stati JFish ↔ PerX
 * Da sincronizzare con StatoManager.swift jfishAlias
 */
export const StateMapper = {
  // JFish → PerX
  jfishToPerx: {
    // Da compilare con i valori reali di JFish
    'DA SCARICARE': 'Da scaricare',
    'IN LAVORAZIONE': 'In gestione',
    'CHIUSO': 'Chiusa',
    'REVOCATO': 'Revocata',
    'ANNULLATO': 'Annullata',
    // ... altri stati
  },
  
  // PerX → JFish
  perxToJfish: {
    'Da scaricare': 'DA SCARICARE',
    'In gestione': 'IN LAVORAZIONE',
    'In gestione (documentale)': 'IN LAVORAZIONE',
    'In gestione (videoperizia)': 'IN LAVORAZIONE',
    'Chiusa': 'CHIUSO',
    'Revocata': 'REVOCATO',
    'Annullata': 'ANNULLATO',
    // ... altri stati
  },
  
  /**
   * Converte stato JFish in stato PerX
   * @param {string} jfishState 
   * @returns {string|null}
   */
  toPerx(jfishState) {
    if (!jfishState) return null;
    const normalized = jfishState.trim().toUpperCase();
    return this.jfishToPerx[normalized] || null;
  },
  
  /**
   * Converte stato PerX in stato JFish
   * @param {string} perxState 
   * @returns {string|null}
   */
  toJfish(perxState) {
    if (!perxState) return null;
    return this.perxToJfish[perxState] || null;
  },
  
  /**
   * Verifica se due stati sono equivalenti
   * @param {string} jfishState 
   * @param {string} perxState 
   * @returns {boolean}
   */
  areEquivalent(jfishState, perxState) {
    const jfishNorm = jfishState?.trim().toUpperCase();
    const perxNorm = perxState?.trim();
    
    // Stesso stato
    if (jfishNorm === perxNorm?.toUpperCase()) return true;
    
    // Mappato
    const mappedPerx = this.toPerx(jfishState);
    return mappedPerx === perxState;
  }
};

/**
 * Utility per confronto date
 */
export const DateUtils = {
  /**
   * Parsa una data in formato italiano (dd/mm/yyyy)
   * @param {string} dateStr 
   * @returns {Date|null}
   */
  parseItalian(dateStr) {
    if (!dateStr) return null;
    
    // Prova formato dd/mm/yyyy
    const parts = dateStr.split('/');
    if (parts.length === 3) {
      const [day, month, year] = parts.map(p => parseInt(p, 10));
      return new Date(year, month - 1, day);
    }
    
    // Prova ISO
    const isoDate = new Date(dateStr);
    if (!isNaN(isoDate.getTime())) {
      return isoDate;
    }
    
    return null;
  },
  
  /**
   * Formatta una data in italiano
   * @param {Date|string} date 
   * @returns {string}
   */
  formatItalian(date) {
    if (!date) return '';
    
    const d = date instanceof Date ? date : new Date(date);
    if (isNaN(d.getTime())) return '';
    
    const day = String(d.getDate()).padStart(2, '0');
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const year = d.getFullYear();
    
    return `${day}/${month}/${year}`;
  },
  
  /**
   * Confronta due date (ignora orario)
   * @param {Date|string} date1 
   * @param {Date|string} date2 
   * @returns {boolean}
   */
  areSameDay(date1, date2) {
    const d1 = date1 instanceof Date ? date1 : this.parseItalian(date1) || new Date(date1);
    const d2 = date2 instanceof Date ? date2 : this.parseItalian(date2) || new Date(date2);
    
    if (isNaN(d1.getTime()) || isNaN(d2.getTime())) return false;
    
    return d1.getFullYear() === d2.getFullYear() &&
           d1.getMonth() === d2.getMonth() &&
           d1.getDate() === d2.getDate();
  }
};
