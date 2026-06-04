import { useEffect, useRef, useState, useMemo } from 'react';
import maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import { supabase } from '@/integrations/supabase/client';
import type { PerXSession } from '@/lib/perxApi';

export interface MapDataProp {
  communes: any[];
  cats: any[];
  associations: any[];
  suspended_cat_ids?: string[];
  metadata?: { cache_version?: number };
}

interface MapProps {
  session: PerXSession | null;
  mapData: MapDataProp | null;
  mapDataLoading: boolean;
  onCommuneSelect?: (communeId: string) => void;
  highlightedCommune?: string | null;
  activeCatIds?: Set<string> | undefined;
  onVisibleCatsChange?: (catCounts: Map<string, number>) => void;
  centerOnCat?: string | null;
  centerOnCommuneId?: string | null;
  selectedCommuneId?: string | null;
  centerOnCoordinates?: { lat: number; lng: number } | null;
  onBoundsChange?: (bounds: { north: number; south: number; east: number; west: number }) => void;
  showAddressMarker?: boolean;
  onMarkerDragEnd?: (lat: number, lng: number) => void;
  limitToRadius?: { lat: number; lng: number; radiusKm: number } | null;
}

const Map = ({ session, mapData, mapDataLoading, onCommuneSelect, highlightedCommune, activeCatIds, onVisibleCatsChange, centerOnCat, centerOnCommuneId, selectedCommuneId, centerOnCoordinates, onBoundsChange, showAddressMarker = false, onMarkerDragEnd, limitToRadius = null }: MapProps) => {
  const mapContainer = useRef<HTMLDivElement>(null);
  const map = useRef<maplibregl.Map | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const [allFeatures, setAllFeatures] = useState<GeoJSON.Feature[]>([]);
  const addressMarkerRef = useRef<maplibregl.Marker | null>(null);

  // Stabilize activeCatIds using serialization for dependency comparison
  const activeCatIdsKey = useMemo(() => {
    if (!activeCatIds || activeCatIds.size === 0) return null;
    return Array.from(activeCatIds).sort().join(',');
  }, [activeCatIds]);

  const activeCatIdsArray = useMemo(() => {
    if (!activeCatIdsKey) return null;
    return activeCatIdsKey.split(',');
  }, [activeCatIdsKey]);

  // Log when mapData changes
  useEffect(() => {
    console.log('🗺️ Map component received data:', {
      hasData: !!mapData,
      communes: mapData?.communes?.length || 0,
      cats: mapData?.cats?.length || 0,
      associations: mapData?.associations?.length || 0,
      isLoading: mapDataLoading
    });
  }, [mapData, mapDataLoading]);

  // Extract and transform data from edge function response - MEMOIZED to prevent infinite loops
  const communes = useMemo(() => mapData?.communes?.filter((c: any) => !c.quartiere) || [], [mapData?.communes]);
  const allNeighborhoods = useMemo(() => mapData?.communes?.filter((c: any) => c.quartiere) || [], [mapData?.communes]);
  const allCats = useMemo(() => mapData?.cats || [], [mapData?.cats]);
  
  // Crea un set di comuni con use_quartieri = false (case-insensitive)
  // Per questi comuni, mostreremo la geometria del comune invece dei quartieri
  const communesWithQuartieriDisabled = useMemo(() => {
    const disabled = communes.filter((c: any) => c.use_quartieri === false);
    console.log('🔍 Comuni con use_quartieri=false:', disabled.map((c: any) => ({ nome: c.comune, use_quartieri: c.use_quartieri })));
    // Usa lowercase per confronto case-insensitive
    return new Set(disabled.map((c: any) => c.comune.toLowerCase()));
  }, [communes]);

  // Filtra i quartieri: escludi quelli di comuni con use_quartieri = false (case-insensitive)
  const neighborhoods = useMemo(() => {
    const filtered = allNeighborhoods.filter((n: any) => 
      !communesWithQuartieriDisabled.has(n.comune.toLowerCase())
    );
    const excluded = allNeighborhoods.length - filtered.length;
    if (excluded > 0) {
      console.log(`🔍 Quartieri esclusi: ${excluded} su ${allNeighborhoods.length}`);
    }
    return filtered;
  }, [allNeighborhoods, communesWithQuartieriDisabled]);
  
  // Transform associations into the format expected by the rest of the code
  const catAssociations = useMemo(() => {
    return (mapData?.associations || []).map((assoc: any) => {
      const cat = allCats.find((c: any) => c.id === assoc.cat_id);
      return {
        commune_id: assoc.commune_id,
        is_primary: assoc.is_primary,
        cats: cat ? {
          id: cat.id,
          name: cat.name,
          color_hex: cat.color_hex,
          active: cat.active
        } : null
      };
    }).filter((a: any) => a.cats !== null);
  }, [mapData?.associations, allCats]);

  // Get unique commune names that have neighborhoods (for filtering)
  // Escludi i comuni con use_quartieri = false - questi verranno mostrati come comuni normali
  const allCommunesWithNeighborhoods = useMemo(() => {
    return [...new Set(neighborhoods.map((n: any) => n.comune))];
  }, [neighborhoods]);

  // Initialize map
  useEffect(() => {
    if (!mapContainer.current || map.current) return;

    map.current = new maplibregl.Map({
      container: mapContainer.current,
      style: {
        version: 8,
        sources: {
          osm: {
            type: 'raster',
            tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
            tileSize: 256,
            attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          }
        },
        layers: [
          {
            id: 'osm',
            type: 'raster',
            source: 'osm',
            minzoom: 0,
            maxzoom: 19
          }
        ]
      },
      center: [12.5, 42.5], // Center on Italy
      zoom: 6,
      attributionControl: false
    });

    // Controls positioned to avoid header overlap
    map.current.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-right');
    map.current.addControl(new maplibregl.NavigationControl(), 'bottom-right');

    map.current.on('load', () => {
      setMapReady(true);
    });

    // Track bounds changes for search optimization
    const updateBounds = () => {
      if (map.current && onBoundsChange) {
        const bounds = map.current.getBounds();
        onBoundsChange({
          north: bounds.getNorth(),
          south: bounds.getSouth(),
          east: bounds.getEast(),
          west: bounds.getWest()
        });
      }
    };

    map.current.on('moveend', updateBounds);
    map.current.on('zoomend', updateBounds);

    return () => {
      map.current?.remove();
      map.current = null;
    };
  }, [onBoundsChange]);

  // Prepare all features and apply filters - Split by province for better performance
  useEffect(() => {
    if (!map.current || !mapReady || !communes || !catAssociations) return;

    // Filter out communes that have neighborhoods (we'll show neighborhoods instead)
    const communesWithoutNeighborhoods = communes.filter((commune) => 
      !allCommunesWithNeighborhoods?.includes(commune.comune)
    );

    console.log('Total communes:', communes.length);
    console.log('Communes WITH neighborhoods (excluded from this layer):', communes.length - communesWithoutNeighborhoods.length);
    console.log('Communes WITHOUT neighborhoods (showing in this layer):', communesWithoutNeighborhoods.length);

    const allCommuneFeatures = communesWithoutNeighborhoods.map((commune) => {
      const primaryCat = catAssociations.find(
        (assoc) => assoc.commune_id === commune.id && assoc.is_primary && assoc.cats.active
      );

      return {
        type: 'Feature' as const,
        geometry: commune.geom as any,
        properties: {
          id: commune.id,
          comune: commune.comune,
          provincia: commune.provincia,
          regione: commune.regione,
          cat_id: primaryCat?.cats.id || null,
          cat_color: primaryCat?.cats.color_hex || '#BBBBBB',
          cat_name: primaryCat?.cats.name || null
        }
      };
    });

    setAllFeatures(allCommuneFeatures);

    // Filter features based on active CAT IDs - if no filter, show all
    const filteredFeatures = !activeCatIdsArray ? allCommuneFeatures : allCommuneFeatures.filter((feature) => {
      const catId = feature.properties?.cat_id;
      if (!catId) {
        return activeCatIdsArray.includes('unassigned');
      }
      return activeCatIdsArray.includes(catId);
    });

    console.log('Communes after CAT filter:', filteredFeatures.length);

    // Group features by province
    const featuresByProvince = new globalThis.Map<string, GeoJSON.Feature[]>();
    filteredFeatures.forEach((feature) => {
      const provincia = feature.properties?.provincia || 'unknown';
      if (!featuresByProvince.has(provincia)) {
        featuresByProvince.set(provincia, []);
      }
      featuresByProvince.get(provincia)!.push(feature);
    });

    // Track existing layers for cleanup
    const existingLayers = new Set<string>();
    if (map.current.getStyle()) {
      map.current.getStyle().layers.forEach((layer) => {
        if (layer.id.startsWith('communes-fill-') || layer.id.startsWith('communes-line-')) {
          existingLayers.add(layer.id);
        }
      });
    }

    const newLayers = new Set<string>();

    // Create or update source and layers for each province
    featuresByProvince.forEach((features, provincia) => {
      const sourceId = `communes-${provincia}`;
      const fillLayerId = `communes-fill-${provincia}`;
      const lineLayerId = `communes-line-${provincia}`;

      newLayers.add(fillLayerId);
      newLayers.add(lineLayerId);

      const geojsonData: GeoJSON.FeatureCollection = {
        type: 'FeatureCollection',
        features: features
      };

      const source = map.current!.getSource(sourceId) as maplibregl.GeoJSONSource;
      if (!source) {
        map.current!.addSource(sourceId, {
          type: 'geojson',
          data: geojsonData
        });

        map.current!.addLayer({
          id: fillLayerId,
          type: 'fill',
          source: sourceId,
          paint: {
            'fill-color': ['get', 'cat_color'],
            'fill-opacity': selectedCommuneId 
              ? ['case', ['==', ['get', 'id'], selectedCommuneId], 0.25, 0.08]
              : 0.25
          }
        });

        map.current!.addLayer({
          id: lineLayerId,
          type: 'line',
          source: sourceId,
          paint: {
            'line-color': ['get', 'cat_color'],
            'line-width': 2.5,
            'line-opacity': selectedCommuneId
              ? ['case', ['==', ['get', 'id'], selectedCommuneId], 1, 0.3]
              : 1
          }
        });
      } else {
        source.setData(geojsonData);
      }
    });

    // Remove layers/sources that are no longer needed
    existingLayers.forEach((layerId) => {
      if (!newLayers.has(layerId)) {
        if (map.current!.getLayer(layerId)) {
          map.current!.removeLayer(layerId);
        }
        const sourceId = layerId.replace('communes-fill-', 'communes-').replace('communes-line-', 'communes-');
        if (map.current!.getSource(sourceId) && !Array.from(newLayers).some(l => l.includes(sourceId))) {
          map.current!.removeSource(sourceId);
        }
      }
    });

    // Set up event handlers once (only if not already set)
    if (!map.current.listens('mousemove')) {
      map.current.on('mousemove', (e) => {
        if (!map.current) return;
        const fillLayers = Array.from(newLayers).filter(l => l.startsWith('communes-fill-'));
        const features = map.current.queryRenderedFeatures(e.point, {
          layers: fillLayers
        });
        map.current.getCanvas().style.cursor = features.length > 0 ? 'pointer' : '';
      });

      // Handle clicks: prioritize neighborhoods and skip communes with neighborhoods
      map.current.on('click', async (e) => {
        if (!map.current) return;
        
        const fillLayers = map.current.getStyle().layers
          .filter(l => l.id.startsWith('communes-fill-') || l.id.startsWith('neighborhoods-fill-'))
          .map(l => l.id);
        
        const features = map.current.queryRenderedFeatures(e.point, {
          layers: fillLayers
        });
        
        if (features && features.length > 0) {
          // First check if there's a neighborhood feature
          const neighborhoodFeature = features.find(f => f.source && f.source.startsWith('neighborhoods'));
          if (neighborhoodFeature) {
            const id = neighborhoodFeature.properties?.id;
            if (id && onCommuneSelect) {
              onCommuneSelect(id);
              return;
            }
          }
          
          // If no neighborhood, check commune but verify it doesn't have neighborhoods
          const communeFeature = features.find(f => f.source && f.source.startsWith('communes-'));
          if (communeFeature) {
            const communeName = communeFeature.properties?.comune;
            
            // Check if this commune has neighborhoods using already loaded data
            const hasNeighborhoods = allCommunesWithNeighborhoods.includes(communeName);
            
            // Only select if it doesn't have neighborhoods
            if (!hasNeighborhoods) {
              const id = communeFeature.properties?.id;
              if (id && onCommuneSelect) {
                onCommuneSelect(id);
              }
            }
          }
        }
      });
    }
  }, [mapReady, communes, catAssociations, onCommuneSelect, activeCatIdsKey, allCommunesWithNeighborhoods]);

  // Removed automatic map centering on selection - user can control map view manually

  // Add highlight layer for selected commune/neighborhood
  useEffect(() => {
    if (!map.current || !mapReady || !selectedCommuneId) return;

    // Find the selected feature in communes or neighborhoods
    const selectedCommune = communes?.find(c => c.id === selectedCommuneId);
    const selectedNeighborhood = neighborhoods?.find(n => n.id === selectedCommuneId);
    const selectedFeature = selectedCommune || selectedNeighborhood;

    if (!selectedFeature) return;

    const highlightData: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features: [{
        type: 'Feature',
        geometry: selectedFeature.geom as any,
        properties: {
          id: selectedFeature.id
        }
      }]
    };

    const source = map.current.getSource('highlight') as maplibregl.GeoJSONSource;
    if (!source) {
      map.current.addSource('highlight', {
        type: 'geojson',
        data: highlightData
      });

      map.current.addLayer({
        id: 'highlight-line',
        type: 'line',
        source: 'highlight',
        paint: {
          'line-color': '#2563eb',
          'line-width': 5,
          'line-opacity': 1
        }
      });

      map.current.addLayer({
        id: 'highlight-fill',
        type: 'fill',
        source: 'highlight',
        paint: {
          'fill-color': '#2563eb',
          'fill-opacity': 0.15
        }
      });
    } else {
      source.setData(highlightData);
    }

    return () => {
      if (map.current && map.current.getLayer('highlight-line')) {
        map.current.removeLayer('highlight-line');
      }
      if (map.current && map.current.getLayer('highlight-fill')) {
        map.current.removeLayer('highlight-fill');
      }
      if (map.current && map.current.getSource('highlight')) {
        map.current.removeSource('highlight');
      }
    };
  }, [mapReady, selectedCommuneId, communes, neighborhoods]);

  // Update opacity of all layers when a commune is selected
  useEffect(() => {
    if (!map.current || !mapReady) return;

    const style = map.current.getStyle();
    if (!style) return;

    const fillOpacity = selectedCommuneId 
      ? ['case', ['==', ['get', 'id'], selectedCommuneId], 0.25, 0.08]
      : 0.25;
    const lineOpacity = selectedCommuneId
      ? ['case', ['==', ['get', 'id'], selectedCommuneId], 1, 0.3]
      : 1;

    style.layers.forEach((layer) => {
      if (layer.id.startsWith('communes-fill-') || layer.id.startsWith('neighborhoods-fill-')) {
        map.current!.setPaintProperty(layer.id, 'fill-opacity', fillOpacity);
      }
      if (layer.id.startsWith('communes-line-') || layer.id.startsWith('neighborhoods-line-')) {
        map.current!.setPaintProperty(layer.id, 'line-opacity', lineOpacity);
      }
    });
  }, [mapReady, selectedCommuneId]);

  // Add neighborhoods layer with filters - Split by province for better performance
  useEffect(() => {
    if (!map.current || !mapReady || !neighborhoods || !catAssociations) return;

    const allNeighborhoodFeatures = neighborhoods.map((neighborhood) => {
      const primaryCat = catAssociations.find(
        (assoc) => assoc.commune_id === neighborhood.id && assoc.is_primary && assoc.cats.active
      );

      return {
        type: 'Feature' as const,
        geometry: neighborhood.geom as any,
        properties: {
          id: neighborhood.id,
          quartiere: neighborhood.quartiere,
          comune: neighborhood.comune,
          provincia: neighborhood.provincia,
          regione: neighborhood.regione,
          cat_id: primaryCat?.cats.id || null,
          cat_color: primaryCat?.cats.color_hex || '#BBBBBB',
          cat_name: primaryCat?.cats.name || null
        }
      };
    });

    console.log('Total neighborhoods:', allNeighborhoodFeatures.length);

    // Filter neighborhoods based on active CAT IDs - if no filter, show all
    const filteredFeatures = !activeCatIdsArray ? allNeighborhoodFeatures : allNeighborhoodFeatures.filter((feature) => {
      const catId = feature.properties?.cat_id;
      if (!catId) {
        return activeCatIdsArray.includes('unassigned');
      }
      return activeCatIdsArray.includes(catId);
    });

    console.log('Neighborhoods after CAT filter:', filteredFeatures.length);

    // Group features by province
    const featuresByProvince = new globalThis.Map<string, GeoJSON.Feature[]>();
    filteredFeatures.forEach((feature) => {
      const provincia = feature.properties?.provincia || 'unknown';
      if (!featuresByProvince.has(provincia)) {
        featuresByProvince.set(provincia, []);
      }
      featuresByProvince.get(provincia)!.push(feature);
    });

    // Track existing layers for cleanup
    const existingLayers = new Set<string>();
    if (map.current.getStyle()) {
      map.current.getStyle().layers.forEach((layer) => {
        if (layer.id.startsWith('neighborhoods-fill-') || layer.id.startsWith('neighborhoods-line-')) {
          existingLayers.add(layer.id);
        }
      });
    }

    const newLayers = new Set<string>();

    // Create or update source and layers for each province
    featuresByProvince.forEach((features, provincia) => {
      const sourceId = `neighborhoods-${provincia}`;
      const fillLayerId = `neighborhoods-fill-${provincia}`;
      const lineLayerId = `neighborhoods-line-${provincia}`;

      newLayers.add(fillLayerId);
      newLayers.add(lineLayerId);

      const geojsonData: GeoJSON.FeatureCollection = {
        type: 'FeatureCollection',
        features: features
      };

      const source = map.current!.getSource(sourceId) as maplibregl.GeoJSONSource;
      if (!source) {
        map.current!.addSource(sourceId, {
          type: 'geojson',
          data: geojsonData
        });

        // Add neighborhoods fill layer ABOVE communes
        map.current!.addLayer({
          id: fillLayerId,
          type: 'fill',
          source: sourceId,
          paint: {
            'fill-color': ['get', 'cat_color'],
            'fill-opacity': selectedCommuneId 
              ? ['case', ['==', ['get', 'id'], selectedCommuneId], 0.25, 0.08]
              : 0.25
          }
        });

        // Add neighborhoods border with more prominent style
        map.current!.addLayer({
          id: lineLayerId,
          type: 'line',
          source: sourceId,
          paint: {
            'line-color': ['get', 'cat_color'],
            'line-width': 3,
            'line-opacity': selectedCommuneId
              ? ['case', ['==', ['get', 'id'], selectedCommuneId], 1, 0.3]
              : 1
          }
        });
      } else {
        source.setData(geojsonData);
      }
    });

    // Remove layers/sources that are no longer needed
    existingLayers.forEach((layerId) => {
      if (!newLayers.has(layerId)) {
        if (map.current!.getLayer(layerId)) {
          map.current!.removeLayer(layerId);
        }
        const sourceId = layerId.replace('neighborhoods-fill-', 'neighborhoods-').replace('neighborhoods-line-', 'neighborhoods-');
        if (map.current!.getSource(sourceId) && !Array.from(newLayers).some(l => l.includes(sourceId))) {
          map.current!.removeSource(sourceId);
        }
      }
    });
  }, [mapReady, neighborhoods, catAssociations, onCommuneSelect, activeCatIdsKey]);

  // Add commune boundaries layer for communes with neighborhoods
  useEffect(() => {
    if (!map.current || !mapReady || !communes || !allCommunesWithNeighborhoods) return;

    // Filter communes that have neighborhoods
    const communesWithNeighborhoods = communes.filter((commune) => 
      allCommunesWithNeighborhoods.includes(commune.comune)
    );

    const geojsonData: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features: communesWithNeighborhoods.map((commune) => ({
        type: 'Feature' as const,
        geometry: commune.geom as any,
        properties: {
          id: commune.id,
          comune: commune.comune
        }
      }))
    };

    const source = map.current.getSource('commune-boundaries') as maplibregl.GeoJSONSource;
    if (!source) {
      map.current.addSource('commune-boundaries', {
        type: 'geojson',
        data: geojsonData
      });

      // Add boundary line for communes with neighborhoods
      map.current.addLayer({
        id: 'commune-boundaries-line',
        type: 'line',
        source: 'commune-boundaries',
        paint: {
          'line-color': '#333333',
          'line-width': 2.5,
          'line-dasharray': [2, 2]
        }
      });
    } else {
      source.setData(geojsonData);
    }
  }, [mapReady, communes, allCommunesWithNeighborhoods]);

  // Calculate visible CAT counts on map move/zoom - including neighborhoods
  useEffect(() => {
    if (!map.current || !mapReady || !onVisibleCatsChange) return;

    const updateVisibleCats = () => {
      if (!map.current) return;

      const bounds = map.current.getBounds();
      const catCounts = new globalThis.Map<string, number>();

      // Count communes without neighborhoods
      allFeatures.forEach((feature) => {
        const geometry = feature.geometry as any;
        if (geometry && (geometry.type === 'MultiPolygon' || geometry.type === 'Polygon')) {
          const coords = geometry.type === 'MultiPolygon' 
            ? geometry.coordinates[0][0][0] 
            : geometry.coordinates[0][0];
          
          if (coords && bounds.contains([coords[0], coords[1]])) {
            const catId = feature.properties?.cat_id || 'unassigned';
            catCounts.set(catId, (catCounts.get(catId) || 0) + 1);
          }
        }
      });

      // Count neighborhoods (get from map sources)
      const style = map.current.getStyle();
      if (style) {
        const neighborhoodSources = Object.keys(style.sources).filter(s => s.startsWith('neighborhoods-'));
        neighborhoodSources.forEach(sourceId => {
          const source = map.current!.getSource(sourceId) as maplibregl.GeoJSONSource;
          if (source && (source as any)._data && (source as any)._data.features) {
            (source as any)._data.features.forEach((feature: any) => {
              const geometry = feature.geometry;
              if (geometry && (geometry.type === 'MultiPolygon' || geometry.type === 'Polygon')) {
                const coords = geometry.type === 'MultiPolygon' 
                  ? geometry.coordinates[0][0][0] 
                  : geometry.coordinates[0][0];
                
                if (coords && bounds.contains([coords[0], coords[1]])) {
                  const catId = feature.properties?.cat_id || 'unassigned';
                  catCounts.set(catId, (catCounts.get(catId) || 0) + 1);
                }
              }
            });
          }
        });
      }

      onVisibleCatsChange(catCounts);
    };

    map.current.on('moveend', updateVisibleCats);
    map.current.on('zoomend', updateVisibleCats);
    
    // Initial calculation
    updateVisibleCats();

    return () => {
      map.current?.off('moveend', updateVisibleCats);
      map.current?.off('zoomend', updateVisibleCats);
    };
  }, [mapReady, allFeatures, onVisibleCatsChange]);

  // Center on CAT when requested
  useEffect(() => {
    if (!map.current || !mapReady || !centerOnCat || !catAssociations) return;

    const catFeatures = allFeatures.filter((f) => 
      f.properties?.cat_id === centerOnCat || (centerOnCat === 'unassigned' && !f.properties?.cat_id)
    );

    if (catFeatures.length > 0) {
      // Calculate bounds of all features for this CAT
      const bounds = new maplibregl.LngLatBounds();
      
      catFeatures.forEach((feature) => {
        const geometry = feature.geometry as any;
        if (geometry && geometry.type === 'MultiPolygon') {
          geometry.coordinates.forEach((polygon: any) => {
            polygon[0].forEach((coord: [number, number]) => {
              bounds.extend(coord);
            });
          });
        } else if (geometry && geometry.type === 'Polygon') {
          geometry.coordinates[0].forEach((coord: [number, number]) => {
            bounds.extend(coord);
          });
        }
      });

      map.current.fitBounds(bounds, { padding: 50, duration: 800, easing: (t) => t * (2 - t) });
    }
  }, [centerOnCat, mapReady, allFeatures, catAssociations]);

  // Center on specific commune when requested
  useEffect(() => {
    if (!map.current || !mapReady || !centerOnCommuneId || !communes || !neighborhoods) return;

    // Find the commune or neighborhood
    const allCommunes = [...communes, ...neighborhoods];
    const targetCommune = allCommunes.find(c => c.id === centerOnCommuneId);
    
    if (targetCommune && targetCommune.geom) {
      const bounds = new maplibregl.LngLatBounds();
      const geometry = targetCommune.geom as any;
      
      if (geometry && geometry.type === 'MultiPolygon') {
        geometry.coordinates.forEach((polygon: any) => {
          polygon[0].forEach((coord: [number, number]) => {
            bounds.extend(coord);
          });
        });
      } else if (geometry && geometry.type === 'Polygon') {
        geometry.coordinates[0].forEach((coord: [number, number]) => {
          bounds.extend(coord);
        });
      }
      
      map.current.fitBounds(bounds, { padding: 80, duration: 800, easing: (t) => t * (2 - t) });
    }
  }, [centerOnCommuneId, mapReady, communes, neighborhoods]);

  // Center on specific coordinates when requested (e.g., from address search)
  useEffect(() => {
    if (!map.current || !mapReady || !centerOnCoordinates) return;

    // Remove existing marker if any
    if (addressMarkerRef.current) {
      addressMarkerRef.current.remove();
    }

    // Only create marker if showAddressMarker is true
    if (showAddressMarker) {
      // Create custom marker element
      const el = document.createElement('div');
      el.className = 'address-marker';
      el.style.cssText = `
        width: 40px;
        height: 40px;
        background-color: #ef4444;
        border: 4px solid white;
        border-radius: 50%;
        box-shadow: 0 4px 12px rgba(0,0,0,0.4);
        cursor: move;
        position: relative;
      `;

      // Add inner dot
      const innerDot = document.createElement('div');
      innerDot.style.cssText = `
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        width: 12px;
        height: 12px;
        background-color: white;
        border-radius: 50%;
      `;
      el.appendChild(innerDot);

      // Create and add draggable marker
      const marker = new maplibregl.Marker({ 
        element: el,
        draggable: true 
      })
        .setLngLat([centerOnCoordinates.lng, centerOnCoordinates.lat])
        .addTo(map.current);

      // Handle drag end event
      marker.on('dragend', () => {
        const lngLat = marker.getLngLat();
        if (onMarkerDragEnd) {
          onMarkerDragEnd(lngLat.lat, lngLat.lng);
        }
      });

      addressMarkerRef.current = marker;
    }

    // Smooth fly to location
    map.current.easeTo({
      center: [centerOnCoordinates.lng, centerOnCoordinates.lat],
      zoom: 16,
      duration: 1000,
      easing: (t) => t * (2 - t) // easeOutQuad
    });
  }, [centerOnCoordinates, mapReady, showAddressMarker, onMarkerDragEnd]);

  return (
    <div ref={mapContainer} className="absolute inset-0" />
  );
};

export default Map;
