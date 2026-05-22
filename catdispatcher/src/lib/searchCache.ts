interface CachedSearchResult {
  results: any[];
  timestamp: number;
}

const CACHE_KEY_PREFIX = 'search_cache_';
const CACHE_DURATION = 24 * 60 * 60 * 1000; // 24 ore

export const searchCache = {
  get: (term: string): any[] | null => {
    try {
      const key = CACHE_KEY_PREFIX + term.toLowerCase().trim();
      const cached = localStorage.getItem(key);
      
      if (!cached) return null;
      
      const data: CachedSearchResult = JSON.parse(cached);
      const now = Date.now();
      
      // Check if cache is still valid
      if (now - data.timestamp > CACHE_DURATION) {
        localStorage.removeItem(key);
        return null;
      }
      
      return data.results;
    } catch (error) {
      console.warn('Error reading search cache:', error);
      return null;
    }
  },

  set: (term: string, results: any[]): void => {
    try {
      const key = CACHE_KEY_PREFIX + term.toLowerCase().trim();
      const data: CachedSearchResult = {
        results,
        timestamp: Date.now()
      };
      
      localStorage.setItem(key, JSON.stringify(data));
      
      // Clean old cache entries
      searchCache.cleanup();
    } catch (error) {
      console.warn('Error writing search cache:', error);
    }
  },

  cleanup: (): void => {
    try {
      const now = Date.now();
      const keysToRemove: string[] = [];
      
      // Find expired entries
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key?.startsWith(CACHE_KEY_PREFIX)) {
          const cached = localStorage.getItem(key);
          if (cached) {
            const data: CachedSearchResult = JSON.parse(cached);
            if (now - data.timestamp > CACHE_DURATION) {
              keysToRemove.push(key);
            }
          }
        }
      }
      
      // Remove expired entries
      keysToRemove.forEach(key => localStorage.removeItem(key));
    } catch (error) {
      console.warn('Error cleaning search cache:', error);
    }
  }
};
