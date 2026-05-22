import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { X, MapPin, Building2, Info, Crosshair, AlertTriangle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { normalizeText, getProvinceName } from '@/lib/textUtils';
import { useCommuneDetails } from '@/hooks/useCommuneDetails';

interface CommunePopupProps {
  communeId: string;
  onClose: () => void;
  onNavigate: (communeId: string) => void;
  onCenterOnCommune?: (communeId: string) => void;
  apiMode?: boolean;
  onCatSelect?: (catData: { 
    id: string; 
    name: string; 
    color: string;
    suspended?: boolean;
    suspension_end_date?: string;
    suspension_reason?: string;
  }) => void;
}

interface Suspension {
  cat_id: string;
  start_date: string;
  end_date: string;
  reason: string;
}

const CommunePopup = ({ communeId, onClose, onNavigate, onCenterOnCommune, apiMode = false, onCatSelect }: CommunePopupProps) => {
  const { data: details, isLoading: detailsLoading } = useCommuneDetails(communeId);
  const commune = details?.commune ?? null;
  const catAssociations = details?.catAssociations ?? [];
  const suspensions = (details?.suspensions ?? []) as Suspension[];
  const parentCommune = details?.parentCommune ?? null;
  const neighborhoods = details?.neighborhoods ?? [];

  // Helper to check if CAT is suspended
  const getCatSuspension = (catId: string): Suspension | undefined => {
    return suspensions?.find(s => s.cat_id === catId);
  };

  const formatDate = (dateStr: string) => {
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

  if (!commune) return null;

  const isNeighborhood = !!commune.quartiere;

  const handleCenterClick = () => {
    if (onCenterOnCommune) {
      onCenterOnCommune(communeId);
    }
  };

  return (
    <Card className="absolute top-20 right-4 w-96 max-h-[calc(100vh-6rem)] overflow-y-auto shadow-xl z-10 bg-card backdrop-blur-md border-2 animate-in fade-in-0 slide-in-from-right-2 duration-300">
      <div className="sticky top-0 bg-card backdrop-blur-md border-b border-border z-10 px-4 py-3">
        <div className="flex items-start justify-between gap-2">
          <div className="flex items-center gap-2 flex-1 min-w-0">
            {isNeighborhood ? (
              <MapPin className="h-5 w-5 text-primary flex-shrink-0" />
            ) : (
              <Building2 className="h-5 w-5 text-primary flex-shrink-0" />
            )}
            <div className="flex-1 min-w-0">
              <h2 className="text-lg font-bold text-foreground truncate">
                {normalizeText(isNeighborhood ? commune.quartiere : commune.comune)}
              </h2>
              {commune.alias && (
                <p className="text-sm text-muted-foreground italic">
                  {String(commune.alias)}
                </p>
              )}
              <p className="text-xs text-muted-foreground">
                {isNeighborhood ? 'Quartiere' : 'Comune'}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-1 flex-shrink-0">
            <Button
              variant="ghost"
              size="icon"
              onClick={handleCenterClick}
              className="h-8 w-8 hover:bg-primary/10 transition-all"
              title="Centra sulla mappa"
            >
              <Crosshair className="h-4 w-4 text-primary" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              onClick={onClose}
              className="h-8 w-8"
            >
              <X className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>

      <div className="p-4 space-y-4">
        {/* Location Info */}
        <div className="space-y-2">
          {isNeighborhood && parentCommune && (
            <div className="flex items-center justify-between py-2 px-3 bg-muted/50 rounded-lg">
              <div>
                <p className="text-xs text-muted-foreground">Comune</p>
                <button
                  onClick={() => onNavigate(parentCommune.id)}
                  className="text-sm font-medium text-primary hover:underline text-left"
                >
                  {normalizeText(commune.comune)}
                </button>
              </div>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onNavigate(parentCommune.id)}
                className="h-8"
              >
                Vedi
              </Button>
            </div>
          )}
          
          <div className="grid grid-cols-2 gap-2">
            <div className="py-2 px-3 bg-muted/30 rounded-lg">
              <p className="text-xs text-muted-foreground mb-1">Provincia</p>
              <p className="text-sm font-medium text-foreground">{getProvinceName(commune.provincia) || 'N/D'}</p>
            </div>
            <div className="py-2 px-3 bg-muted/30 rounded-lg">
              <p className="text-xs text-muted-foreground mb-1">Regione</p>
              <p className="text-sm font-medium text-foreground">{normalizeText(commune.regione) || 'N/D'}</p>
            </div>
          </div>
        </div>

        <Separator />

        {/* CAT Assignment */}
        <div>
          <h3 className="text-sm font-semibold mb-3 text-foreground">
            CAT:
          </h3>
          
          {catAssociations && catAssociations.length > 0 ? (
            <div className="space-y-2">
              {catAssociations
                .sort((a, b) => {
                  // Prima ordina per is_primary (TRUE prima di FALSE)
                  if (a.is_primary !== b.is_primary) {
                    return a.is_primary ? -1 : 1;
                  }
                  // Poi ordina per nome
                  return a.cats.name.localeCompare(b.cats.name);
                })
                .map((assoc) => {
                  // Get intervention type from database
                  const interventionType = assoc.intervention_type;
                  const showBadge = interventionType !== 'both';
                  const badgeText = interventionType === 'sopralluogo' ? 'Sopralluogo' : 'RFS';
                  const badgeVariant = interventionType === 'sopralluogo' ? 'default' : 'secondary';
                  
                  // Check suspension or disabled
                  const suspension = getCatSuspension(assoc.cats.id);
                  const isDisabled = assoc.cats.active === false;
                  const isSuspended = !!suspension || isDisabled;
                  const reasonLabel = isDisabled ? 'disattivato' : (suspension ? getReasonLabel(suspension.reason) : null);
                  
                  return (
                    <button
                      key={assoc.cats.id}
                      onClick={() => {
                        if (apiMode && onCatSelect) {
                          onCatSelect({
                            id: assoc.cats.id,
                            name: assoc.cats.name,
                            color: assoc.cats.color_hex,
                            suspended: isSuspended,
                            suspension_end_date: isDisabled ? undefined : suspension?.end_date,
                            suspension_reason: isDisabled ? 'disattivato' : suspension?.reason
                          });
                        }
                      }}
                      disabled={!apiMode}
                      className={`w-full p-3 bg-muted/50 rounded-lg border-l-4 text-left transition-all ${
                        apiMode ? 'hover:bg-muted/70 cursor-pointer hover:scale-[1.02]' : ''
                      } ${isSuspended ? 'opacity-70' : ''}`}
                      style={{ borderLeftColor: assoc.cats.color_hex }}
                    >
                      <div className="flex items-start justify-between flex-wrap gap-1">
                        <div>
                          <p className="font-semibold text-foreground">{assoc.cats.name}</p>
                          {isSuspended && (
                            <div className="flex items-center gap-1 mt-1">
                              <AlertTriangle className="h-3 w-3 text-amber-500" />
                              <span className="text-xs text-amber-600">
                                {isDisabled 
                                  ? 'Attualmente disattivato'
                                  : `Non disponibile${reasonLabel ? ` per ${reasonLabel}` : ''}${suspension?.end_date ? ` fino al ${formatDate(suspension.end_date)}` : ''}`
                                }
                              </span>
                            </div>
                          )}
                        </div>
                        <div className="flex gap-1 flex-wrap">
                          {isSuspended && (
                            <Badge variant="outline" className="text-xs text-amber-600 border-amber-400">
                              Sospeso
                            </Badge>
                          )}
                          {showBadge && (
                            <Badge variant={badgeVariant} className="text-xs">
                              {badgeText}
                            </Badge>
                          )}
                        </div>
                      </div>
                      {apiMode && (
                        <p className="text-xs text-primary mt-2">
                          {isSuspended ? 'Clicca per assegnare comunque' : 'Clicca per selezionare'}
                        </p>
                      )}
                    </button>
                  );
                })}
            </div>
          ) : (
            <div className="p-3 bg-muted/30 rounded-lg text-center">
              <p className="text-sm text-muted-foreground">Nessun CAT assegnato</p>
            </div>
          )}
        </div>

        {/* Neighborhoods for communes */}
        {!isNeighborhood && neighborhoods && neighborhoods.length > 0 && (
          <>
            <Separator />
            <div>
              <div className="flex items-center gap-2 mb-3">
                <Info className="h-4 w-4 text-primary" />
                <h3 className="text-sm font-semibold text-foreground">
                  Quartieri ({neighborhoods.length})
                </h3>
              </div>
              <div className="bg-accent/20 border border-accent/30 rounded-lg p-3 mb-3">
                <p className="text-xs text-muted-foreground">
                  ⚠️ Questo comune ha quartieri. L'assegnazione CAT deve essere fatta sui singoli quartieri!
                </p>
              </div>
              <div className="space-y-2 max-h-40 overflow-y-auto">
                {neighborhoods.map((neighborhood) => (
                  <button
                    key={neighborhood.id}
                    onClick={() => onNavigate(neighborhood.id)}
                    className="w-full flex items-center justify-between p-2 bg-muted/30 hover:bg-muted/50 rounded-lg transition-colors text-left group"
                  >
                    <div className="flex items-center gap-2">
                      <MapPin className="h-3 w-3 text-muted-foreground" />
                      <span className="text-sm font-medium text-foreground group-hover:text-primary transition-colors">
                        {normalizeText(neighborhood.quartiere)}
                      </span>
                    </div>
                    <Badge variant="secondary" className="text-xs">
                      Vedi
                    </Badge>
                  </button>
                ))}
              </div>
            </div>
          </>
        )}
      </div>
    </Card>
  );
};

export default CommunePopup;
