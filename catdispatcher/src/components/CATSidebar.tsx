import { Badge } from '@/components/ui/badge';
import { MapPin, Building2, Loader2, AlertTriangle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { normalizeText, getProvinceName } from '@/lib/textUtils';
import { useCommuneDetails } from '@/hooks/useCommuneDetails';
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
} from '@/components/ui/sidebar';

interface CATSidebarProps {
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

const CATSidebar = ({ communeId, onCatSelect }: CATSidebarProps) => {
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
    <Sidebar className="w-80 border-l">
      <SidebarHeader className="border-b p-4">
        <div className="flex items-center gap-2">
          {isNeighborhood ? (
            <MapPin className="h-5 w-5 text-primary flex-shrink-0" />
          ) : (
            <Building2 className="h-5 w-5 text-primary flex-shrink-0" />
          )}
          <div className="flex-1 min-w-0">
            <h2 className="text-lg font-bold text-foreground truncate">
              CAT DISPATCHER
            </h2>
            <p className="text-xs text-muted-foreground">
              Seleziona un CAT
            </p>
          </div>
        </div>
      </SidebarHeader>

      <SidebarContent>
        {isLoading ? (
          <div className="flex items-center justify-center p-8">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
          </div>
        ) : !commune ? (
          <div className="p-6 text-center">
            <p className="text-sm text-muted-foreground">
              Inserisci un indirizzo per visualizzare i CAT disponibili
            </p>
          </div>
        ) : (
          <>
            {/* Location Info */}
            <SidebarGroup>
              <SidebarGroupLabel>Località</SidebarGroupLabel>
              <SidebarGroupContent className="space-y-3 px-4">
                <div className="space-y-2">
                  <div className="flex items-center gap-2">
                    {isNeighborhood ? (
                      <MapPin className="h-4 w-4 text-muted-foreground" />
                    ) : (
                      <Building2 className="h-4 w-4 text-muted-foreground" />
                    )}
                    <div>
                      <p className="text-xs text-muted-foreground">
                        {isNeighborhood ? 'Quartiere' : 'Comune'}
                      </p>
                      <p className="text-sm font-semibold text-foreground">
                        {normalizeText(isNeighborhood ? commune.quartiere : commune.comune)}
                      </p>
                      {commune.alias && (
                        <p className="text-xs text-muted-foreground italic">
                          {String(commune.alias)}
                        </p>
                      )}
                    </div>
                  </div>
                  
                  {isNeighborhood && (
                    <div className="pl-6">
                      <p className="text-xs text-muted-foreground">Comune</p>
                      <p className="text-sm font-medium text-foreground">{normalizeText(commune.comune)}</p>
                    </div>
                  )}
                  
                  <div className="grid grid-cols-2 gap-2 pt-2">
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
              </SidebarGroupContent>
            </SidebarGroup>

            <Separator />

            {/* CAT Selection */}
            <SidebarGroup>
              <SidebarGroupLabel>CAT Disponibili</SidebarGroupLabel>
              <SidebarGroupContent className="space-y-2 px-4">
                {catAssociations && catAssociations.length > 0 ? (
                  <div className="space-y-2">
                    {catAssociations
                      .sort((a, b) => {
                        // Prima ordina per is_primary
                        if (a.is_primary !== b.is_primary) {
                          return a.is_primary ? -1 : 1;
                        }
                        // Poi ordina per nome
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
                            className={`w-full p-4 h-auto border-l-4 hover:bg-muted/70 hover:scale-[1.02] transition-all text-left justify-start ${isSuspended ? 'opacity-70' : ''}`}
                            style={{ borderLeftColor: assoc.cats.color_hex }}
                          >
                            <div className="flex flex-col w-full gap-1">
                              <div className="flex items-start justify-between w-full">
                                <div className="flex-1">
                                  <p className="font-semibold text-foreground">{assoc.cats.name}</p>
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
                              {isSuspended && (
                                <div className="flex items-center gap-1">
                                  <AlertTriangle className="h-3 w-3 text-amber-500" />
                                  <span className="text-xs text-amber-600">
                                    {isDisabled 
                                      ? 'Attualmente disattivato'
                                      : `Non disponibile${reasonLabel ? ` per ${reasonLabel}` : ''}${suspension?.end_date ? ` fino al ${formatDate(suspension.end_date)}` : ''}`
                                    }
                                  </span>
                                </div>
                              )}
                              <div className="flex gap-1 mt-1">
                                {assoc.is_primary && (
                                  <Badge variant="default" className="text-xs">
                                    Primario
                                  </Badge>
                                )}
                              </div>
                              {isSuspended && (
                                <p className="text-xs text-amber-600 mt-1">Clicca per assegnare comunque</p>
                              )}
                            </div>
                          </Button>
                        );
                      })}
                  </div>
                ) : (
                  <div className="p-4 bg-muted/30 rounded-lg text-center">
                    <p className="text-sm text-muted-foreground">Nessun CAT assegnato</p>
                  </div>
                )}
              </SidebarGroupContent>
            </SidebarGroup>
          </>
        )}
      </SidebarContent>
    </Sidebar>
  );
};

export default CATSidebar;
