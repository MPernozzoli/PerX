import { useState, useEffect, useCallback } from 'react';
import Map from '@/components/Map';
import SearchBar from '@/components/SearchBar';
import MapLegend from '@/components/MapLegend';
import CommunePopup from '@/components/CommunePopup';
import { Button } from '@/components/ui/button';
import { Settings, LogOut } from 'lucide-react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useAnonymousAuth } from '@/hooks/useAnonymousAuth';
import { toast } from 'sonner';
import { LoadingProgress } from '@/components/LoadingProgress';
import { useMapDataCache } from '@/hooks/useMapDataCache';
import { clearPerXSession } from '@/lib/perxApi';

const Index = () => {
  const { session, loading: authLoading, requiresLogin } = useAnonymousAuth();
  const [searchParams, setSearchParams] = useSearchParams();
  const [isAdmin, setIsAdmin] = useState(false);
  const [selectedCommune, setSelectedCommune] = useState<string | null>(null);
  const [activeCatIds, setActiveCatIds] = useState<Set<string> | undefined>(undefined);
  const [visibleCatCounts, setVisibleCatCounts] = useState<Map<string, number>>(() => new globalThis.Map());
  const [centerOnCat, setCenterOnCat] = useState<string | null>(null);
  const [centerOnCommuneId, setCenterOnCommuneId] = useState<string | null>(null);
  const [centerOnCoordinates, setCenterOnCoordinates] = useState<{ lat: number; lng: number } | null>(null);
  const [mapBounds, setMapBounds] = useState<{ north: number; south: number; east: number; west: number } | null>(null);
  const [loadingToastId, setLoadingToastId] = useState<string | number | null>(null);
  const [initialSearch, setInitialSearch] = useState<string>('');
  const navigate = useNavigate();
  
  // Read search parameter from URL
  useEffect(() => {
    const searchQuery = searchParams.get('search');
    if (searchQuery) {
      setInitialSearch(searchQuery);
      // Clear the URL parameter after reading it
      setSearchParams({}, { replace: true });
    }
  }, [searchParams, setSearchParams]);

  // Use cached map data
  const { data: mapData, isLoading: isLoadingMapData, isBackgroundRefresh } = useMapDataCache(!!session);

  // Show loading toast only for initial load
  useEffect(() => {
    if (isLoadingMapData && !isBackgroundRefresh && session && !loadingToastId) {
      const toastId = toast(
        <LoadingProgress 
          isLoading={true} 
          onComplete={() => toast.dismiss(toastId)}
        />,
        {
          duration: Infinity,
          closeButton: false,
        }
      );
      setLoadingToastId(toastId);
    } else if (!isLoadingMapData && loadingToastId) {
      toast.dismiss(loadingToastId);
      if (mapData) {
        const totalCommunes = mapData.communes?.length || 0;
        const communesWithGeometry = mapData.communes?.filter((c: any) => c.geom).length || 0;
        
        // Show status toast with geometry info
        const toastId = toast(
          <LoadingProgress 
            isLoading={false}
            geometryStatus={{
              total: totalCommunes,
              loaded: communesWithGeometry
            }}
            onComplete={() => toast.dismiss(toastId)}
          />,
          {
            duration: 5000,
            closeButton: true,
          }
        );
      }
      setLoadingToastId(null);
    }
  }, [isLoadingMapData, isBackgroundRefresh, session, loadingToastId, mapData]);

  // Show silent background refresh notification
  useEffect(() => {
    if (isBackgroundRefresh) {
      console.log('🔄 Aggiornamento dati in background...');
    }
  }, [isBackgroundRefresh]);

  useEffect(() => {
    // Initialize with all CATs active when mapData is loaded
    if (mapData?.cats && activeCatIds === undefined) {
      const initialCatIds = new globalThis.Set(mapData.cats.map((cat: any) => cat.id));
      setActiveCatIds(initialCatIds);
    }
  }, [mapData?.cats, activeCatIds]);

  // Check admin status
  useEffect(() => {
    setIsAdmin(Boolean(session?.user.is_platform_admin || session?.user.roles.some((role) => ['admin', 'site_admin'].includes(role))));
  }, [session]);

  const handleSearch = (result: any) => {
    if (result.type === 'comune' || result.type === 'quartiere' || result.type === 'address') {
      // Select the commune/neighborhood
      setSelectedCommune(result.id);
      
      // Center on coordinates if available (for addresses)
      if (result.coordinates) {
        setCenterOnCoordinates(result.coordinates);
        // Reset after animation
        setTimeout(() => setCenterOnCoordinates(null), 1000);
      } else {
        // For communes/neighborhoods without specific coordinates, we'll center on the selected feature
        // This is handled by the map component itself when selectedCommuneId changes
      }
    } else if (result.type === 'cat') {
      // For CAT search, center on that CAT
      handleCenterOnCat(result.id);
    }
  };

  const handleToggleCat = (catId: string) => {
    setActiveCatIds((prev) => {
      const newSet = new globalThis.Set(prev);
      if (newSet.has(catId)) {
        newSet.delete(catId);
      } else {
        newSet.add(catId);
      }
      return newSet;
    });
  };

  const handleCenterOnCat = useCallback((catId: string) => {
    setCenterOnCat(catId);
    // Reset after a short delay to allow re-centering on same CAT
    setTimeout(() => setCenterOnCat(null), 100);
  }, []);

  const handleVisibleCatsChange = useCallback((catCounts: Map<string, number>) => {
    setVisibleCatCounts(catCounts);
  }, []);

  const handleCenterOnCommune = useCallback((communeId: string) => {
    setCenterOnCommuneId(communeId);
    // Reset after animation
    setTimeout(() => setCenterOnCommuneId(null), 100);
  }, []);

  const handleLogout = async () => {
    clearPerXSession();
    toast.success('Disconnesso con successo');
    navigate('/login');
  };

  useEffect(() => {
    if (requiresLogin && !authLoading) {
      navigate('/login');
    }
  }, [requiresLogin, authLoading, navigate]);

  // Show loading state while authenticating
  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-background">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary mx-auto mb-4"></div>
          <p className="text-muted-foreground">Caricamento...</p>
        </div>
      </div>
    );
  }

  // If requires login, don't render the page
  if (requiresLogin) {
    return null;
  }

  return (
    <div className="relative h-[calc(100vh-3.5rem)] w-screen overflow-hidden bg-background">
      {/* Map */}
      <Map
        session={session}
        mapData={mapData}
        mapDataLoading={isLoadingMapData}
        onCommuneSelect={setSelectedCommune}
        highlightedCommune={selectedCommune}
        activeCatIds={activeCatIds}
        onVisibleCatsChange={handleVisibleCatsChange}
        centerOnCat={centerOnCat}
        centerOnCommuneId={centerOnCommuneId}
        selectedCommuneId={selectedCommune}
        centerOnCoordinates={centerOnCoordinates}
        onBoundsChange={setMapBounds}
      />

      {/* Header with Search and Login - compact design */}
      <header className="absolute top-0 left-0 right-0 z-20 py-3 px-4 bg-background backdrop-blur-md border-b border-border shadow-sm">
        <div className="max-w-7xl mx-auto flex items-center justify-between gap-4">
          <div className="flex items-center gap-3 flex-1">
            <img 
              src="/logo-text.png" 
              alt="CAT Dispatcher" 
              className="h-6 w-auto"
            />
            <SearchBar onSelect={handleSearch} mapBounds={mapBounds} initialValue={initialSearch} />
          </div>
          <div className="flex items-center gap-2">
            {isAdmin && (
              <Button
                variant="outline"
                size="sm"
                onClick={() => navigate('/admin')}
                className="flex-shrink-0"
              >
                <Settings className="h-4 w-4 mr-2" />
                Admin
              </Button>
            )}
            <Button
              variant="outline"
              size="sm"
              onClick={handleLogout}
              className="flex-shrink-0"
            >
              <LogOut className="h-4 w-4 mr-2" />
              Esci
            </Button>
          </div>
        </div>
      </header>

      {/* Legend */}
      <div className="absolute bottom-4 left-4 z-10">
        <MapLegend 
          cats={mapData?.cats || []}
          activeCatIds={activeCatIds}
          onToggleCat={handleToggleCat}
          onCenterOnCat={handleCenterOnCat}
          visibleCatCounts={visibleCatCounts}
          suspendedCatIds={mapData?.suspended_cat_ids || []}
        />
      </div>

      {/* Popup */}
      {selectedCommune && (
        <CommunePopup
          communeId={selectedCommune}
          onClose={() => setSelectedCommune(null)}
          onNavigate={(id) => setSelectedCommune(id)}
          onCenterOnCommune={handleCenterOnCommune}
        />
      )}
    </div>
  );
};

export default Index;
