import { Badge } from '@/components/ui/badge';
import { MapPin, Building2, Loader2, AlertTriangle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { normalizeText, getProvinceName } from '@/lib/textUtils';
import { useCommuneDetails } from '@/hooks/useCommuneDetails';

interface CATBottomBarProps {
  communeId: string | null;
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

const CATBottomBar = ({ communeId, onCatSelect }: CATBottomBarProps) => {
  const { data: details, isLoading: detailsLoading } = useCommuneDetails(communeId);
  const commune = details?.commune ?? null;
  const catAssociations = details?.catAssociations ?? [];
  const suspensions = (details?.suspensions ?? []) as Suspension[];
  const communeLoading = detailsLoading;
  const catsLoading = detailsLoading;

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

  const isNeighborhood = !!commune?.quartiere;
  const isLoading = communeLoading || catsLoading;

  return (
    <Card className="absolute bottom-0 left-0 right-0 z-30 bg-card/95 backdrop-blur-md border-t-2 rounded-none">
      <div className="container mx-auto px-6 py-6">
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-primary mr-2" />
            <span className="text-sm text-muted-foreground">Caricamento dati...</span>
          </div>
        ) : !commune ? (
          <div className="text-center py-8">
            <p className="text-sm text-muted-foreground">
              Inserisci un indirizzo per visualizzare i CAT disponibili
            </p>
          </div>
        ) : (
          <div className="space-y-4">
            {/* Location Info - Header */}
            <div className="flex items-center gap-4 pb-3 border-b border-border">
              {isNeighborhood ? (
                <MapPin className="h-6 w-6 text-primary flex-shrink-0" />
              ) : (
                <Building2 className="h-6 w-6 text-primary flex-shrink-0" />
              )}
              <div className="flex-1">
                <div className="flex items-baseline gap-3">
                  <h3 className="text-lg font-bold text-foreground">
                    {normalizeText(isNeighborhood ? commune.quartiere : commune.comune)}
                  </h3>
                  {commune.alias && (
                    <span className="text-sm text-muted-foreground italic">
                      {String(commune.alias)}
                    </span>
                  )}
                  <Badge variant="outline" className="text-xs">
                    {isNeighborhood ? 'Quartiere' : 'Comune'}
                  </Badge>
                </div>
                <div className="flex items-center gap-4 mt-1">
                  {isNeighborhood && (
                    <span className="text-sm text-muted-foreground">
                      {normalizeText(commune.comune)}
                    </span>
                  )}
                  <span className="text-sm text-muted-foreground">
                    {getProvinceName(commune.provincia)}
                  </span>
                  <span className="text-sm text-muted-foreground">
                    {normalizeText(commune.regione)}
                  </span>
                </div>
              </div>
            </div>

            {/* CAT Selection - Grid Layout */}
            <div>
              <div className="flex items-center justify-between mb-3">
                <h4 className="text-sm font-semibold text-foreground uppercase tracking-wide">
                  CAT Disponibili
                </h4>
                <Badge variant="secondary" className="text-xs">
                  {catAssociations?.length || 0} CAT
                </Badge>
              </div>
              
              {catAssociations && catAssociations.length > 0 ? (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
                  {catAssociations
                    .sort((a, b) => {
                      if (a.is_primary !== b.is_primary) {
                        return a.is_primary ? -1 : 1;
                      }
                      return a.cats.name.localeCompare(b.cats.name);
                    })
                    .map((assoc) => {
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
                        <Button
                          key={assoc.cats.id}
                          onClick={() => {
                            console.log('🎯 CAT selected:', assoc.cats, 'suspended:', isSuspended, 'disabled:', isDisabled);
                            if (onCatSelect) {
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
                          variant="outline"
                          className={`p-4 h-auto border-l-4 hover:bg-muted/70 hover:scale-[1.02] transition-all group ${isSuspended ? 'opacity-70' : ''}`}
                          style={{ borderLeftColor: assoc.cats.color_hex }}
                        >
                          <div className="w-full space-y-2">
                            <div className="flex items-start justify-between">
                              <div className="text-left flex-1">
                                <p className="font-bold text-foreground text-base group-hover:text-primary transition-colors">
                                  {assoc.cats.name}
                                </p>
                              </div>
                              {isSuspended && (
                                <Badge variant="outline" className="text-xs text-amber-600 border-amber-400 ml-2">
                                  Sospeso
                                </Badge>
                              )}
                            </div>
                            {isSuspended && (
                              <div className="flex items-center gap-1 text-left">
                                <AlertTriangle className="h-3 w-3 text-amber-500" />
                                <span className="text-xs text-amber-600">
                                  {isDisabled 
                                    ? 'Attualmente disattivato'
                                    : `Non disponibile${reasonLabel ? ` per ${reasonLabel}` : ''}${suspension?.end_date ? ` fino al ${formatDate(suspension.end_date)}` : ''}`
                                  }
                                </span>
                              </div>
                            )}
                            <div className="flex gap-1.5 flex-wrap">
                              {assoc.is_primary && (
                                <Badge variant="default" className="text-xs">
                                  Primario
                                </Badge>
                              )}
                              {showBadge && (
                                <Badge variant={badgeVariant} className="text-xs">
                                  {badgeText}
                                </Badge>
                              )}
                            </div>
                            {isSuspended && (
                              <p className="text-xs text-amber-600 text-left">Clicca per assegnare comunque</p>
                            )}
                          </div>
                        </Button>
                      );
                    })}
                </div>
              ) : (
                <div className="p-6 bg-muted/30 rounded-lg text-center">
                  <p className="text-sm text-muted-foreground">Nessun CAT assegnato a questa località</p>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </Card>
  );
};

export default CATBottomBar;
