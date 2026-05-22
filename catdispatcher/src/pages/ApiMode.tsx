import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import Map from '@/components/Map';
import CATBottomBar from '@/components/CATBottomBar';
import { toast } from 'sonner';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Info, AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAnonymousAuth } from '@/hooks/useAnonymousAuth';
import { LoadingProgress } from '@/components/LoadingProgress';
import { useMapDataCache } from '@/hooks/useMapDataCache';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';

interface GeocodingResult {
  lat: number;
  lon: number;
  display_name: string;
}

interface SuspendedCatInfo {
  id: string;
  name: string;
  color: string;
  suspension_end_date: string;
  suspension_reason: string;
}

const ApiMode = () => {
  const { session, loading: authLoading } = useAnonymousAuth();
  const [searchParams] = useSearchParams();
  const [selectedCommune, setSelectedCommune] = useState<string | null>(null);
  const [centerCoordinates, setCenterCoordinates] = useState<{ lat: number; lng: number } | null>(null);
  const [markerPosition, setMarkerPosition] = useState<{ lat: number; lng: number } | null>(null);
  const [geocodingInfo, setGeocodingInfo] = useState<string>('');
  const [showInfo, setShowInfo] = useState(false);
  const [loadingToastId, setLoadingToastId] = useState<string | number | null>(null);
  const [suspendedCatDialog, setSuspendedCatDialog] = useState<SuspendedCatInfo | null>(null);

  // Parse address from URL parameters
  const via = searchParams.get('via');
  const civico = searchParams.get('civico');
  const citta = searchParams.get('citta');
  const cap = searchParams.get('cap');
  const provincia = searchParams.get('provincia');
  const nazione = searchParams.get('nazione') || 'Italia';

  // Use cached map data
  const { data: mapData, isLoading: isLoadingMapData, isBackgroundRefresh } = useMapDataCache(!!session);

  // Show loading toast only for initial load (not background refresh)
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
      setLoadingToastId(null);
    }
  }, [isLoadingMapData, isBackgroundRefresh, session, loadingToastId]);

  useEffect(() => {
    const geocodeAddress = async () => {
      if (!citta && !via) {
        console.log('⚠️ No city or street provided');
        toast.error('Indirizzo non valido: città o via richiesta');
        return;
      }

      // Build full address
      let fullAddress = '';
      if (via) {
        fullAddress += via;
        if (civico) fullAddress += ' ' + civico;
        fullAddress += ', ';
      }
      if (citta) fullAddress += citta;
      if (provincia) fullAddress += ' (' + provincia + ')';
      if (cap) fullAddress += ' ' + cap;
      if (nazione) fullAddress += ', ' + nazione;

      console.log('🏠 Full address to geocode:', fullAddress);

      try {
        console.log('🚀 Starting geocoding for:', fullAddress);
        
        // Try full address first
        let result = await geocode(fullAddress);
        console.log('📍 Geocode result for full address:', result);
        
        if (!result && via && citta) {
          // Retry with just street and city
          console.log('⚠️ Retrying with street and city only');
          setGeocodingInfo('Indirizzo esatto non trovato, ricerca con via e città');
          setShowInfo(true);
          setTimeout(() => setShowInfo(false), 5000);
          result = await geocode(`${via}, ${citta}, ${nazione}`);
          console.log('📍 Geocode result for street+city:', result);
        }
        
        if (!result && citta) {
          // Retry with just city
          console.log('⚠️ Retrying with city only');
          setGeocodingInfo('Via non trovata, ricerca solo comune');
          setShowInfo(true);
          setTimeout(() => setShowInfo(false), 5000);
          result = await geocode(`${citta}, ${nazione}`);
          console.log('📍 Geocode result for city only:', result);
        }

        if (result) {
          const coords = { lat: result.lat, lng: result.lon };
          console.log('✅ Final coordinates:', coords);
          
          // IMPORTANTE: Prima settiamo le coordinate
          setCenterCoordinates(coords);
          setMarkerPosition(coords);
          
          console.log('🔎 Now calling findCommuneAtPoint...');
          
          // Poi cerchiamo il comune - CON AWAIT per aspettare che finisca
          await findCommuneAtPoint(coords.lat, coords.lng);
          
          toast.success('Indirizzo trovato');
        } else {
          console.log('❌ No geocoding result found');
          toast.error('Impossibile trovare l\'indirizzo specificato');
        }
      } catch (error) {
        console.error('💥 Geocoding error:', error);
        toast.error('Errore durante la ricerca dell\'indirizzo');
      }
    };

    geocodeAddress();
  }, [via, civico, citta, cap, provincia, nazione]);

  const geocode = async (address: string): Promise<GeocodingResult | null> => {
    try {
      const { data, error } = await supabase.functions.invoke('geocode', {
        body: { address }
      });

      if (error) {
        console.error('Geocoding error:', error);
        return null;
      }

      if (data && data.lat && data.lng) {
        return {
          lat: data.lat,
          lon: data.lng,
          display_name: data.formatted_address
        };
      }
      
      return null;
    } catch (error) {
      console.error('Geocoding API error:', error);
      return null;
    }
  };

  const findCommuneAtPoint = async (lat: number, lng: number) => {
    try {
      console.log(`🔍 Searching for commune at point: ${lat}, ${lng}`);
      
      // PRIORITÀ AI QUARTIERI: Prima cerchiamo se esiste un quartiere che contiene il punto
      const { data, error } = await supabase.rpc('find_commune_at_point', {
        point_lat: lat,
        point_lng: lng
      });

      console.log('📍 RPC Response - data:', data);
      console.log('📍 RPC Response - error:', error);
      console.log('📍 RPC Response - data length:', data?.length);

      if (error) {
        console.error('❌ Error finding commune:', error);
        toast.error(`Errore ricerca comune: ${error.message}`);
        return;
      }

      if (data && data.length > 0) {
        // Se abbiamo più risultati (comune + quartieri), prendiamo il quartiere (quello con quartiere NOT NULL)
        const neighborhood = data.find((item: any) => item.quartiere !== null);
        const result = neighborhood || data[0];
        
        console.log('✅ Found result:', result);
        console.log(`📌 Type: ${result.quartiere ? 'Quartiere' : 'Comune'}`);
        console.log('🆔 Setting selectedCommune to:', result.id);
        
        // Settiamo il comune selezionato
        setSelectedCommune(result.id);
        
        console.log('✅ selectedCommune has been set!');
        
        if (result.quartiere) {
          toast.success(`Quartiere trovato: ${result.quartiere} (${result.comune})`);
        } else {
          toast.success(`Comune trovato: ${result.comune}`);
        }
      } else {
        console.log('⚠️ No commune found at this point');
        toast.info('Nessun comune trovato in questa posizione');
      }
    } catch (error) {
      console.error('❌ Exception finding commune:', error);
      toast.error('Errore nella ricerca del comune');
    }
  };

  const handleCommuneSelect = (communeId: string) => {
    setSelectedCommune(communeId);
  };

  const handleCatSelect = (catData: { 
    id: string; 
    name: string; 
    color: string;
    suspended?: boolean;
    suspension_end_date?: string;
    suspension_reason?: string;
  }) => {
    console.log('🎯 CAT selected in API mode:', catData);

    // Se il CAT è sospeso, mostra dialog di conferma
    if (catData.suspended) {
      setSuspendedCatDialog({
        id: catData.id,
        name: catData.name,
        color: catData.color,
        suspension_end_date: catData.suspension_end_date || '',
        suspension_reason: catData.suspension_reason || 'altro'
      });
      return;
    }

    // Procedi con l'assegnazione
    assignCat(catData.name);
  };

  const assignCat = (catName: string) => {
    // Send the CAT alias to parent window (for extension)
    if (window.opener) {
      window.opener.postMessage({
        type: 'CAT_SELECTED',
        data: catName
      }, '*');
    }
    
    // Also post to parent if embedded in iframe
    window.parent.postMessage({
      type: 'CAT_SELECTED',
      data: catName
    }, '*');
    
    toast.success(`CAT selezionato: ${catName}`, {
      duration: 8000
    });
  };

  const handleConfirmSuspendedCat = () => {
    if (suspendedCatDialog) {
      assignCat(suspendedCatDialog.name);
      setSuspendedCatDialog(null);
    }
  };

  const formatDate = (dateStr: string) => {
    if (!dateStr) return '';
    return new Date(dateStr).toLocaleDateString('it-IT', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric'
    });
  };

  const getReasonLabel = (reason: string) => {
    switch (reason) {
      case 'malattia': return 'malattia';
      case 'ferie': return 'ferie';
      case 'disattivato': return 'disattivato';
      default: return null;
    }
  };

  const handleMarkerDragEnd = (lat: number, lng: number) => {
    setMarkerPosition({ lat, lng });
    toast.info('Posizione aggiornata');
  };

  const handleNavigate = (communeId: string) => {
    setSelectedCommune(communeId);
  };

  return (
    <div className="relative w-full h-[calc(100vh-3.5rem)] overflow-hidden">
      {/* Logo */}
      <div className="absolute top-4 left-4 z-20 bg-card/90 backdrop-blur-md px-4 py-2 rounded-lg shadow-lg border">
        <img 
          src="/logo-text.png" 
          alt="CAT Dispatcher" 
          className="h-6 w-auto"
        />
      </div>

      {/* Info Alert */}
      {showInfo && (
        <div className="absolute top-4 left-1/2 -translate-x-1/2 z-20 w-96">
          <Alert className="bg-card/95 backdrop-blur-md border-primary/50">
            <Info className="h-4 w-4" />
            <AlertDescription>{geocodingInfo}</AlertDescription>
          </Alert>
        </div>
      )}

      {/* Map - Full screen */}
      <Map
        session={session}
        mapData={mapData}
        mapDataLoading={isLoadingMapData}
        onCommuneSelect={handleCommuneSelect}
        highlightedCommune={selectedCommune}
        selectedCommuneId={selectedCommune}
        centerOnCoordinates={centerCoordinates}
        showAddressMarker={true}
        onMarkerDragEnd={handleMarkerDragEnd}
        limitToRadius={centerCoordinates ? { ...centerCoordinates, radiusKm: 2 } : null}
      />

      {/* Bottom Bar per CAT - Sempre visibile */}
      <CATBottomBar
        communeId={selectedCommune}
        onCatSelect={handleCatSelect}
      />

      {/* Dialog conferma CAT sospeso */}
      <AlertDialog open={!!suspendedCatDialog} onOpenChange={() => setSuspendedCatDialog(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-amber-500" />
              CAT temporaneamente sospeso
            </AlertDialogTitle>
            <AlertDialogDescription className="text-base">
              {suspendedCatDialog && (
                <>
                  <strong>{suspendedCatDialog.name}</strong>
                  {suspendedCatDialog.suspension_reason === 'disattivato' 
                    ? ' è attualmente disattivato'
                    : (
                      <>
                        {' non è disponibile'}
                        {getReasonLabel(suspendedCatDialog.suspension_reason) && 
                          suspendedCatDialog.suspension_reason !== 'disattivato'
                          ? ` per ${getReasonLabel(suspendedCatDialog.suspension_reason)}`
                          : ''
                        }
                        {suspendedCatDialog.suspension_end_date && 
                          ` fino al ${formatDate(suspendedCatDialog.suspension_end_date)}`
                        }
                      </>
                    )
                  }.
                  <br /><br />
                  Vuoi assegnarlo comunque?
                </>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Annulla</AlertDialogCancel>
            <AlertDialogAction 
              onClick={handleConfirmSuspendedCat}
              className="bg-amber-600 hover:bg-amber-700"
            >
              Assegna comunque
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
};

export default ApiMode;
