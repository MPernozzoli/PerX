import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Input } from '@/components/ui/input';
import { 
  MapPin, 
  Wrench, 
  Tag, 
  Map as MapIcon,
  Layers,
  CheckCircle2,
  Search
} from 'lucide-react';
import type { InterventionMode, CAT, CATAssignment } from '@/screens/GISEditor';

interface GISInspectorProps {
  cats: CAT[];
  assignments: CATAssignment[];
  selectedCatId: string | null;
  onSelectCat: (catId: string | null) => void;
  currentMode: InterventionMode;
  onModeChange: (mode: InterventionMode) => void;
  showLabels: boolean;
  onShowLabelsChange: (show: boolean) => void;
  showProvinceBorders: boolean;
  onShowProvinceBordersChange: (show: boolean) => void;
  showRegionBorders: boolean;
  onShowRegionBordersChange: (show: boolean) => void;
  hasProvinceGeoms: boolean;
  hasRegionGeoms: boolean;
}

const GISInspector = ({
  cats,
  assignments,
  selectedCatId,
  onSelectCat,
  currentMode,
  onModeChange,
  showLabels,
  onShowLabelsChange,
  showProvinceBorders,
  onShowProvinceBordersChange,
  showRegionBorders,
  onShowRegionBordersChange,
  hasProvinceGeoms,
  hasRegionGeoms
}: GISInspectorProps) => {
  const [catSearch, setCatSearch] = useState('');

  // Count assignments per CAT for current mode
  const catCounts = useMemo(() => {
    const counts = new Map<string, number>();
    assignments.forEach(a => {
      counts.set(a.cat_id, (counts.get(a.cat_id) || 0) + 1);
    });
    return counts;
  }, [assignments]);

  // Filter cats by search
  const filteredCats = useMemo(() => {
    if (!catSearch.trim()) return cats;
    const search = catSearch.toLowerCase();
    return cats.filter(cat => 
      cat.name.toLowerCase().includes(search)
    );
  }, [cats, catSearch]);

  // Count total assigned and unassigned
  const totalAssigned = useMemo(() => {
    const uniqueCommunes = new Set(assignments.map(a => a.commune_id));
    return uniqueCommunes.size;
  }, [assignments]);

  return (
    <div className="h-full flex flex-col">
      {/* Mode Selector */}
      <div className="p-4 border-b">
        <Label className="text-xs text-muted-foreground mb-2 block">Modalità</Label>
        <div className="grid grid-cols-2 gap-2">
          <Button
            variant={currentMode === 'sopralluogo' ? 'default' : 'outline'}
            size="sm"
            onClick={() => onModeChange('sopralluogo')}
            className="w-full"
          >
            <MapPin className="h-4 w-4 mr-2" />
            Sopralluogo
          </Button>
          <Button
            variant={currentMode === 'rfs' ? 'default' : 'outline'}
            size="sm"
            onClick={() => onModeChange('rfs')}
            className="w-full"
          >
            <Wrench className="h-4 w-4 mr-2" />
            RFS
          </Button>
        </div>
      </div>

      {/* CAT Selection */}
      <div className="p-4 border-b flex flex-col">
        <div className="flex items-center justify-between mb-2">
          <Label className="text-xs text-muted-foreground">Seleziona CAT</Label>
          {selectedCatId && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => onSelectCat(null)}
              className="h-6 px-2 text-xs"
            >
              Deseleziona
            </Button>
          )}
        </div>
        
        {/* Search input */}
        <div className="relative mb-2">
          <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
          <Input
            placeholder="Cerca CAT..."
            value={catSearch}
            onChange={(e) => setCatSearch(e.target.value)}
            className="h-8 pl-7 text-sm"
          />
        </div>

        <ScrollArea className="h-56">
          <div className="space-y-1">
            {filteredCats.map(cat => {
              const count = catCounts.get(cat.id) || 0;
              const isSelected = selectedCatId === cat.id;
              
              return (
                <button
                  key={cat.id}
                  onClick={() => onSelectCat(isSelected ? null : cat.id)}
                  className={`
                    w-full flex items-center gap-2 p-2 rounded-md transition-all text-left
                    ${isSelected 
                      ? 'bg-primary/10 ring-2 ring-primary ring-inset' 
                      : 'hover:bg-accent'
                    }
                  `}
                >
                  <div
                    className="w-4 h-4 rounded-full flex-shrink-0"
                    style={{ backgroundColor: cat.color_hex || '#888' }}
                  />
                  <div className="flex-1 min-w-0">
                    <div className="font-medium text-sm truncate">{cat.name}</div>
                  </div>
                  <Badge variant="secondary" className="text-xs flex-shrink-0">
                    {count}
                  </Badge>
                  {isSelected && (
                    <CheckCircle2 className="h-4 w-4 text-primary flex-shrink-0" />
                  )}
                </button>
              );
            })}
            {filteredCats.length === 0 && (
              <p className="text-xs text-muted-foreground text-center py-4">
                Nessun CAT trovato
              </p>
            )}
          </div>
        </ScrollArea>
      </div>

      {/* Overlay Options */}
      <div className="p-4 border-b space-y-4">
        <Label className="text-xs text-muted-foreground">Overlay</Label>
        
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Tag className="h-4 w-4 text-muted-foreground" />
            <span className="text-sm">Nomi comuni</span>
          </div>
          <Switch
            checked={showLabels}
            onCheckedChange={onShowLabelsChange}
          />
        </div>

        <div className={`flex items-center justify-between ${!hasProvinceGeoms ? 'opacity-50' : ''}`}>
          <div className="flex items-center gap-2">
            <MapIcon className="h-4 w-4 text-muted-foreground" />
            <div className="flex flex-col">
              <span className="text-sm">Confini province</span>
              {!hasProvinceGeoms && (
                <span className="text-xs text-muted-foreground">Non caricati</span>
              )}
            </div>
          </div>
          <Switch
            checked={showProvinceBorders}
            onCheckedChange={onShowProvinceBordersChange}
            disabled={!hasProvinceGeoms}
          />
        </div>

        <div className={`flex items-center justify-between ${!hasRegionGeoms ? 'opacity-50' : ''}`}>
          <div className="flex items-center gap-2">
            <Layers className="h-4 w-4 text-muted-foreground" />
            <div className="flex flex-col">
              <span className="text-sm">Confini regioni</span>
              {!hasRegionGeoms && (
                <span className="text-xs text-muted-foreground">Non caricati</span>
              )}
            </div>
          </div>
          <Switch
            checked={showRegionBorders}
            onCheckedChange={onShowRegionBordersChange}
            disabled={!hasRegionGeoms}
          />
        </div>
      </div>

      {/* Statistics */}
      <div className="p-4 mt-auto">
        <Separator className="mb-4" />
        <div className="space-y-2 text-sm">
          <div className="flex justify-between">
            <span className="text-muted-foreground">Comuni assegnati</span>
            <span className="font-medium">{totalAssigned}</span>
          </div>
          {selectedCatId && (
            <div className="flex justify-between">
              <span className="text-muted-foreground">CAT selezionato</span>
              <span className="font-medium">{catCounts.get(selectedCatId) || 0}</span>
            </div>
          )}
        </div>
        
        {!selectedCatId && (
          <p className="text-xs text-muted-foreground mt-4 text-center">
            Seleziona un CAT per iniziare ad assegnare i comuni
          </p>
        )}
      </div>
    </div>
  );
};

export default GISInspector;
