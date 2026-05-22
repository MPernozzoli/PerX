import { useEffect, useRef, useState, useMemo, useCallback } from 'react';
import maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import { Session } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';
import type { InterventionMode, CAT, CATAssignment, PendingChange } from '@/pages/GISEditor';

interface BoundaryGeom {
  name: string;
  geom: any;
  regione?: string;
}

interface GISMapProps {
  session: Session | null;
  selectedCatId: string | null;
  currentMode: InterventionMode;
  assignments: CATAssignment[]; // Filtered by current mode
  allAssignments: CATAssignment[]; // All assignments including pending
  cats: CAT[];
  showLabels: boolean;
  showProvinceBorders: boolean;
  showRegionBorders: boolean;
  onLocalChange: (change: PendingChange) => void;
  pendingChanges: PendingChange[];
  provinceGeoms: BoundaryGeom[];
  regionGeoms: BoundaryGeom[];
}

interface CommuneData {
  id: string;
  comune: string;
  quartiere: string | null;
  provincia: string;
  regione: string;
  geom: any;
  centroid_lat: number | null;
  centroid_lng: number | null;
  use_quartieri?: boolean | null;
}

const GISMap = ({
  session,
  selectedCatId,
  currentMode,
  assignments,
  allAssignments,
  cats,
  showLabels,
  showProvinceBorders,
  showRegionBorders,
  onLocalChange,
  pendingChanges,
  provinceGeoms,
  regionGeoms
}: GISMapProps) => {
  const mapContainer = useRef<HTMLDivElement>(null);
  const map = useRef<maplibregl.Map | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const [communes, setCommunes] = useState<CommuneData[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadingProgress, setLoadingProgress] = useState(0);

  // Create a lookup for CAT colors
  const catColorMap = useMemo(() => {
    const map = new Map<string, string>();
    cats.forEach(cat => {
      map.set(cat.id, cat.color_hex || '#888888');
    });
    return map;
  }, [cats]);

  // Create assignment lookup by commune_id
  const assignmentMap = useMemo(() => {
    const map = new Map<string, CATAssignment[]>();
    assignments.forEach(a => {
      const existing = map.get(a.commune_id) || [];
      existing.push(a);
      map.set(a.commune_id, existing);
    });
    return map;
  }, [assignments]);

  // Fetch communes with pagination (Supabase default limit is 1000)
  useEffect(() => {
    const fetchCommunes = async () => {
      setIsLoading(true);
      const allCommunes: CommuneData[] = [];
      let page = 0;
      const pageSize = 1000;
      let hasMore = true;

      console.log('🗺️ GISMap: Starting to fetch communes...');

      while (hasMore) {
        const { data, error } = await supabase
          .from('communes')
          .select('id, comune, quartiere, provincia, regione, geom, centroid_lat, centroid_lng, use_quartieri')
          .range(page * pageSize, (page + 1) * pageSize - 1);
        
        if (error) {
          console.error('Error fetching communes:', error);
          break;
        }
        
        if (data && data.length > 0) {
          allCommunes.push(...(data as CommuneData[]));
          setLoadingProgress(allCommunes.length);
          console.log(`🗺️ GISMap: Loaded page ${page + 1}, total: ${allCommunes.length} communes`);
          hasMore = data.length === pageSize;
          page++;
        } else {
          hasMore = false;
        }
      }

      console.log(`🗺️ GISMap: Finished loading ${allCommunes.length} communes total`);
      setCommunes(allCommunes);
      setIsLoading(false);
    };
    
    fetchCommunes();
  }, []);

  // Separate communes and neighborhoods
  // Rispetta use_quartieri: se false, mostra il comune invece dei quartieri (case-insensitive)
  const { regularCommunes, neighborhoods, communesWithNeighborhoods } = useMemo(() => {
    // Trova comuni con use_quartieri = false (usa lowercase per confronto)
    const communesWithQuartieriDisabled = new Set(
      communes
        .filter(c => !c.quartiere && c.use_quartieri === false)
        .map(c => c.comune.toLowerCase())
    );

    // Filtra i quartieri: escludi quelli di comuni con use_quartieri = false
    const neighborhoods = communes.filter(c => 
      c.quartiere && !communesWithQuartieriDisabled.has(c.comune.toLowerCase())
    );
    
    // Nomi di comuni che hanno quartieri attivi (use_quartieri != false)
    const communeNamesWithActiveNeighborhoods = new Set(
      neighborhoods.map(n => n.comune.toLowerCase())
    );
    
    // Comuni normali: quelli senza quartieri O quelli con use_quartieri = false
    const regularCommunes = communes.filter(c => 
      !c.quartiere && !communeNamesWithActiveNeighborhoods.has(c.comune.toLowerCase())
    );
    
    // Comuni con quartieri attivi (per il layer dei confini)
    const communesWithNeighborhoods = communes.filter(c => 
      !c.quartiere && communeNamesWithActiveNeighborhoods.has(c.comune.toLowerCase())
    );
    
    return { regularCommunes, neighborhoods, communesWithNeighborhoods };
  }, [communes]);


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
            attribution: '&copy; OpenStreetMap'
          }
        },
        layers: [{
          id: 'osm',
          type: 'raster',
          source: 'osm',
          minzoom: 0,
          maxzoom: 19
        }]
      },
      center: [12.5, 42.5],
      zoom: 6,
      attributionControl: false
    });

    map.current.addControl(new maplibregl.NavigationControl(), 'bottom-right');

    map.current.on('load', () => {
      setMapReady(true);
    });

    return () => {
      map.current?.remove();
      map.current = null;
    };
  }, []);

  // Handle geometry click - creates local change, doesn't save to DB
  const handleGeometryClick = useCallback((communeId: string) => {
    if (!selectedCatId) return;
    
    // Find existing assignment for this commune and selected CAT
    const communeAssignments = assignmentMap.get(communeId) || [];
    const existingForCat = communeAssignments.find(a => a.cat_id === selectedCatId);
    
    if (existingForCat) {
      // Toggle: create removal change
      // Only create removal if it's a real assignment (not pending)
      if (!existingForCat.id.startsWith('pending-')) {
        onLocalChange({
          type: 'remove',
          communeId,
          catId: selectedCatId,
          interventionType: currentMode,
          originalAssignmentId: existingForCat.id
        });
      } else {
        // It's a pending add - cancel it by creating opposite change
        onLocalChange({
          type: 'remove',
          communeId,
          catId: selectedCatId,
          interventionType: currentMode
        });
      }
    } else {
      // Check if commune has other CATs for this mode
      const hasOtherCat = communeAssignments.length > 0;
      
      // Create add change
      onLocalChange({
        type: 'add',
        communeId,
        catId: selectedCatId,
        interventionType: currentMode,
        isPrimary: !hasOtherCat
      });
    }
  }, [selectedCatId, currentMode, assignmentMap, onLocalChange]);

  // Create features for all geometries
  const createFeatures = useCallback((items: CommuneData[], isNeighborhood: boolean = false) => {
    return items.map(item => {
      const communeAssignments = assignmentMap.get(item.id) || [];
      const primaryAssignment = communeAssignments.find(a => a.is_primary);
      const catColor = primaryAssignment 
        ? catColorMap.get(primaryAssignment.cat_id) || '#CCCCCC'
        : '#CCCCCC';
      
      const isAssignedToSelected = selectedCatId 
        ? communeAssignments.some(a => a.cat_id === selectedCatId)
        : false;

      return {
        type: 'Feature' as const,
        geometry: item.geom,
        properties: {
          id: item.id,
          comune: item.comune,
          quartiere: item.quartiere,
          provincia: item.provincia,
          regione: item.regione,
          cat_color: catColor,
          cat_id: primaryAssignment?.cat_id || null,
          is_assigned: communeAssignments.length > 0,
          is_assigned_to_selected: isAssignedToSelected,
          centroid_lat: item.centroid_lat,
          centroid_lng: item.centroid_lng,
          label: isNeighborhood ? item.quartiere : item.comune
        }
      };
    });
  }, [assignmentMap, catColorMap, selectedCatId]);

  // Update map layers
  useEffect(() => {
    if (!map.current || !mapReady || communes.length === 0) return;

    const m = map.current;

    // Create commune features
    const communeFeatures = createFeatures(regularCommunes);
    const neighborhoodFeatures = createFeatures(neighborhoods, true);
    const boundaryFeatures = communesWithNeighborhoods.map(c => ({
      type: 'Feature' as const,
      geometry: c.geom,
      properties: { id: c.id, comune: c.comune }
    }));

    // Commune source and layers
    const communeSource = m.getSource('communes') as maplibregl.GeoJSONSource;
    const communeData: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features: communeFeatures
    };

    if (!communeSource) {
      m.addSource('communes', { type: 'geojson', data: communeData });
      
      // Fill layer
      m.addLayer({
        id: 'communes-fill',
        type: 'fill',
        source: 'communes',
        paint: {
          'fill-color': ['get', 'cat_color'],
          'fill-opacity': [
            'case',
            ['get', 'is_assigned_to_selected'], 0.5,
            ['get', 'is_assigned'], 0.25,
            0.1
          ]
        }
      });

      // Line layer
      m.addLayer({
        id: 'communes-line',
        type: 'line',
        source: 'communes',
        paint: {
          'line-color': [
            'case',
            ['get', 'is_assigned_to_selected'], '#2563eb',
            ['get', 'cat_color']
          ],
          'line-width': [
            'case',
            ['get', 'is_assigned_to_selected'], 3,
            2
          ],
          'line-opacity': 1
        }
      });
    } else {
      communeSource.setData(communeData);
    }

    // Neighborhood source and layers
    const neighborhoodSource = m.getSource('neighborhoods') as maplibregl.GeoJSONSource;
    const neighborhoodData: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features: neighborhoodFeatures
    };

    if (!neighborhoodSource) {
      m.addSource('neighborhoods', { type: 'geojson', data: neighborhoodData });
      
      m.addLayer({
        id: 'neighborhoods-fill',
        type: 'fill',
        source: 'neighborhoods',
        paint: {
          'fill-color': ['get', 'cat_color'],
          'fill-opacity': [
            'case',
            ['get', 'is_assigned_to_selected'], 0.5,
            ['get', 'is_assigned'], 0.25,
            0.1
          ]
        }
      });

      m.addLayer({
        id: 'neighborhoods-line',
        type: 'line',
        source: 'neighborhoods',
        paint: {
          'line-color': [
            'case',
            ['get', 'is_assigned_to_selected'], '#2563eb',
            ['get', 'cat_color']
          ],
          'line-width': [
            'case',
            ['get', 'is_assigned_to_selected'], 3,
            2
          ],
          'line-opacity': 1
        }
      });
    } else {
      neighborhoodSource.setData(neighborhoodData);
    }

    // Commune boundaries (for communes with neighborhoods)
    const boundarySource = m.getSource('commune-boundaries') as maplibregl.GeoJSONSource;
    const boundaryData: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features: boundaryFeatures
    };

    if (!boundarySource) {
      m.addSource('commune-boundaries', { type: 'geojson', data: boundaryData });
      
      m.addLayer({
        id: 'commune-boundaries-line',
        type: 'line',
        source: 'commune-boundaries',
        paint: {
          'line-color': '#333333',
          'line-width': 3,
          'line-dasharray': [3, 2]
        }
      });
    } else {
      boundarySource.setData(boundaryData);
    }

  }, [mapReady, communes, regularCommunes, neighborhoods, communesWithNeighborhoods, createFeatures]);

  // Labels layer
  useEffect(() => {
    if (!map.current || !mapReady || communes.length === 0) return;

    const m = map.current;
    const layerId = 'commune-labels';

    // Create label features with centroids (use all communes, not just filtered)
    const labelFeatures = communes
      .filter(c => c.centroid_lat && c.centroid_lng)
      .map(c => ({
        type: 'Feature' as const,
        geometry: {
          type: 'Point' as const,
          coordinates: [c.centroid_lng!, c.centroid_lat!]
        },
        properties: {
          label: c.quartiere || c.comune
        }
      }));

    console.log(`Labels: ${labelFeatures.length} features with centroids, showLabels: ${showLabels}`);

    const data: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features: labelFeatures
    };

    const source = m.getSource('commune-labels') as maplibregl.GeoJSONSource;

    if (!source) {
      m.addSource('commune-labels', { type: 'geojson', data });
      
      m.addLayer({
        id: layerId,
        type: 'symbol',
        source: 'commune-labels',
        layout: {
          'text-field': ['get', 'label'],
          'text-size': [
            'interpolate', ['linear'], ['zoom'],
            6, 8,
            10, 11,
            14, 14
          ],
          'text-anchor': 'center',
          'text-allow-overlap': false,
          'text-ignore-placement': false,
          'visibility': showLabels ? 'visible' : 'none'
        },
        paint: {
          'text-color': '#1a1a1a',
          'text-halo-color': '#ffffff',
          'text-halo-width': 2
        }
      });
    } else {
      source.setData(data);
    }
    
    // Always update visibility
    if (m.getLayer(layerId)) {
      m.setLayoutProperty(layerId, 'visibility', showLabels ? 'visible' : 'none');
    }
  }, [mapReady, showLabels, communes]);

  // Province borders layer - uses pre-loaded province geometries
  useEffect(() => {
    if (!map.current || !mapReady || provinceGeoms.length === 0) return;
    const m = map.current;

    const layerId = 'province-borders';
    const sourceId = 'province-boundaries';

    // Build features from province geometries
    const provinceColors = [
      '#e63946', '#f4a261', '#2a9d8f', '#264653', '#e9c46a',
      '#606c38', '#283618', '#bc6c25', '#9b2226', '#0077b6'
    ];
    
    const features: GeoJSON.Feature[] = provinceGeoms.map((p, i) => ({
      type: 'Feature',
      geometry: p.geom,
      properties: {
        name: p.name,
        color: provinceColors[i % provinceColors.length]
      }
    }));

    const data: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features
    };

    const source = m.getSource(sourceId) as maplibregl.GeoJSONSource;
    
    if (!source) {
      m.addSource(sourceId, { type: 'geojson', data });
      
      m.addLayer({
        id: layerId,
        type: 'line',
        source: sourceId,
        layout: {
          'visibility': showProvinceBorders ? 'visible' : 'none'
        },
        paint: {
          'line-color': ['get', 'color'],
          'line-width': 3,
          'line-opacity': 0.8
        }
      }, 'communes-fill');
    } else {
      source.setData(data);
      m.setLayoutProperty(layerId, 'visibility', showProvinceBorders ? 'visible' : 'none');
    }
  }, [mapReady, showProvinceBorders, provinceGeoms]);

  // Region borders layer - uses pre-loaded region geometries
  useEffect(() => {
    if (!map.current || !mapReady || regionGeoms.length === 0) return;
    const m = map.current;

    const layerId = 'region-borders';
    const sourceId = 'region-boundaries';

    // Build features from region geometries
    const regionColors = [
      '#1d3557', '#457b9d', '#a8dadc', '#2d6a4f', '#40916c'
    ];
    
    const features: GeoJSON.Feature[] = regionGeoms.map((r, i) => ({
      type: 'Feature',
      geometry: r.geom,
      properties: {
        name: r.name,
        color: regionColors[i % regionColors.length]
      }
    }));

    const data: GeoJSON.FeatureCollection = {
      type: 'FeatureCollection',
      features
    };

    const source = m.getSource(sourceId) as maplibregl.GeoJSONSource;
    
    if (!source) {
      m.addSource(sourceId, { type: 'geojson', data });
      
      m.addLayer({
        id: layerId,
        type: 'line',
        source: sourceId,
        layout: {
          'visibility': showRegionBorders ? 'visible' : 'none'
        },
        paint: {
          'line-color': ['get', 'color'],
          'line-width': 4,
          'line-opacity': 0.8
        }
      }, 'communes-fill');
    } else {
      source.setData(data);
      m.setLayoutProperty(layerId, 'visibility', showRegionBorders ? 'visible' : 'none');
    }
  }, [mapReady, showRegionBorders, regionGeoms]);

  // Click handler setup
  useEffect(() => {
    if (!map.current || !mapReady) return;

    const m = map.current;

    const handleClick = (e: maplibregl.MapMouseEvent) => {
      const layers = ['neighborhoods-fill', 'communes-fill'].filter(l => m.getLayer(l));
      
      const features = m.queryRenderedFeatures(e.point, { layers });
      
      if (features.length > 0) {
        // Prioritize neighborhoods
        const neighborhoodFeature = features.find(f => f.layer?.id === 'neighborhoods-fill');
        const feature = neighborhoodFeature || features[0];
        
        const id = feature.properties?.id;
        if (id) {
          handleGeometryClick(id);
        }
      }
    };

    const handleMouseMove = (e: maplibregl.MapMouseEvent) => {
      const layers = ['neighborhoods-fill', 'communes-fill'].filter(l => m.getLayer(l));
      const features = m.queryRenderedFeatures(e.point, { layers });
      m.getCanvas().style.cursor = features.length > 0 && selectedCatId ? 'pointer' : '';
    };

    m.on('click', handleClick);
    m.on('mousemove', handleMouseMove);

    return () => {
      m.off('click', handleClick);
      m.off('mousemove', handleMouseMove);
    };
  }, [mapReady, handleGeometryClick, selectedCatId]);

  return (
    <div className="relative w-full h-full">
      <div ref={mapContainer} className="absolute inset-0" />
      
      {/* Loading indicator */}
      {isLoading && (
        <div className="absolute inset-0 bg-background/80 backdrop-blur-sm flex items-center justify-center z-10">
          <div className="bg-card p-6 rounded-lg shadow-lg text-center">
            <div className="animate-spin rounded-full h-8 w-8 border-2 border-primary border-t-transparent mx-auto mb-4"></div>
            <p className="text-sm font-medium">Caricamento geometrie...</p>
            <p className="text-xs text-muted-foreground mt-1">{loadingProgress.toLocaleString()} comuni caricati</p>
          </div>
        </div>
      )}
      
      {/* Pending changes indicator */}
      {pendingChanges.length > 0 && (
        <div className="absolute top-4 left-1/2 -translate-x-1/2 bg-primary/90 backdrop-blur-sm px-4 py-2 rounded-full shadow-lg z-10">
          <p className="text-sm text-white font-medium">
            {pendingChanges.length} modific{pendingChanges.length === 1 ? 'a' : 'he'} da salvare
          </p>
        </div>
      )}

      {/* No CAT selected hint */}
      {!selectedCatId && !isLoading && (
        <div className="absolute bottom-4 left-1/2 -translate-x-1/2 bg-background/90 backdrop-blur-sm px-4 py-2 rounded-lg shadow-lg">
          <p className="text-sm text-muted-foreground">
            Seleziona un CAT dal pannello per iniziare ad assegnare
          </p>
        </div>
      )}
    </div>
  );
};

export default GISMap;
