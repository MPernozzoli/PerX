import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { toast } from 'sonner';
import { Trash2, Search, MapPin, Pencil, X, Star, Map, Wand2, ArrowUpDown, ArrowUp, ArrowDown } from 'lucide-react';
import { normalizeText, getProvinceName } from '@/lib/textUtils';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Separator } from '@/components/ui/separator';

interface EditingCommune {
  id: string;
  name: string;
  isQuartiere: boolean;
  hasQuartieri: boolean;
  useQuartieri: boolean;
}

interface CommuneManagerProps {
  isSiteAdmin?: boolean;
}

type SortColumn = 'comune' | 'cat' | 'provincia' | 'regione' | null;
type SortDirection = 'asc' | 'desc';

const CommuneManager = ({ isSiteAdmin = false }: CommuneManagerProps) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [editingCommune, setEditingCommune] = useState<EditingCommune | null>(null);
  const [catSearchSopralluogo, setCatSearchSopralluogo] = useState('');
  const [catSearchRFS, setCatSearchRFS] = useState('');
  const [sortColumn, setSortColumn] = useState<SortColumn>(null);
  const [sortDirection, setSortDirection] = useState<SortDirection>('asc');
  const queryClient = useQueryClient();

  // Fetch all CATs for the dropdown
  const { data: allCats } = useQuery({
    queryKey: ['cats-all'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('cats')
        .select('id, name, color_hex, active')
        .eq('active', true)
        .order('name');
      if (error) throw error;
      return data;
    }
  });

  // Fetch full assignments for the editing commune
  const { data: communeFullAssignments, refetch: refetchCommuneAssignments } = useQuery({
    queryKey: ['commune-assignments', editingCommune?.id],
    queryFn: async () => {
      if (!editingCommune?.id) return [];
      const { data, error } = await supabase
        .from('cat_commune')
        .select('id, cat_id, intervention_type, is_primary, cats(name, color_hex)')
        .eq('commune_id', editingCommune.id);
      if (error) throw error;
      return data || [];
    },
    enabled: !!editingCommune?.id
  });

  const { data: communes, isLoading } = useQuery({
    queryKey: ['communes-admin-paginated'],
    queryFn: async () => {
      const allCommunes = [];
      let page = 0;
      const pageSize = 1000;
      let hasMore = true;

      while (hasMore) {
        const { data, error } = await supabase
          .from('communes')
          .select('id, comune, alias, quartiere, provincia, regione, centroid_lat, centroid_lng, created_at, use_quartieri')
          .order('comune', { ascending: true })
          .order('quartiere', { ascending: true, nullsFirst: true })
          .range(page * pageSize, (page + 1) * pageSize - 1);
        
        if (error) throw error;
        
        if (data && data.length > 0) {
          allCommunes.push(...data);
          hasMore = data.length === pageSize;
          page++;
        } else {
          hasMore = false;
        }
      }
      
      console.log('Admin: Loaded communes:', allCommunes.length);
      return allCommunes;
    },
    staleTime: 5 * 60 * 1000,
  });

  const { data: catAssociations } = useQuery({
    queryKey: ['cat-associations-admin-paginated'],
    queryFn: async () => {
      const allAssociations = [];
      let page = 0;
      const pageSize = 1000;
      let hasMore = true;

      while (hasMore) {
        const { data, error } = await supabase
        .from('cat_commune')
        .select('commune_id, cat_id, is_primary, cats(name, color_hex)')
          .range(page * pageSize, (page + 1) * pageSize - 1);
        
        if (error) throw error;
        
        if (data && data.length > 0) {
          allAssociations.push(...data);
          hasMore = data.length === pageSize;
          page++;
        } else {
          hasMore = false;
        }
      }
      
      return allAssociations;
    },
    staleTime: 5 * 60 * 1000,
  });

  const deleteMutation = useMutation({
    mutationFn: async (communeId: string) => {
      const { error } = await supabase
        .from('communes')
        .delete()
        .eq('id', communeId);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['communes-admin-paginated'] });
      toast.success('Comune eliminato');
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore eliminazione comune');
    }
  });

  const deleteAllMutation = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from('communes')
        .delete()
        .neq('id', '00000000-0000-0000-0000-000000000000'); // Delete all
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['communes-admin-paginated'] });
      toast.success('Tutti i comuni eliminati');
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore eliminazione comuni');
    }
  });

  // Mutation to remove CAT assignment
  const removeAssignmentMutation = useMutation({
    mutationFn: async (assignmentId: string) => {
      const { error } = await supabase
        .from('cat_commune')
        .delete()
        .eq('id', assignmentId);
      if (error) throw error;
    },
    onSuccess: () => {
      refetchCommuneAssignments();
      queryClient.invalidateQueries({ queryKey: ['cat-associations-admin-paginated'] });
      toast.success('Assegnazione rimossa');
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore rimozione');
    }
  });

  // Mutation to set primary CAT
  const setPrimaryMutation = useMutation({
    mutationFn: async ({ assignmentId, interventionType }: { assignmentId: string; interventionType: string }) => {
      // First, unset all primaries for this commune and intervention type
      const { error: unsetError } = await supabase
        .from('cat_commune')
        .update({ is_primary: false })
        .eq('commune_id', editingCommune?.id)
        .in('intervention_type', interventionType === 'both' ? ['sopralluogo', 'rfs', 'both'] : [interventionType, 'both']);
      
      if (unsetError) throw unsetError;

      // Then set the new primary
      const { error } = await supabase
        .from('cat_commune')
        .update({ is_primary: true })
        .eq('id', assignmentId);
      
      if (error) throw error;
    },
    onSuccess: () => {
      refetchCommuneAssignments();
      queryClient.invalidateQueries({ queryKey: ['cat-associations-admin-paginated'] });
      toast.success('CAT primario aggiornato');
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore aggiornamento');
    }
  });

  // Mutation to add new assignment
  const addAssignmentMutation = useMutation({
    mutationFn: async ({ catId, interventionType }: { catId: string; interventionType: 'sopralluogo' | 'rfs' }) => {
      // Check if it's the first for this mode
      const existingForMode = communeFullAssignments?.filter(a => 
        a.intervention_type === interventionType || a.intervention_type === 'both'
      );
      const isPrimary = !existingForMode || existingForMode.length === 0;

      const { error } = await supabase
        .from('cat_commune')
        .insert({
          cat_id: catId,
          commune_id: editingCommune?.id,
          intervention_type: interventionType,
          is_primary: isPrimary,
          active: true
        });
      
      if (error) throw error;
    },
    onSuccess: () => {
      refetchCommuneAssignments();
      queryClient.invalidateQueries({ queryKey: ['cat-associations-admin-paginated'] });
      toast.success('CAT aggiunto');
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore aggiunta CAT');
    }
  });

  // Mutation per aggiornare use_quartieri
  const updateUseQuartieriMutation = useMutation({
    mutationFn: async ({ communeId, useQuartieri }: { communeId: string; useQuartieri: boolean }) => {
      const { error } = await supabase
        .from('communes')
        .update({ use_quartieri: useQuartieri })
        .eq('id', communeId);
      
      if (error) throw error;
      return { communeId, useQuartieri };
    },
    onSuccess: async (data) => {
      // Forza il refetch immediato della lista comuni
      await queryClient.refetchQueries({ queryKey: ['communes-admin-paginated'] });
      // Invalida la cache locale della mappa per forzare il refresh
      localStorage.removeItem('map_data_cache');
      localStorage.removeItem('map_data_cache_version');
      toast.success('Preferenza quartieri aggiornata. Ricarica la pagina per vedere le modifiche sulla mappa.');
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore aggiornamento preferenza');
    }
  });

  // Mutation per normalizzare i nomi dei comuni e province (Title Case) - con batching
  const normalizeNamesMutation = useMutation({
    mutationFn: async () => {
      // Recupera tutti i comuni
      const allCommunes: { id: string; comune: string; provincia_nome: string | null }[] = [];
      let page = 0;
      const pageSize = 1000;
      let hasMore = true;

      while (hasMore) {
        const { data, error } = await supabase
          .from('communes')
          .select('id, comune, provincia_nome')
          .range(page * pageSize, (page + 1) * pageSize - 1);
        
        if (error) throw error;
        
        if (data && data.length > 0) {
          allCommunes.push(...data);
          hasMore = data.length === pageSize;
          page++;
        } else {
          hasMore = false;
        }
      }

      // Filtra solo i record che necessitano normalizzazione (comune o provincia)
      const toUpdate = allCommunes
        .map(c => ({
          id: c.id,
          oldComune: c.comune,
          newComune: normalizeText(c.comune),
          oldProvincia: c.provincia_nome,
          newProvincia: c.provincia_nome ? normalizeText(c.provincia_nome) : null
        }))
        .filter(c => c.newComune !== c.oldComune || c.newProvincia !== c.oldProvincia);

      // Aggiorna in batch di 1000
      const batchSize = 1000;
      let updatedCount = 0;

      for (let i = 0; i < toUpdate.length; i += batchSize) {
        const batch = toUpdate.slice(i, i + batchSize);
        
        // Esegui gli update del batch in parallelo (max 50 concurrent per evitare rate limiting)
        const chunkSize = 50;
        for (let j = 0; j < batch.length; j += chunkSize) {
          const chunk = batch.slice(j, j + chunkSize);
          await Promise.all(
            chunk.map(async (item) => {
              const updateData: { comune: string; provincia_nome?: string } = { comune: item.newComune };
              if (item.newProvincia) {
                updateData.provincia_nome = item.newProvincia;
              }
              
              const { error } = await supabase
                .from('communes')
                .update(updateData)
                .eq('id', item.id);
              
              if (error) throw error;
            })
          );
          updatedCount += chunk.length;
        }
      }

      return { total: allCommunes.length, updated: updatedCount };
    },
    onSuccess: async (data) => {
      await queryClient.refetchQueries({ queryKey: ['communes-admin-paginated'] });
      localStorage.removeItem('map_data_cache');
      localStorage.removeItem('map_data_cache_version');
      toast.success(`Normalizzazione completata: ${data.updated} record aggiornati su ${data.total} totali`);
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore durante la normalizzazione');
    }
  });

  const filteredCommunes = communes?.filter(c => 
    c.comune.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.quartiere?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.provincia?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.regione?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  // Group communes and their neighborhoods (case-insensitive matching)
  const groupedCommunesUnsorted = filteredCommunes?.reduce((acc, commune) => {
    if (commune.quartiere) {
      // This is a neighborhood - find parent with case-insensitive match
      const parent = acc.find(c => 
        c.comune.toLowerCase() === commune.comune.toLowerCase() && !c.quartiere
      );
      if (parent) {
        if (!parent.neighborhoods) parent.neighborhoods = [];
        parent.neighborhoods.push(commune);
      } else {
        // Create virtual parent if it doesn't exist
        const virtualParent = {
          id: `virtual-${commune.comune}`,
          comune: normalizeText(commune.comune),
          provincia: commune.provincia,
          regione: commune.regione,
          quartiere: null,
          neighborhoods: [commune],
          isVirtual: true
        };
        acc.push(virtualParent as any);
      }
    } else {
      // This is a main commune - check if already exists with case-insensitive match
      const existing = acc.find(c => 
        c.comune.toLowerCase() === commune.comune.toLowerCase() && !c.quartiere
      );
      if (existing) {
        // If virtual parent exists, replace it with real commune but keep neighborhoods
        if (existing.isVirtual) {
          existing.id = commune.id;
          existing.comune = commune.comune;
          existing.provincia = commune.provincia;
          existing.regione = commune.regione;
          existing.use_quartieri = commune.use_quartieri;
          existing.isVirtual = false;
        }
      } else {
        acc.push({ ...commune, neighborhoods: [] });
      }
    }
    return acc;
  }, [] as any[]);

  // Sort grouped communes
  const groupedCommunes = groupedCommunesUnsorted ? [...groupedCommunesUnsorted].sort((a, b) => {
    if (!sortColumn) return 0;

    let aValue: string | null = null;
    let bValue: string | null = null;

    switch (sortColumn) {
      case 'comune':
        aValue = normalizeText(a.comune).toLowerCase();
        bValue = normalizeText(b.comune).toLowerCase();
        break;
      case 'cat':
        aValue = getPrimaryCAT(a.id)?.toLowerCase() || '';
        bValue = getPrimaryCAT(b.id)?.toLowerCase() || '';
        break;
      case 'provincia':
        aValue = (getProvinceName(a.provincia) || '').toLowerCase();
        bValue = (getProvinceName(b.provincia) || '').toLowerCase();
        break;
      case 'regione':
        aValue = (normalizeText(a.regione) || '').toLowerCase();
        bValue = (normalizeText(b.regione) || '').toLowerCase();
        break;
    }

    // Handle empty values - always put them at the end
    const aEmpty = !aValue || aValue === '';
    const bEmpty = !bValue || bValue === '';
    
    if (aEmpty && bEmpty) return 0;
    if (aEmpty) return 1;
    if (bEmpty) return -1;

    const comparison = aValue.localeCompare(bValue);
    return sortDirection === 'asc' ? comparison : -comparison;
  }) : null;

  const getCommuneCATs = (communeId: string) => {
    return catAssociations?.filter(ca => ca.commune_id === communeId) || [];
  };

  const getPrimaryCAT = (communeId: string) => {
    const associations = getCommuneCATs(communeId);
    const primary = associations.find((ca: any) => ca.is_primary);
    return primary?.cats?.name || null;
  };

  const handleSort = (column: SortColumn) => {
    if (sortColumn === column) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortColumn(column);
      setSortDirection('asc');
    }
  };

  const getSortIcon = (column: SortColumn) => {
    if (sortColumn !== column) {
      return <ArrowUpDown className="h-4 w-4 ml-1 inline" />;
    }
    return sortDirection === 'asc' 
      ? <ArrowUp className="h-4 w-4 ml-1 inline" />
      : <ArrowDown className="h-4 w-4 ml-1 inline" />;
  };

  if (isLoading) {
    return <div className="text-center py-8">Caricamento...</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Cerca comune, provincia o regione..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="pl-9"
          />
        </div>
        <Badge variant="secondary">
          {communes?.filter(c => !c.quartiere).length || 0} comuni
        </Badge>
        <Badge variant="outline">
          {communes?.filter(c => c.quartiere).length || 0} quartieri
        </Badge>
        {isSiteAdmin && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              if (confirm('Normalizzare i nomi di tutti i comuni e province (iniziali maiuscole)? Questa operazione potrebbe richiedere alcuni secondi.')) {
                normalizeNamesMutation.mutate();
              }
            }}
            disabled={!communes?.length || normalizeNamesMutation.isPending}
          >
            <Wand2 className="h-4 w-4 mr-2" />
            {normalizeNamesMutation.isPending ? 'Normalizzazione...' : 'Normalizza Nomi'}
          </Button>
        )}
        <Button
          variant="destructive"
          size="sm"
          onClick={() => {
            if (confirm('Eliminare TUTTI i comuni? Azione irreversibile!')) {
              deleteAllMutation.mutate();
            }
          }}
          disabled={!communes?.length}
        >
          Elimina tutti
        </Button>
      </div>

      <Card>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>
                <button
                  onClick={() => handleSort('comune')}
                  className="flex items-center hover:text-foreground transition-colors"
                >
                  Comune
                  {getSortIcon('comune')}
                </button>
              </TableHead>
              <TableHead>Quartiere</TableHead>
              <TableHead>
                <button
                  onClick={() => handleSort('provincia')}
                  className="flex items-center hover:text-foreground transition-colors"
                >
                  Provincia
                  {getSortIcon('provincia')}
                </button>
              </TableHead>
              <TableHead>
                <button
                  onClick={() => handleSort('regione')}
                  className="flex items-center hover:text-foreground transition-colors"
                >
                  Regione
                  {getSortIcon('regione')}
                </button>
              </TableHead>
              <TableHead>
                <button
                  onClick={() => handleSort('cat')}
                  className="flex items-center hover:text-foreground transition-colors"
                >
                  CAT Associati
                  {getSortIcon('cat')}
                </button>
              </TableHead>
              <TableHead className="w-[100px]">Azioni</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {groupedCommunes?.map((commune) => {
              const cats = commune.isVirtual ? [] : getCommuneCATs(commune.id);
              return (
                <>
                  <TableRow key={commune.id} className="font-medium">
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <MapPin className="h-4 w-4 text-muted-foreground" />
                        <span>
                          {normalizeText(commune.comune)}
                          {commune.alias && (
                            <span className="text-muted-foreground font-normal ml-1">
                              - {commune.alias}
                            </span>
                          )}
                        </span>
                        {commune.isVirtual && (
                          <Badge variant="outline" className="text-xs ml-2">Solo quartieri</Badge>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>-</TableCell>
                    <TableCell>{getProvinceName(commune.provincia) || '-'}</TableCell>
                    <TableCell>{normalizeText(commune.regione) || '-'}</TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {cats.length > 0 ? (
                          cats.map((ca: any) => (
                            <Badge 
                              key={ca.cat_id}
                              style={{ 
                                backgroundColor: ca.cats.color_hex + '20',
                                color: ca.cats.color_hex,
                                borderColor: ca.cats.color_hex
                              }}
                              className="border"
                            >
                              {ca.cats.name}
                            </Badge>
                          ))
                        ) : (
                          <span className="text-xs text-muted-foreground">Nessuno</span>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        {!commune.isVirtual && (
                          <>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => setEditingCommune({
                                id: commune.id,
                                name: commune.comune,
                                isQuartiere: false,
                                hasQuartieri: (commune.neighborhoods?.length || 0) > 0,
                                useQuartieri: commune.use_quartieri !== false
                              })}
                              title="Modifica CAT"
                            >
                              <Pencil className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => {
                                if (confirm(`Eliminare ${commune.comune}?`)) {
                                  deleteMutation.mutate(commune.id);
                                }
                              }}
                            >
                              <Trash2 className="h-4 w-4 text-destructive" />
                            </Button>
                          </>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                  {commune.neighborhoods?.map((neighborhood: any) => {
                    const neighborhoodCats = getCommuneCATs(neighborhood.id);
                    return (
                      <TableRow key={neighborhood.id} className="bg-muted/30">
                        <TableCell className="pl-12">
                          <div className="flex items-center gap-2 text-sm">
                            <div className="w-4 h-px bg-border" />
                            {normalizeText(neighborhood.quartiere)}
                          </div>
                        </TableCell>
                        <TableCell>
                          <Badge variant="outline" className="text-xs">Quartiere</Badge>
                        </TableCell>
                        <TableCell className="text-sm text-muted-foreground">
                          {getProvinceName(neighborhood.provincia) || '-'}
                        </TableCell>
                        <TableCell className="text-sm text-muted-foreground">
                          {normalizeText(neighborhood.regione) || '-'}
                        </TableCell>
                        <TableCell>
                          <div className="flex flex-wrap gap-1">
                            {neighborhoodCats.length > 0 ? (
                              neighborhoodCats.map((ca: any) => (
                                <Badge 
                                  key={ca.cat_id}
                                  style={{ 
                                    backgroundColor: ca.cats.color_hex + '20',
                                    color: ca.cats.color_hex,
                                    borderColor: ca.cats.color_hex
                                  }}
                                  className="border text-xs"
                                >
                                  {ca.cats.name}
                                </Badge>
                              ))
                            ) : (
                              <span className="text-xs text-muted-foreground">Nessuno</span>
                            )}
                          </div>
                        </TableCell>
                        <TableCell>
                          <div className="flex gap-1">
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => setEditingCommune({
                                id: neighborhood.id,
                                name: `${neighborhood.comune} - ${neighborhood.quartiere}`,
                                isQuartiere: true,
                                hasQuartieri: false,
                                useQuartieri: true
                              })}
                              title="Modifica CAT"
                            >
                              <Pencil className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => {
                                if (confirm(`Eliminare quartiere ${neighborhood.quartiere}?`)) {
                                  deleteMutation.mutate(neighborhood.id);
                                }
                              }}
                            >
                              <Trash2 className="h-4 w-4 text-destructive" />
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </>
              );
            })}
            {!groupedCommunes?.length && (
              <TableRow>
                <TableCell colSpan={6} className="text-center text-muted-foreground">
                  Nessun comune trovato
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </Card>

      {/* CAT Assignment Edit Modal */}
      <Dialog open={!!editingCommune} onOpenChange={(open) => {
        if (!open) {
          setEditingCommune(null);
          setCatSearchSopralluogo('');
          setCatSearchRFS('');
        }
      }}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>
              Modifica CAT - {editingCommune?.name}
            </DialogTitle>
          </DialogHeader>
          
          <div className="space-y-6 mt-4">
            {/* Sezione Quartieri - solo per comuni che hanno quartieri */}
            {editingCommune?.hasQuartieri && !editingCommune?.isQuartiere && (
              <>
                <div className="p-4 bg-muted/50 rounded-lg">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <Map className="h-5 w-5 text-muted-foreground" />
                      <div>
                        <Label className="text-sm font-medium">Usa Quartieri</Label>
                        <p className="text-xs text-muted-foreground">
                          Se attivo, vengono usati i quartieri definiti. 
                          Altrimenti viene usata la geometria unificata del comune.
                        </p>
                      </div>
                    </div>
                    <Switch
                      checked={editingCommune.useQuartieri}
                      onCheckedChange={(checked) => {
                        setEditingCommune(prev => prev ? { ...prev, useQuartieri: checked } : null);
                        updateUseQuartieriMutation.mutate({
                          communeId: editingCommune.id,
                          useQuartieri: checked
                        });
                      }}
                    />
                  </div>
                </div>
                <Separator />
              </>
            )}

            {/* Sopralluogo Section */}
            <div>
              <Label className="text-sm font-medium mb-2 block">Sopralluogo</Label>
              <div className="space-y-2">
                {communeFullAssignments
                  ?.filter(a => a.intervention_type === 'sopralluogo' || a.intervention_type === 'both')
                  .map((assignment: any) => (
                    <div 
                      key={assignment.id} 
                      className="flex items-center justify-between p-2 rounded-lg border"
                      style={{ borderColor: assignment.cats?.color_hex || '#ccc' }}
                    >
                      <div className="flex items-center gap-2">
                        <div 
                          className="w-4 h-4 rounded-full"
                          style={{ backgroundColor: assignment.cats?.color_hex || '#888' }}
                        />
                        <span className="font-medium">{assignment.cats?.name}</span>
                        {assignment.is_primary && (
                          <Badge className="text-xs bg-yellow-500">
                            <Star className="h-3 w-3 mr-1" />
                            Primario
                          </Badge>
                        )}
                      </div>
                      <div className="flex items-center gap-1">
                        {!assignment.is_primary && (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => setPrimaryMutation.mutate({ 
                              assignmentId: assignment.id, 
                              interventionType: 'sopralluogo' 
                            })}
                            title="Imposta come primario"
                          >
                            <Star className="h-4 w-4" />
                          </Button>
                        )}
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => removeAssignmentMutation.mutate(assignment.id)}
                        >
                          <X className="h-4 w-4 text-destructive" />
                        </Button>
                      </div>
                    </div>
                  ))}
                {(!communeFullAssignments?.filter(a => 
                  a.intervention_type === 'sopralluogo' || a.intervention_type === 'both'
                ).length) && (
                  <p className="text-sm text-muted-foreground">Nessun CAT assegnato</p>
                )}
                
                {/* Add new CAT for Sopralluogo */}
                <div className="space-y-2 mt-2">
                  <div className="relative">
                    <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
                    <Input
                      placeholder="Cerca CAT..."
                      value={catSearchSopralluogo}
                      onChange={(e) => setCatSearchSopralluogo(e.target.value)}
                      className="h-8 pl-7 text-sm"
                    />
                  </div>
                  <div className="max-h-32 overflow-y-auto space-y-1">
                    {allCats
                      ?.filter(cat => !communeFullAssignments?.some(a => 
                        a.cat_id === cat.id && 
                        (a.intervention_type === 'sopralluogo' || a.intervention_type === 'both')
                      ))
                      .filter(cat => {
                        if (!catSearchSopralluogo.trim()) return true;
                        const search = catSearchSopralluogo.toLowerCase();
                        return cat.name.toLowerCase().includes(search);
                      })
                      .map(cat => (
                        <button
                          key={cat.id}
                          onClick={() => {
                            addAssignmentMutation.mutate({ catId: cat.id, interventionType: 'sopralluogo' });
                            setCatSearchSopralluogo('');
                          }}
                          className="w-full flex items-center gap-2 p-2 rounded-md hover:bg-accent text-left text-sm"
                        >
                          <div 
                            className="w-3 h-3 rounded-full flex-shrink-0"
                            style={{ backgroundColor: cat.color_hex || '#888' }}
                          />
                          <span className="truncate">{cat.name}</span>
                        </button>
                      ))}
                  </div>
                </div>
              </div>
            </div>

            <Separator />

            {/* RFS Section */}
            <div>
              <Label className="text-sm font-medium mb-2 block">RFS</Label>
              <div className="space-y-2">
                {communeFullAssignments
                  ?.filter(a => a.intervention_type === 'rfs' || a.intervention_type === 'both')
                  .map((assignment: any) => (
                    <div 
                      key={assignment.id} 
                      className="flex items-center justify-between p-2 rounded-lg border"
                      style={{ borderColor: assignment.cats?.color_hex || '#ccc' }}
                    >
                      <div className="flex items-center gap-2">
                        <div 
                          className="w-4 h-4 rounded-full"
                          style={{ backgroundColor: assignment.cats?.color_hex || '#888' }}
                        />
                        <span className="font-medium">{assignment.cats?.name}</span>
                        {assignment.is_primary && (
                          <Badge className="text-xs bg-yellow-500">
                            <Star className="h-3 w-3 mr-1" />
                            Primario
                          </Badge>
                        )}
                      </div>
                      <div className="flex items-center gap-1">
                        {!assignment.is_primary && (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => setPrimaryMutation.mutate({ 
                              assignmentId: assignment.id, 
                              interventionType: 'rfs' 
                            })}
                            title="Imposta come primario"
                          >
                            <Star className="h-4 w-4" />
                          </Button>
                        )}
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => removeAssignmentMutation.mutate(assignment.id)}
                        >
                          <X className="h-4 w-4 text-destructive" />
                        </Button>
                      </div>
                    </div>
                  ))}
                {(!communeFullAssignments?.filter(a => 
                  a.intervention_type === 'rfs' || a.intervention_type === 'both'
                ).length) && (
                  <p className="text-sm text-muted-foreground">Nessun CAT assegnato</p>
                )}
                
                {/* Add new CAT for RFS */}
                <div className="space-y-2 mt-2">
                  <div className="relative">
                    <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
                    <Input
                      placeholder="Cerca CAT..."
                      value={catSearchRFS}
                      onChange={(e) => setCatSearchRFS(e.target.value)}
                      className="h-8 pl-7 text-sm"
                    />
                  </div>
                  <div className="max-h-32 overflow-y-auto space-y-1">
                    {allCats
                      ?.filter(cat => !communeFullAssignments?.some(a => 
                        a.cat_id === cat.id && 
                        (a.intervention_type === 'rfs' || a.intervention_type === 'both')
                      ))
                      .filter(cat => {
                        if (!catSearchRFS.trim()) return true;
                        const search = catSearchRFS.toLowerCase();
                        return cat.name.toLowerCase().includes(search);
                      })
                      .map(cat => (
                        <button
                          key={cat.id}
                          onClick={() => {
                            addAssignmentMutation.mutate({ catId: cat.id, interventionType: 'rfs' });
                            setCatSearchRFS('');
                          }}
                          className="w-full flex items-center gap-2 p-2 rounded-md hover:bg-accent text-left text-sm"
                        >
                          <div 
                            className="w-3 h-3 rounded-full flex-shrink-0"
                            style={{ backgroundColor: cat.color_hex || '#888' }}
                          />
                          <span className="truncate">{cat.name}</span>
                        </button>
                      ))}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default CommuneManager;
