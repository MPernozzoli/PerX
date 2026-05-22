import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { ChevronDown, ChevronUp, AlertTriangle } from 'lucide-react';
import { useState, useEffect } from 'react';

interface CatData {
  id: string;
  name: string;
  color_hex: string;
  totalCount: number;
  visibleCount: number;
}

interface MapLegendProps {
  cats: any[];
  activeCatIds: Set<string> | undefined;
  onToggleCat: (catId: string) => void;
  onCenterOnCat: (catId: string) => void;
  visibleCatCounts: Map<string, number>;
  suspendedCatIds?: string[];
}

const MapLegend = ({ cats, activeCatIds, onToggleCat, onCenterOnCat, visibleCatCounts, suspendedCatIds = [] }: MapLegendProps) => {
  const suspendedSet = new Set(suspendedCatIds);
  // Three states: 'collapsed', 'top3', 'expanded'
  const [viewState, setViewState] = useState<'collapsed' | 'top3' | 'expanded'>('top3');
  const [topCats, setTopCats] = useState<CatData[]>([]);
  const [allCatsData, setAllCatsData] = useState<CatData[]>([]);

  // Calculate top 3 CATs based on visible counts (excluding unassigned)
  useEffect(() => {
    if (!cats || cats.length === 0) return;

    const catsWithVisibleCounts: CatData[] = cats.map((cat) => ({
      id: cat.id,
      name: cat.name,
      color_hex: cat.color_hex,
      totalCount: 0, // We don't need total count anymore
      visibleCount: visibleCatCounts.get(cat.id) || 0
    }));

    // Sort by visible count and take top 3 (excluding unassigned from dynamic calculation)
    const sorted = [...catsWithVisibleCounts].sort((a, b) => b.visibleCount - a.visibleCount);
    setTopCats(sorted.slice(0, 3));

    // Add "Non assegnati" at the end, always
    const unassignedVisible = visibleCatCounts.get('unassigned') || 0;
    const unassignedCat: CatData = {
      id: 'unassigned',
      name: 'Non assegnati',
      color_hex: '#BBBBBB',
      totalCount: 0,
      visibleCount: unassignedVisible
    };

    // All cats: regular CATs + unassigned at the end
    setAllCatsData([...catsWithVisibleCounts, unassignedCat]);
  }, [cats, visibleCatCounts]);

  const handleCatClick = (catId: string) => {
    onToggleCat(catId);
  };

  const handleCatDoubleClick = (catId: string) => {
    onCenterOnCat(catId);
  };

  // Show only top 3 when in 'top3' state (no unassigned)
  // Show all + unassigned when expanded
  const unassignedCat = allCatsData.find(cat => cat.id === 'unassigned');
  const regularCats = allCatsData.filter(cat => cat.id !== 'unassigned');
  
  const catsToDisplay = viewState === 'expanded'
    ? [...regularCats, ...(unassignedCat ? [unassignedCat] : [])]
    : topCats;

  const handleChevronClick = () => {
    if (viewState === 'collapsed') {
      setViewState('top3');
    } else if (viewState === 'top3') {
      setViewState('collapsed');
    } else if (viewState === 'expanded') {
      setViewState('top3');
    }
  };

  if (viewState === 'collapsed') {
    return (
      <Card className="p-3 shadow-lg backdrop-blur-md bg-card w-64">
        <div className="flex items-center justify-between">
          <h3 className="font-semibold text-sm text-foreground">
            Filtri CAT
          </h3>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleChevronClick}
            className="h-6 px-2"
          >
            <ChevronDown className="h-4 w-4" />
          </Button>
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-3 shadow-lg backdrop-blur-md bg-card w-64">
      <div className="flex items-center justify-between mb-2">
        <h3 className="font-semibold text-sm text-foreground">
          Filtri CAT
        </h3>
        <Button
          variant="ghost"
          size="sm"
          onClick={handleChevronClick}
          className="h-6 px-2"
        >
          <ChevronUp className="h-4 w-4" />
        </Button>
      </div>
      
      
      <div className="space-y-1 max-h-[calc(100vh-200px)] overflow-y-auto">
        {catsToDisplay.map((cat) => {
          const isActive = activeCatIds ? activeCatIds.has(cat.id) : true;
          const isSuspended = suspendedSet.has(cat.id);
          
          return (
            <button
              key={cat.id}
              onClick={() => handleCatClick(cat.id)}
              onDoubleClick={() => handleCatDoubleClick(cat.id)}
              className={`w-full flex items-center gap-2 p-2 rounded-md transition-all text-left group ${
                isActive 
                  ? 'bg-primary/10 border border-primary/30' 
                  : 'bg-muted/30 opacity-50 hover:opacity-75'
              }`}
              title="Click per attivare/disattivare, Doppio click per centrare"
            >
              <div
                className={`w-3 h-3 rounded-sm flex-shrink-0 border transition-all ${
                  isActive ? 'border-primary' : 'border-border'
                }`}
                style={{ backgroundColor: isActive ? cat.color_hex : '#999' }}
              />
              <div className="flex-1 min-w-0">
                <div className={`font-medium text-xs truncate transition-colors flex items-center gap-1 ${
                  isActive ? 'text-foreground' : 'text-muted-foreground'
                }`}>
                  {cat.name}
                  {isSuspended && (
                    <AlertTriangle className="h-3 w-3 text-amber-500 flex-shrink-0" />
                  )}
                </div>
              </div>
              {isSuspended ? (
                <Badge 
                  variant="outline" 
                  className="text-[10px] px-1.5 py-0 text-amber-600 border-amber-400"
                >
                  Sospeso
                </Badge>
              ) : (
                <Badge 
                  variant={isActive ? "default" : "secondary"} 
                  className="text-[10px] px-1.5 py-0"
                >
                  {cat.visibleCount > 0 ? cat.visibleCount : '-'}
                </Badge>
              )}
            </button>
          );
        })}
        
        {catsToDisplay.length === 0 && (
          <p className="text-xs text-muted-foreground text-center py-3">
            Nessun CAT disponibile
          </p>
        )}
      </div>

      {viewState === 'top3' && topCats.length > 0 && regularCats.length > topCats.length && (
        <button
          onClick={() => setViewState('expanded')}
          className="w-full text-center mt-2 py-1 px-2 rounded-md hover:bg-secondary/50 transition-colors"
        >
          <p className="text-[10px] text-primary font-medium">
            +{regularCats.length - topCats.length} altri CAT
          </p>
        </button>
      )}
    </Card>
  );
};

export default MapLegend;
