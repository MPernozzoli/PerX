/**
 * IndexedDB Cache Manager for large files like GeoJSON
 * More efficient than localStorage for large data (>5MB)
 */

const DB_NAME = 'cat_dispatcher_cache';
const DB_VERSION = 1;
const STORE_NAME = 'geo_cache';

export interface CacheEntry {
  key: string;
  data: any;
  timestamp: number;
  size: number;
}

class IndexedDBCache {
  private db: IDBDatabase | null = null;
  private initPromise: Promise<void> | null = null;

  constructor() {
    this.initPromise = this.init();
  }

  private async init(): Promise<void> {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onerror = () => {
        console.error('❌ IndexedDB error:', request.error);
        reject(request.error);
      };

      request.onsuccess = () => {
        this.db = request.result;
        console.log('✅ IndexedDB initialized');
        resolve();
      };

      request.onupgradeneeded = (event) => {
        const db = (event.target as IDBOpenDBRequest).result;
        
        // Create object store if it doesn't exist
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          const objectStore = db.createObjectStore(STORE_NAME, { keyPath: 'key' });
          objectStore.createIndex('timestamp', 'timestamp', { unique: false });
          console.log('🔨 IndexedDB object store created');
        }
      };
    });
  }

  private async ensureInit(): Promise<void> {
    if (this.initPromise) {
      await this.initPromise;
    }
  }

  async set(key: string, data: any): Promise<void> {
    await this.ensureInit();
    
    if (!this.db) {
      throw new Error('IndexedDB not initialized');
    }

    const entry: CacheEntry = {
      key,
      data,
      timestamp: Date.now(),
      size: JSON.stringify(data).length,
    };

    return new Promise((resolve, reject) => {
      const transaction = this.db!.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.put(entry);

      request.onsuccess = () => {
        console.log(`✅ Cached "${key}" in IndexedDB (${(entry.size / 1024 / 1024).toFixed(2)} MB)`);
        resolve();
      };

      request.onerror = () => {
        console.error(`❌ Error caching "${key}":`, request.error);
        reject(request.error);
      };
    });
  }

  async get(key: string, options?: { maxAgeMs?: number }): Promise<any | null> {
    await this.ensureInit();
    
    if (!this.db) {
      throw new Error('IndexedDB not initialized');
    }

    return new Promise((resolve, reject) => {
      const transaction = this.db!.transaction([STORE_NAME], 'readonly');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(key);

      request.onsuccess = () => {
        const entry = request.result as CacheEntry | undefined;
        if (entry) {
          const maxAgeMs = options?.maxAgeMs;
          if (maxAgeMs !== undefined && Date.now() - entry.timestamp > maxAgeMs) {
            console.log(`⚠️ "${key}" expired in IndexedDB (age ${Math.round((Date.now() - entry.timestamp) / 3600000)}h)`);
            resolve(null);
            return;
          }
          console.log(`✅ Retrieved "${key}" from IndexedDB (${(entry.size / 1024 / 1024).toFixed(2)} MB, cached ${new Date(entry.timestamp).toLocaleString('it-IT')})`);
          resolve(entry.data);
        } else {
          console.log(`⚠️ "${key}" not found in IndexedDB`);
          resolve(null);
        }
      };

      request.onerror = () => {
        console.error(`❌ Error retrieving "${key}":`, request.error);
        reject(request.error);
      };
    });
  }

  async delete(key: string): Promise<void> {
    await this.ensureInit();
    
    if (!this.db) {
      throw new Error('IndexedDB not initialized');
    }

    return new Promise((resolve, reject) => {
      const transaction = this.db!.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.delete(key);

      request.onsuccess = () => {
        console.log(`🗑️ Deleted "${key}" from IndexedDB`);
        resolve();
      };

      request.onerror = () => {
        console.error(`❌ Error deleting "${key}":`, request.error);
        reject(request.error);
      };
    });
  }

  async clear(): Promise<void> {
    await this.ensureInit();
    
    if (!this.db) {
      throw new Error('IndexedDB not initialized');
    }

    return new Promise((resolve, reject) => {
      const transaction = this.db!.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.clear();

      request.onsuccess = () => {
        console.log('🗑️ Cleared all IndexedDB cache');
        resolve();
      };

      request.onerror = () => {
        console.error('❌ Error clearing IndexedDB:', request.error);
        reject(request.error);
      };
    });
  }

  async getAllKeys(): Promise<string[]> {
    await this.ensureInit();
    
    if (!this.db) {
      throw new Error('IndexedDB not initialized');
    }

    return new Promise((resolve, reject) => {
      const transaction = this.db!.transaction([STORE_NAME], 'readonly');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.getAllKeys();

      request.onsuccess = () => {
        resolve(request.result as string[]);
      };

      request.onerror = () => {
        console.error('❌ Error getting keys:', request.error);
        reject(request.error);
      };
    });
  }

  async getStats(): Promise<{ totalSize: number; entries: number; keys: string[] }> {
    await this.ensureInit();
    
    if (!this.db) {
      throw new Error('IndexedDB not initialized');
    }

    return new Promise((resolve, reject) => {
      const transaction = this.db!.transaction([STORE_NAME], 'readonly');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.getAll();

      request.onsuccess = () => {
        const entries = request.result as CacheEntry[];
        const totalSize = entries.reduce((sum, entry) => sum + entry.size, 0);
        const keys = entries.map(entry => entry.key);
        
        resolve({
          totalSize,
          entries: entries.length,
          keys,
        });
      };

      request.onerror = () => {
        console.error('❌ Error getting stats:', request.error);
        reject(request.error);
      };
    });
  }
}

// Export singleton instance
export const idbCache = new IndexedDBCache();
