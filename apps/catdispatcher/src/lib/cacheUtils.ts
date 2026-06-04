import { idbCache } from './indexedDBCache';

const CACHE_KEYS = {
  MAP_DATA: 'map_data_cache',
  MAP_VERSION: 'map_data_cache_version',
  GEOJSON_LS: 'geojson_data_cache',
  GEOJSON_IDB: 'lombardia_geojson_v1',
};

/**
 * Clear all caches (localStorage + IndexedDB)
 */
export async function clearAllCaches(): Promise<void> {
  console.log('🗑️ Clearing all caches...');
  
  // Clear localStorage
  Object.values(CACHE_KEYS).forEach((key) => {
    if (key !== CACHE_KEYS.GEOJSON_IDB) {
      localStorage.removeItem(key);
      console.log(`  ✓ Removed ${key} from localStorage`);
    }
  });
  
  // Clear IndexedDB
  try {
    await idbCache.clear();
    console.log('  ✓ Cleared IndexedDB cache');
  } catch (error) {
    console.warn('  ⚠️ Could not clear IndexedDB:', error);
  }
  
  console.log('✅ All caches cleared');
}

/**
 * Force reload of map data by clearing caches and reloading page
 */
export async function forceReloadMapData(): Promise<void> {
  await clearAllCaches();
  console.log('🔄 Reloading page...');
  window.location.reload();
}
