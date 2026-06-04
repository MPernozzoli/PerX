import { useState, useEffect } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { supabase } from '@/integrations/supabase/client';
import { Globe, Check, X } from 'lucide-react';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';

interface RegionFilterProps {
  selectedRegions: string[];
  onRegionsChange: (regions: string[]) => void;
}

export const RegionFilter = ({ selectedRegions, onRegionsChange }: RegionFilterProps) => {
  const [availableRegions, setAvailableRegions] = useState<string[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    loadAvailableRegions();
  }, []);

  const loadAvailableRegions = async () => {
    try {
      setIsLoading(true);
      
      // Get list of backup files to extract regions
      const { data: files, error } = await supabase.storage
        .from('geojson-backups')
        .list('', {
          sortBy: { column: 'created_at', order: 'desc' }
        });

      if (error || !files) {
        console.error('Failed to load regions:', error);
        return;
      }

      // Extract unique regions from filenames
      const regions = new Set<string>();
      for (const file of files) {
        const match = file.name.match(/geojson-([a-z-]+)-\d{4}/i);
        if (match) {
          regions.add(match[1]);
        }
      }

      const sortedRegions = Array.from(regions).sort();
      setAvailableRegions(sortedRegions);
      
      // If no regions selected yet, select all by default
      if (selectedRegions.length === 0) {
        onRegionsChange(sortedRegions);
      }
    } catch (error) {
      console.error('Error loading regions:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const toggleRegion = (region: string) => {
    if (selectedRegions.includes(region)) {
      onRegionsChange(selectedRegions.filter(r => r !== region));
    } else {
      onRegionsChange([...selectedRegions, region]);
    }
  };

  const selectAll = () => {
    onRegionsChange(availableRegions);
  };

  const deselectAll = () => {
    onRegionsChange([]);
  };

  const formatRegionName = (region: string) => {
    return region
      .split('-')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
  };

  if (isLoading) {
    return (
      <Card className="mb-4">
        <CardContent className="py-3">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Globe className="h-4 w-4 animate-spin" />
            Caricamento regioni...
          </div>
        </CardContent>
      </Card>
    );
  }

  if (availableRegions.length === 0) {
    return null;
  }

  return (
    <Card className="mb-4">
      <Collapsible open={isOpen} onOpenChange={setIsOpen}>
        <CollapsibleTrigger asChild>
          <CardContent className="py-3 cursor-pointer hover:bg-muted/50 transition-colors">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Globe className="h-4 w-4" />
                <span className="text-sm font-medium">
                  Filtro Regioni
                </span>
                <Badge variant="secondary" className="ml-2">
                  {selectedRegions.length}/{availableRegions.length}
                </Badge>
              </div>
              <div className="flex items-center gap-2">
                {selectedRegions.length > 0 && selectedRegions.length < availableRegions.length && (
                  <Badge variant="outline" className="text-xs">
                    Filtrato
                  </Badge>
                )}
              </div>
            </div>
          </CardContent>
        </CollapsibleTrigger>
        
        <CollapsibleContent>
          <CardContent className="pt-0 pb-4">
            <div className="space-y-3">
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={selectAll}
                  className="flex-1"
                >
                  <Check className="h-3 w-3 mr-1" />
                  Tutte
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={deselectAll}
                  className="flex-1"
                >
                  <X className="h-3 w-3 mr-1" />
                  Nessuna
                </Button>
              </div>
              
              <div className="grid grid-cols-2 gap-2">
                {availableRegions.map(region => (
                  <div
                    key={region}
                    className="flex items-center space-x-2 p-2 rounded-md hover:bg-muted/50 cursor-pointer"
                    onClick={() => toggleRegion(region)}
                  >
                    <Checkbox
                      id={`region-${region}`}
                      checked={selectedRegions.includes(region)}
                      onCheckedChange={() => toggleRegion(region)}
                    />
                    <label
                      htmlFor={`region-${region}`}
                      className="text-sm cursor-pointer flex-1"
                    >
                      {formatRegionName(region)}
                    </label>
                  </div>
                ))}
              </div>
            </div>
          </CardContent>
        </CollapsibleContent>
      </Collapsible>
    </Card>
  );
};
