import { supabase } from '@/integrations/supabase/client';
import { idbCache } from './indexedDBCache';

const GEOJSON_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 ore

/**
 * Loads GeoJSON data from multiple regional backup files.
 * Combines all available regional backups into a unified GeoJSON.
 * Cache IndexedDB 24h - riduce Storage list + download a 1 volta/giorno per utente.
 * @param selectedRegions - Optional array of region names to filter. If empty/null, loads all regions.
 */
export async function loadGeoJSON(selectedRegions?: string[] | null): Promise<any> {
  try {
    console.log('📍 Attempting to load regional GeoJSON files from Supabase Storage...');
    
    // Get list of all backup files
    const { data: files, error: listError } = await supabase.storage
      .from('geojson-backups')
      .list('', {
        sortBy: { column: 'created_at', order: 'desc' }
      });
    
    console.log('📦 Storage list response:', { 
      error: listError, 
      filesCount: files?.length || 0,
      files: files?.map(f => f.name) || []
    });
    
    if (listError) {
      console.error('❌ Storage list error:', listError);
      throw new Error(`Storage error: ${listError.message}`);
    }
    
    if (!files || files.length === 0) {
      console.log('⚠️ No backup files found, falling back to static file');
      throw new Error('No backups available');
    }
    
    // Group files by region and keep only the latest for each
    const regionMap = new Map<string, typeof files[0]>();
    
    for (const file of files) {
      // Extract region from filename (e.g., "geojson-lombardia-2025-11-26...")
      const match = file.name.match(/geojson-([a-z-]+)-\d{4}/i);
      if (!match) continue;
      
      const region = match[1];
      const existing = regionMap.get(region);
      
      // Keep the most recent file for each region
      if (!existing || new Date(file.created_at) > new Date(existing.created_at)) {
        regionMap.set(region, file);
      }
    }
    
    console.log(`📦 Found ${regionMap.size} regions available`);
    
    // Filter by selected regions if provided
    const regionsToLoad = selectedRegions && selectedRegions.length > 0
      ? Array.from(regionMap.entries()).filter(([region]) => 
          selectedRegions.some(selected => selected.toLowerCase() === region.toLowerCase())
        )
      : Array.from(regionMap.entries());
    
    console.log(`📥 Loading ${regionsToLoad.length} region(s)${selectedRegions ? ` (filtered from ${regionMap.size})` : ''}`);
    
    // Cache key basata su file metadata - invalida se backup cambiano
    const cacheKey = 'geojson_' + regionsToLoad.map(([r, f]) => `${r}:${f.name}:${f.created_at}`).sort().join('|');
    try {
      const cached = await idbCache.get(cacheKey, { maxAgeMs: GEOJSON_CACHE_TTL_MS });
      if (cached?.features?.length) {
        console.log(`✅ Loaded GeoJSON from cache (${cached.features.length} features)`);
        return cached;
      }
    } catch (cacheErr) {
      console.warn('GeoJSON cache read failed:', cacheErr);
    }
    
    // Download and merge selected regional files
    const allFeatures: any[] = [];
    let loadedRegions = 0;
    
    for (const [region, file] of regionsToLoad) {
      try {
        console.log(`⬇️ Loading ${region} (${file.name})...`);
        
        const { data: fileData, error: downloadError } = await supabase.storage
          .from('geojson-backups')
          .download(file.name);
        
        if (downloadError || !fileData) {
          console.warn(`Failed to download ${region}:`, downloadError);
          continue;
        }
        
        const content = await fileData.text();
        const geojson = JSON.parse(content);
        
        if (geojson.features && Array.isArray(geojson.features)) {
          allFeatures.push(...geojson.features);
          loadedRegions++;
          console.log(`✅ Loaded ${geojson.features.length} features from ${region}`);
        }
      } catch (error) {
        console.warn(`Error loading ${region}:`, error);
      }
    }
    
    if (allFeatures.length === 0) {
      throw new Error('No features loaded from regional backups');
    }
    
    // Create unified GeoJSON
    const unifiedGeoJson = {
      type: 'FeatureCollection',
      name: 'Italy Communes',
      crs: { type: 'name', properties: { name: 'urn:ogc:def:crs:OGC:1.3:CRS84' } },
      features: allFeatures
    };
    
    try {
      await idbCache.set(cacheKey, unifiedGeoJson);
    } catch (cacheErr) {
      console.warn('GeoJSON cache write failed:', cacheErr);
    }
    console.log(`✅ Successfully loaded ${allFeatures.length} total features from ${loadedRegions} regions`);
    return unifiedGeoJson;
    
  } catch (storageError) {
    console.warn('Regional backups load failed:', storageError);
  }
  
  // Fallback to static file
  console.log('📍 Loading GeoJSON from static file...');
  const response = await fetch('/data/lombardia.geojson');
  
  if (!response.ok) {
    throw new Error(`Failed to load GeoJSON: ${response.status}`);
  }
  
  const geojson = await response.json();
  console.log(`✅ Loaded GeoJSON from static file: ${geojson.features?.length || 0} features`);
  return geojson;
}
