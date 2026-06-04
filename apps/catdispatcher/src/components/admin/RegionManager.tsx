import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';
import { Map as MapIcon, RefreshCw, CheckCircle2, XCircle } from 'lucide-react';
import { Separator } from '@/components/ui/separator';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';

interface Region {
  id: string;
  name: string;
  is_active: boolean;
  created_at: string | null;
  commune_count?: number;
}

const RegionManager = () => {
  const queryClient = useQueryClient();
  const [isUpdating, setIsUpdating] = useState<string | null>(null);

  // Fetch regions with commune counts
  const { data: regions, isLoading, refetch } = useQuery({
    queryKey: ['regions-admin'],
    queryFn: async () => {
      // Fetch regions
      const { data: regionsData, error: regionsError } = await supabase
        .from('regions')
        .select('id, name, is_active, created_at')
        .order('name');

      if (regionsError) throw regionsError;

      // Fetch commune counts per region
      const { data: communeCounts, error: countError } = await supabase
        .from('communes')
        .select('regione')
        .not('regione', 'is', null);

      if (countError) {
        console.error('Error fetching commune counts:', countError);
      }

      // Count communes per region
      const countMap = new Map<string, number>();
      (communeCounts || []).forEach((c: { regione: string | null }) => {
        if (c.regione) {
          const normalized = c.regione.toUpperCase();
          countMap.set(normalized, (countMap.get(normalized) || 0) + 1);
        }
      });

      // Merge counts with regions
      return (regionsData || []).map(region => ({
        ...region,
        commune_count: countMap.get(region.name.toUpperCase()) || 0
      })) as Region[];
    },
    staleTime: 30000,
  });

  // Toggle region active state
  const toggleMutation = useMutation({
    mutationFn: async ({ regionId, isActive }: { regionId: string; isActive: boolean }) => {
      const { error } = await supabase
        .from('regions')
        .update({ is_active: isActive })
        .eq('id', regionId);
      
      if (error) throw error;
      return { regionId, isActive };
    },
    onMutate: ({ regionId }) => {
      setIsUpdating(regionId);
    },
    onSuccess: ({ isActive }, { regionId }) => {
      const region = regions?.find(r => r.id === regionId);
      toast.success(`${region?.name || 'Regione'} ${isActive ? 'attivata' : 'disattivata'}`);
      queryClient.invalidateQueries({ queryKey: ['regions-admin'] });
      // Invalidate map data cache so it picks up the change
      localStorage.removeItem('map_data_cache');
      localStorage.removeItem('map_data_cache_version');
    },
    onError: (error: any) => {
      toast.error(`Errore: ${error.message}`);
    },
    onSettled: () => {
      setIsUpdating(null);
    }
  });

  // Activate all regions
  const activateAllMutation = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from('regions')
        .update({ is_active: true })
        .neq('id', '00000000-0000-0000-0000-000000000000');
      
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Tutte le regioni attivate');
      queryClient.invalidateQueries({ queryKey: ['regions-admin'] });
      localStorage.removeItem('map_data_cache');
      localStorage.removeItem('map_data_cache_version');
    },
    onError: (error: any) => {
      toast.error(`Errore: ${error.message}`);
    }
  });

  // Deactivate all regions
  const deactivateAllMutation = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from('regions')
        .update({ is_active: false })
        .neq('id', '00000000-0000-0000-0000-000000000000');
      
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Tutte le regioni disattivate');
      queryClient.invalidateQueries({ queryKey: ['regions-admin'] });
      localStorage.removeItem('map_data_cache');
      localStorage.removeItem('map_data_cache_version');
    },
    onError: (error: any) => {
      toast.error(`Errore: ${error.message}`);
    }
  });

  const activeCount = regions?.filter(r => r.is_active).length || 0;
  const totalCommunes = regions?.reduce((sum, r) => sum + (r.commune_count || 0), 0) || 0;
  const activeCommunes = regions?.filter(r => r.is_active).reduce((sum, r) => sum + (r.commune_count || 0), 0) || 0;

  if (isLoading) {
    return (
      <Card className="p-6">
        <div className="flex items-center justify-center py-8">
          <RefreshCw className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-4 space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <MapIcon className="h-5 w-5 text-primary" />
          <h3 className="font-medium">Gestione Regioni</h3>
        </div>
        <div className="flex items-center gap-2">
          <Badge variant={activeCount > 0 ? 'default' : 'secondary'}>
            {activeCount}/{regions?.length || 0} attive
          </Badge>
          <Badge variant="outline">
            {activeCommunes.toLocaleString()}/{totalCommunes.toLocaleString()} comuni
          </Badge>
        </div>
      </div>

      <p className="text-sm text-muted-foreground">
        Attiva solo le regioni necessarie per ridurre i tempi di caricamento della mappa.
        Solo i comuni delle regioni attive verranno caricati.
      </p>

      <Separator />

      <div className="flex gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={() => activateAllMutation.mutate()}
          disabled={activateAllMutation.isPending || activeCount === regions?.length}
        >
          <CheckCircle2 className="h-4 w-4 mr-2" />
          Attiva Tutte
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={() => deactivateAllMutation.mutate()}
          disabled={deactivateAllMutation.isPending || activeCount === 0}
        >
          <XCircle className="h-4 w-4 mr-2" />
          Disattiva Tutte
        </Button>
        <Button
          variant="ghost"
          size="sm"
          onClick={() => refetch()}
          className="ml-auto"
        >
          <RefreshCw className="h-4 w-4 mr-2" />
          Aggiorna
        </Button>
      </div>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Regione</TableHead>
            <TableHead className="text-right">Comuni</TableHead>
            <TableHead className="text-center w-24">Attiva</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {regions?.map((region) => (
            <TableRow key={region.id} className={!region.is_active ? 'opacity-60' : ''}>
              <TableCell className="font-medium">
                {region.name}
              </TableCell>
              <TableCell className="text-right">
                <Badge variant="secondary">
                  {(region.commune_count || 0).toLocaleString()}
                </Badge>
              </TableCell>
              <TableCell className="text-center">
                <Switch
                  checked={region.is_active}
                  onCheckedChange={(checked) => {
                    toggleMutation.mutate({ regionId: region.id, isActive: checked });
                  }}
                  disabled={isUpdating === region.id}
                />
              </TableCell>
            </TableRow>
          ))}
          {(!regions || regions.length === 0) && (
            <TableRow>
              <TableCell colSpan={3} className="text-center text-muted-foreground py-8">
                Nessuna regione trovata. Importa prima i confini regionali.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>

      <div className="text-xs text-muted-foreground p-3 bg-muted/50 rounded-lg">
        <strong>Nota:</strong> Dopo aver modificato le regioni attive, 
        la cache della mappa verrà invalidata automaticamente. 
        Al prossimo caricamento verranno scaricati solo i comuni delle regioni attive.
      </div>
    </Card>
  );
};

export default RegionManager;
