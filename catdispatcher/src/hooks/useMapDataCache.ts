import { useEffect, useState } from 'react';
import { loadGeoJSON } from '@/lib/geojsonLoader';
import { perxGet } from '@/lib/perxApi';

interface CatSuspension {
  cat_id: string;
  end_date: string;
  reason: string;
}

interface MapData {
  communes: any[];
  cats: any[];
  associations: any[];
  suspended_cat_ids?: string[];
  suspensions?: CatSuspension[];
  metadata: {
    timestamp?: string;
    total_communes: number;
    total_cats: number;
    total_associations: number;
    total_suspended?: number;
    cache_version: number;
  };
}

const CACHE_KEY = 'map_data_cache';
const CACHE_VERSION_KEY = 'map_data_cache_version';
const CACHE_TIMESTAMP_KEY = 'map_data_cache_timestamp';
const CACHE_FRESH_MS = 60 * 60 * 1000;

export const useMapDataCache = (enabled: boolean) => {
  const [data, setData] = useState<MapData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isBackgroundRefresh, setIsBackgroundRefresh] = useState(false);

  useEffect(() => {
    if (!enabled) {
      setIsLoading(false);
      setData(null);
      return;
    }

    const enrichWithGeometry = async (raw: MapData): Promise<MapData> => {
      const geoJsonData = await loadGeoJSON();
      const geometryMap = new Map<string, any>();

      for (const feature of geoJsonData?.features || []) {
        const comune = feature.properties.COMUNE || feature.properties.COMUNE_A || feature.properties.comune;
        const sigla = feature.properties.SIGLA || feature.properties.sigla || feature.properties.provincia;
        const quartiere = feature.properties.quartiere || feature.properties.QUARTIERE;
        if (!comune || !sigla) continue;
        const key = quartiere?.trim() ? `${comune}|${sigla}|${quartiere.trim()}` : `${comune}|${sigla}`;
        geometryMap.set(key, feature.geometry);
      }

      return {
        ...raw,
        communes: (raw.communes || []).map((commune: any) => {
          const quartiere = commune.quartiere?.trim();
          const key = quartiere ? `${commune.comune}|${commune.provincia}|${quartiere}` : `${commune.comune}|${commune.provincia}`;
          return { ...commune, geom: geometryMap.get(key) || commune.geom || null };
        }),
      };
    };

    const loadData = async () => {
      setIsLoading(true);
      try {
        const cachedData = localStorage.getItem(CACHE_KEY);
        const cachedTimestamp = Number(localStorage.getItem(CACHE_TIMESTAMP_KEY) || 0);
        const cacheIsFresh = cachedData && cachedTimestamp && Date.now() - cachedTimestamp < CACHE_FRESH_MS;

        if (cachedData) {
          const enriched = await enrichWithGeometry(JSON.parse(cachedData));
          setData(enriched);
          setIsLoading(false);
          if (cacheIsFresh) return;
          setIsBackgroundRefresh(true);
        }

        const freshData = await perxGet<MapData>('/cat-dispatcher/map-data');
        const enriched = await enrichWithGeometry(freshData);
        setData(enriched);
        localStorage.setItem(CACHE_KEY, JSON.stringify(freshData));
        localStorage.setItem(CACHE_VERSION_KEY, String(freshData.metadata?.cache_version || 1));
        localStorage.setItem(CACHE_TIMESTAMP_KEY, String(Date.now()));
      } catch (error) {
        console.error('[MAPCACHE] Error loading PerX map data:', error);
      } finally {
        setIsLoading(false);
        setIsBackgroundRefresh(false);
      }
    };

    loadData();
  }, [enabled]);

  return { data, isLoading, isBackgroundRefresh };
};
