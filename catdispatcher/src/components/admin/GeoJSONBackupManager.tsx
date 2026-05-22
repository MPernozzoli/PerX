import { useState, useEffect, useCallback, useRef } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Database, HardDrive, Shield, RefreshCw, Download, Trash2, Clock, CheckCircle2, AlertCircle, Loader2, RotateCcw, Users } from 'lucide-react';
import { Separator } from '@/components/ui/separator';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';

interface BackupLog {
  id: string;
  backup_name: string;
  feature_count: number;
  file_size_bytes: number;
  is_healthy: boolean;
  created_at: string;
}

interface RegenerationState {
  isRunning: boolean;
  regions: string[];
  completedRegions: string[];
  failedRegions: string[];
  currentRegion: string;
  totalFeatures: number;
  startTime: number;
}

const STORAGE_KEY = 'geojson_regeneration_state';

interface RestoreOptions {
  communes: boolean;
  cats: boolean;
  associations: boolean;
}

interface RestoreProgress {
  isRunning: boolean;
  currentStep: string;
  completedSteps: string[];
  totalSteps: number;
  error?: string;
}

export const GeoJSONBackupManager = () => {
  const [backups, setBackups] = useState<BackupLog[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [regenerationState, setRegenerationState] = useState<RegenerationState | null>(null);
  const [restoreDialogOpen, setRestoreDialogOpen] = useState(false);
  const [restoreOptions, setRestoreOptions] = useState<RestoreOptions>({
    communes: true,
    cats: true,
    associations: true
  });
  const [restoreProgress, setRestoreProgress] = useState<RestoreProgress | null>(null);
  const [healthStatus, setHealthStatus] = useState<{
    status: string;
    feature_count: number;
    minimum_required: number;
    storage_error?: string;
    backup_count?: number;
    regions_count?: number;
    regions?: string[];
    total_size_bytes?: number;
    message?: string;
  } | null>(null);
  
  const abortControllerRef = useRef<AbortController | null>(null);
  
  // Legacy state for compatibility
  const isRegenerating = regenerationState?.isRunning ?? false;
  const regenerationProgress = regenerationState 
    ? (regenerationState.completedRegions.length / Math.max(regenerationState.regions.length, 1)) * 100 
    : 0;
  const currentRegion = regenerationState?.currentRegion ?? '';

  // Save state to localStorage
  const saveState = useCallback((state: RegenerationState | null) => {
    if (state) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    } else {
      localStorage.removeItem(STORAGE_KEY);
    }
  }, []);

  // Load state from localStorage
  const loadState = useCallback((): RegenerationState | null => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        return JSON.parse(saved);
      }
    } catch (e) {
      console.error('Error loading regeneration state:', e);
    }
    return null;
  }, []);

  // Warn user before leaving during regeneration
  useEffect(() => {
    const handleBeforeUnload = (e: BeforeUnloadEvent) => {
      if (regenerationState?.isRunning) {
        e.preventDefault();
        e.returnValue = 'La rigenerazione è in corso. Se esci, il processo verrà interrotto. Continuare?';
        return e.returnValue;
      }
    };

    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, [regenerationState?.isRunning]);

  // Calculate estimated time remaining
  const getEstimatedTimeRemaining = useCallback(() => {
    if (!regenerationState || !regenerationState.isRunning) return null;
    
    const elapsed = Date.now() - regenerationState.startTime;
    const completed = regenerationState.completedRegions.length;
    const total = regenerationState.regions.length;
    
    if (completed === 0) return 'Calcolo...';
    
    const avgTimePerRegion = elapsed / completed;
    const remaining = (total - completed) * avgTimePerRegion;
    
    if (remaining < 60000) {
      return `${Math.round(remaining / 1000)}s rimanenti`;
    } else {
      return `${Math.round(remaining / 60000)}min rimanenti`;
    }
  }, [regenerationState]);

  // Format elapsed time
  const getElapsedTime = useCallback(() => {
    if (!regenerationState) return '';
    
    const elapsed = Date.now() - regenerationState.startTime;
    
    if (elapsed < 60000) {
      return `${Math.round(elapsed / 1000)}s`;
    } else {
      return `${Math.round(elapsed / 60000)}min`;
    }
  }, [regenerationState]);

  const loadBackups = async () => {
    const { data, error } = await supabase
      .from('geojson_backup_log')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(10);

    if (!error && data) {
      setBackups(data);
    }
  };

  const checkHealth = async () => {
    setIsLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke('geojson-backup-manager', {
        body: { action: 'check_health' }
      });

      if (error) throw error;

      setHealthStatus(data);

      if (data.status === 'empty') {
        toast.warning('Nessun backup trovato', {
          description: 'Usa "Rigenera dal DB" per creare i file'
        });
      } else if (data.status === 'low_coverage' || data.status === 'corrupted') {
        toast.warning('Copertura insufficiente', {
          description: data.message || `Solo ${data.feature_count} geometrie (minimo: ${data.minimum_required})`
        });
      } else {
        toast.success('Backup verificati', {
          description: data.message || `${data.feature_count} geometrie in ${data.regions_count || 0} regioni`
        });
      }
    } catch (error: any) {
      console.error('Error checking health:', error);
      toast.error('Errore durante la verifica', {
        description: error.message
      });
    } finally {
      setIsLoading(false);
    }
  };

  const createBackup = async () => {
    setIsLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke('geojson-backup-manager', {
        body: { action: 'create_backup' }
      });

      if (error) {
        // Try to parse error context if available
        const errorMsg = error.context?.error || error.message || 'Errore sconosciuto';
        throw new Error(errorMsg);
      }

      if (data.status === 'backup_created') {
        const totalSizeMB = ((data.total_size_bytes || 0) / 1024 / 1024).toFixed(2);
        toast.success('Backup verificati!', {
          description: data.message || `${data.backup_count || 0} backup esistenti (${totalSizeMB} MB totali)`
        });
        await loadBackups();
      } else if (data.status === 'no_source' || data.status === 'no_backups') {
        toast.warning('Nessun backup esistente', {
          description: data.message || 'Usa "Rigenera dal DB" per creare i backup regionali'
        });
      } else {
        toast.error('Impossibile verificare i backup', {
          description: data.error || data.message || 'Errore sconosciuto'
        });
      }
    } catch (error: any) {
      console.error('Error creating backup:', error);
      toast.error('Errore durante il backup', {
        description: error.message || 'Controlla i log per maggiori dettagli'
      });
    } finally {
      setIsLoading(false);
    }
  };

  const regenerateFromDatabase = async (resumeState?: RegenerationState) => {
    if (!resumeState && !confirm('Rigenerare il file GeoJSON dal database? Questo creerà file separati per ogni regione.\n\nIMPORTANTE: Non chiudere questa pagina durante il processo!')) {
      return;
    }

    // Create abort controller for this operation
    abortControllerRef.current = new AbortController();
    
    let state: RegenerationState;
    
    if (resumeState) {
      // Resume from saved state
      state = { ...resumeState, isRunning: true };
      toast.info('Ripresa rigenerazione', {
        description: `Riprendo da dove ero rimasto: ${resumeState.completedRegions.length}/${resumeState.regions.length} regioni completate`
      });
    } else {
      // Start fresh
      try {
        const { data: regionsData, error: regionsError } = await supabase.functions.invoke('geojson-backup-manager', {
          body: { action: 'get_regions' }
        });

        if (regionsError) throw regionsError;
        
        const regions = regionsData.regions as string[];
        console.log('Regions to process:', regions);
        
        state = {
          isRunning: true,
          regions,
          completedRegions: [],
          failedRegions: [],
          currentRegion: '',
          totalFeatures: 0,
          startTime: Date.now()
        };
      } catch (error: any) {
        console.error('Error getting regions:', error);
        toast.error('Errore nel recupero delle regioni', {
          description: error.message
        });
        return;
      }
    }
    
    setRegenerationState(state);
    saveState(state);
    
    try {
      const pendingRegions = state.regions.filter(
        r => !state.completedRegions.includes(r) && !state.failedRegions.includes(r)
      );
      
      for (const region of pendingRegions) {
        // Check if aborted
        if (abortControllerRef.current?.signal.aborted) {
          toast.warning('Rigenerazione interrotta');
          break;
        }
        
        // Update current region
        state = { ...state, currentRegion: region };
        setRegenerationState(state);
        saveState(state);
        
        console.log(`Processing region ${state.completedRegions.length + 1}/${state.regions.length}: ${region}`);
        
        try {
          const { data, error } = await supabase.functions.invoke('geojson-backup-manager', {
            body: { action: 'regenerate', regione: region }
          });

          if (error) {
            throw error;
          }

          if (data.status === 'regenerated') {
            state = {
              ...state,
              completedRegions: [...state.completedRegions, region],
              totalFeatures: state.totalFeatures + (data.features || 0)
            };
            setRegenerationState(state);
            saveState(state);
          }
        } catch (error: any) {
          console.error(`Error regenerating ${region}:`, error);
          state = {
            ...state,
            failedRegions: [...state.failedRegions, region]
          };
          setRegenerationState(state);
          saveState(state);
          
          toast.error(`Errore su ${region}`, {
            description: error.message
          });
        }
      }
      
      // Complete
      const finalState = {
        ...state,
        isRunning: false,
        currentRegion: 'Completato!'
      };
      setRegenerationState(finalState);
      
      if (state.failedRegions.length === 0) {
        toast.success('Rigenerazione completata!', {
          description: `${state.totalFeatures} geometrie salvate in ${state.completedRegions.length} file regionali`
        });
        // Clear saved state on success
        saveState(null);
      } else {
        toast.warning('Rigenerazione completata con errori', {
          description: `${state.failedRegions.length} regioni fallite. Puoi riprovare.`
        });
      }
      
      await loadBackups();
      await checkHealth();
      
    } catch (error: any) {
      console.error('Error regenerating:', error);
      toast.error('Errore durante la rigenerazione', {
        description: error.message
      });
    } finally {
      setTimeout(() => {
        setRegenerationState(prev => prev ? { ...prev, isRunning: false } : null);
      }, 2000);
    }
  };

  // Resume regeneration if there's saved state
  const resumeRegeneration = useCallback(() => {
    const savedState = loadState();
    if (savedState && savedState.regions.length > savedState.completedRegions.length + savedState.failedRegions.length) {
      regenerateFromDatabase(savedState);
    }
  }, [loadState]);

  // Clear saved state
  const clearSavedState = useCallback(() => {
    saveState(null);
    setRegenerationState(null);
    toast.info('Stato salvato cancellato');
  }, [saveState]);

  const deleteBackup = async (backupName: string) => {
    if (!confirm(`Eliminare il backup ${backupName}?`)) {
      return;
    }

    try {
      const { error } = await supabase.functions.invoke('geojson-backup-manager', {
        body: { action: 'delete_backup', backup_name: backupName }
      });

      if (error) throw error;

      toast.success('Backup eliminato');
      await loadBackups();
    } catch (error: any) {
      console.error('Error deleting backup:', error);
      toast.error('Errore durante l\'eliminazione', {
        description: error.message
      });
    }
  };

  const reloadMap = () => {
    toast.info('Ricarica la pagina per vedere tutte le regioni sulla mappa');
  };

  const backupCatsData = async () => {
    setIsLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke('geojson-backup-manager', {
        body: { action: 'backup_cats_data' }
      });

      if (error) throw error;

      if (data.status === 'backup_created') {
        toast.success('Backup CAT creato!', {
          description: `${data.cats_count} CAT, ${data.associations_count} associazioni, ${data.suspensions_count} sospensioni`
        });
        await loadBackups();
      } else {
        throw new Error(data.error || 'Errore durante il backup');
      }
    } catch (error: any) {
      console.error('Error backing up CATs:', error);
      toast.error('Errore durante il backup CAT', {
        description: error.message
      });
    } finally {
      setIsLoading(false);
    }
  };

  const openRestoreDialog = () => {
    setRestoreDialogOpen(true);
  };

  const executeRestore = async () => {
    // Check at least one option selected
    if (!restoreOptions.communes && !restoreOptions.cats && !restoreOptions.associations) {
      toast.error('Seleziona almeno un\'opzione da ripristinare');
      return;
    }

    // Keep dialog open to show progress
    setIsLoading(true);
    
    // Build steps list
    const steps: { key: keyof RestoreOptions; label: string }[] = [];
    if (restoreOptions.communes) steps.push({ key: 'communes', label: 'Comuni' });
    if (restoreOptions.cats) steps.push({ key: 'cats', label: 'CAT' });
    if (restoreOptions.associations) steps.push({ key: 'associations', label: 'Associazioni' });
    
    setRestoreProgress({
      isRunning: true,
      currentStep: 'Avvio ripristino...',
      completedSteps: [],
      totalSteps: steps.length
    });
    
    try {
      // Execute restore for each selected option separately
      for (let i = 0; i < steps.length; i++) {
        const step = steps[i];
        
        setRestoreProgress(prev => ({
          ...prev!,
          currentStep: `Ripristino ${step.label}...`,
        }));
        
        const singleOption = {
          communes: step.key === 'communes',
          cats: step.key === 'cats',
          associations: step.key === 'associations'
        };
        
        const { data, error } = await supabase.functions.invoke('geojson-backup-manager', {
          body: { 
            action: 'restore',
            restore_options: singleOption
          }
        });

        if (error) throw error;
        
        if (data.status === 'error') {
          throw new Error(data.error || `Errore durante il ripristino ${step.label}`);
        }
        
        setRestoreProgress(prev => ({
          ...prev!,
          completedSteps: [...prev!.completedSteps, step.label],
        }));
      }
      
      setRestoreProgress(prev => ({
        ...prev!,
        currentStep: 'Completato!',
        isRunning: false
      }));
      
      toast.success('Ripristino completato!', {
        description: `Ripristinati: ${steps.map(s => s.label).join(', ')}`
      });
      
      await loadBackups();
      await checkHealth();
      
      // Close dialog and clear progress after a delay
      setTimeout(() => {
        setRestoreDialogOpen(false);
        setRestoreProgress(null);
      }, 2000);
      
    } catch (error: any) {
      console.error('Error restoring backup:', error);
      setRestoreProgress(prev => ({
        ...prev!,
        isRunning: false,
        currentStep: 'Errore!',
        error: error.message
      }));
      toast.error('Errore durante il ripristino', {
        description: error.message
      });
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadBackups();
    checkHealth();
    
    // Check for saved regeneration state
    const savedState = loadState();
    if (savedState && savedState.regions.length > savedState.completedRegions.length + savedState.failedRegions.length) {
      setRegenerationState({ ...savedState, isRunning: false });
      toast.info('Rigenerazione incompleta trovata', {
        description: `${savedState.completedRegions.length}/${savedState.regions.length} regioni completate. Vuoi riprendere?`,
        duration: 10000,
        action: {
          label: 'Riprendi',
          onClick: () => resumeRegeneration()
        }
      });
    }
  }, []);

  const formatBytes = (bytes: number) => {
    return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleString('it-IT');
  };

  return (
    <Card>
      <CardHeader className="pb-4">
        <div className="flex items-start justify-between gap-4">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Shield className="h-5 w-5" />
              Gestione Backup
            </CardTitle>
            <CardDescription className="mt-1">
              Backup e ripristino di geometrie, CAT e associazioni
            </CardDescription>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={checkHealth}
            disabled={isLoading}
          >
            <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
          </Button>
        </div>
        
        {/* Action buttons grid */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 mt-4">
          {/* Backup Actions */}
          <Button
            variant="outline"
            size="sm"
            onClick={() => regenerateFromDatabase()}
            disabled={isLoading || isRegenerating}
            className="justify-start"
          >
            <Database className={`h-4 w-4 mr-2 ${isRegenerating ? 'animate-spin' : ''}`} />
            <span className="truncate">Backup Comuni</span>
          </Button>
          
          <Button
            variant="outline"
            size="sm"
            onClick={backupCatsData}
            disabled={isLoading}
            className="justify-start"
          >
            <Users className="h-4 w-4 mr-2" />
            <span className="truncate">Backup CAT</span>
          </Button>
          
          {/* Utility Actions */}
          <Button
            variant="outline"
            size="sm"
            onClick={createBackup}
            disabled={isLoading}
            className="justify-start"
          >
            <HardDrive className="h-4 w-4 mr-2" />
            <span className="truncate">Verifica</span>
          </Button>
          
          {/* Restore Action */}
          <Button
            variant="destructive"
            size="sm"
            onClick={openRestoreDialog}
            disabled={isLoading || isRegenerating || restoreProgress?.isRunning}
            className="justify-start"
          >
            <RotateCcw className={`h-4 w-4 mr-2 ${restoreProgress?.isRunning ? 'animate-spin' : ''}`} />
            <span className="truncate">Ripristina</span>
          </Button>
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* Regeneration Progress */}
        {regenerationState && (
          <div className={`p-4 rounded-lg border ${
            regenerationState.isRunning 
              ? 'bg-blue-500/10 border-blue-500/50' 
              : regenerationState.failedRegions.length > 0
                ? 'bg-yellow-500/10 border-yellow-500/50'
                : 'bg-green-500/10 border-green-500/50'
          }`}>
            <div className="space-y-3">
              {/* Header */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  {regenerationState.isRunning ? (
                    <Loader2 className="h-4 w-4 animate-spin text-blue-500" />
                  ) : regenerationState.failedRegions.length > 0 ? (
                    <AlertCircle className="h-4 w-4 text-yellow-500" />
                  ) : (
                    <CheckCircle2 className="h-4 w-4 text-green-500" />
                  )}
                  <span className="font-medium text-sm">
                    {regenerationState.isRunning 
                      ? 'Rigenerazione in corso...' 
                      : regenerationState.failedRegions.length > 0
                        ? 'Rigenerazione incompleta'
                        : 'Rigenerazione completata'}
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  {regenerationState.isRunning && (
                    <span className="text-xs text-muted-foreground flex items-center gap-1">
                      <Clock className="h-3 w-3" />
                      {getEstimatedTimeRemaining()}
                    </span>
                  )}
                  <Badge variant="outline">
                    {regenerationState.completedRegions.length}/{regenerationState.regions.length}
                  </Badge>
                </div>
              </div>

              {/* Progress bar */}
              <Progress value={regenerationProgress} className="h-2" />

              {/* Current region */}
              {regenerationState.isRunning && currentRegion && (
                <div className="flex items-center justify-between text-xs">
                  <span className="text-muted-foreground">
                    Processando: <span className="font-medium text-foreground">{currentRegion}</span>
                  </span>
                  <span className="text-muted-foreground">
                    {getElapsedTime()} trascorsi
                  </span>
                </div>
              )}

              {/* Stats */}
              <div className="flex items-center gap-4 text-xs text-muted-foreground">
                <span className="flex items-center gap-1">
                  <CheckCircle2 className="h-3 w-3 text-green-500" />
                  {regenerationState.completedRegions.length} completate
                </span>
                {regenerationState.failedRegions.length > 0 && (
                  <span className="flex items-center gap-1">
                    <AlertCircle className="h-3 w-3 text-red-500" />
                    {regenerationState.failedRegions.length} fallite
                  </span>
                )}
                <span>
                  {regenerationState.totalFeatures.toLocaleString()} geometrie
                </span>
              </div>

              {/* Warning about not leaving */}
              {regenerationState.isRunning && (
                <div className="text-xs text-yellow-600 dark:text-yellow-400 bg-yellow-500/10 p-2 rounded">
                  ⚠️ Non chiudere questa pagina! Il progresso viene salvato, ma il processo si interromperà.
                </div>
              )}

              {/* Actions for incomplete state */}
              {!regenerationState.isRunning && (regenerationState.failedRegions.length > 0 || 
                regenerationState.completedRegions.length < regenerationState.regions.length) && (
                <div className="flex gap-2 pt-2">
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={resumeRegeneration}
                  >
                    <RefreshCw className="h-4 w-4 mr-2" />
                    Riprendi
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={clearSavedState}
                  >
                    Annulla
                  </Button>
                </div>
              )}

              {/* Completed regions list (collapsible) */}
              {regenerationState.completedRegions.length > 0 && !regenerationState.isRunning && (
                <details className="text-xs">
                  <summary className="cursor-pointer text-muted-foreground hover:text-foreground">
                    Mostra regioni completate
                  </summary>
                  <div className="mt-2 flex flex-wrap gap-1">
                    {regenerationState.completedRegions.map(r => (
                      <Badge key={r} variant="secondary" className="text-xs">
                        {r}
                      </Badge>
                    ))}
                  </div>
                </details>
              )}
            </div>
          </div>
        )}

        {/* Health Status */}
        {healthStatus && (
          <div className={`p-4 rounded-lg border ${
            healthStatus.status === 'healthy' 
              ? 'bg-green-500/10 border-green-500/50' 
              : healthStatus.status === 'empty'
                ? 'bg-yellow-500/10 border-yellow-500/50'
                : 'bg-orange-500/10 border-orange-500/50'
          }`}>
            <div className="flex items-center justify-between">
              <div>
                <h4 className="font-medium text-sm">Stato Backup Regionali</h4>
                <p className="text-xs text-muted-foreground mt-1">
                  {healthStatus.message || (healthStatus.status === 'empty' 
                    ? 'Nessun backup trovato'
                    : `${healthStatus.feature_count?.toLocaleString() || 0} geometrie in ${healthStatus.regions_count || 0} regioni`
                  )}
                </p>
                {healthStatus.total_size_bytes && healthStatus.total_size_bytes > 0 && (
                  <p className="text-xs text-muted-foreground">
                    Dimensione totale: {(healthStatus.total_size_bytes / 1024 / 1024).toFixed(2)} MB
                  </p>
                )}
              </div>
              <Badge variant={
                healthStatus.status === 'healthy' 
                  ? 'default' 
                  : healthStatus.status === 'empty' 
                    ? 'secondary' 
                    : 'outline'
              }>
                {healthStatus.status === 'healthy' 
                  ? 'OK' 
                  : healthStatus.status === 'empty' 
                    ? 'VUOTO' 
                    : 'INCOMPLETO'}
              </Badge>
            </div>
            {(healthStatus.status === 'empty' || healthStatus.status === 'low_coverage') && (
              <p className="text-xs text-yellow-600 dark:text-yellow-400 mt-2">
                Usa il pulsante "Rigenera dal DB" per creare i file GeoJSON dalle geometrie nel database.
              </p>
            )}
          </div>
        )}

        <Separator />

        {/* Backups List */}
        <div className="space-y-2">
          <h4 className="font-medium text-sm flex items-center gap-2">
            <HardDrive className="h-4 w-4" />
            Backup Disponibili ({backups.length})
          </h4>
          
          {backups.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-8">
              Nessun backup disponibile. Crea il primo backup per proteggere i dati.
            </p>
          ) : (
            <div className="space-y-2">
              {backups.map((backup) => (
                <div
                  key={backup.id}
                  className="p-3 rounded-lg border bg-muted/50 hover:bg-muted transition-colors"
                >
                  <div className="flex items-center justify-between gap-3">
                    <div className="flex-1">
                      <p className="text-sm font-medium">{backup.backup_name}</p>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {formatDate(backup.created_at)}
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="text-sm font-medium">{backup.feature_count} geometrie</p>
                      <p className="text-xs text-muted-foreground">{formatBytes(backup.file_size_bytes)}</p>
                    </div>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8"
                      onClick={() => deleteBackup(backup.backup_name)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </CardContent>

      {/* Restore Dialog */}
      <Dialog open={restoreDialogOpen} onOpenChange={(open) => {
        // Prevent closing during restore
        if (!restoreProgress?.isRunning) {
          setRestoreDialogOpen(open);
          if (!open) setRestoreProgress(null);
        }
      }}>
        <DialogContent className="sm:max-w-md">
          {/* Show progress when restoring */}
          {restoreProgress ? (
            <>
              <DialogHeader>
                <DialogTitle className="flex items-center gap-2">
                  {restoreProgress.error ? (
                    <AlertCircle className="h-5 w-5 text-destructive" />
                  ) : restoreProgress.isRunning ? (
                    <Loader2 className="h-5 w-5 animate-spin text-primary" />
                  ) : (
                    <CheckCircle2 className="h-5 w-5 text-green-500" />
                  )}
                  {restoreProgress.error 
                    ? 'Errore durante il ripristino' 
                    : restoreProgress.isRunning 
                      ? 'Ripristino in corso...' 
                      : 'Ripristino completato!'}
                </DialogTitle>
              </DialogHeader>
              
              <div className="py-6 space-y-4">
                {/* Progress bar */}
                <div className="space-y-2">
                  <div className="flex justify-between text-sm">
                    <span className="text-muted-foreground">{restoreProgress.currentStep}</span>
                    <span className="font-medium">{restoreProgress.completedSteps.length}/{restoreProgress.totalSteps}</span>
                  </div>
                  <Progress 
                    value={(restoreProgress.completedSteps.length / restoreProgress.totalSteps) * 100} 
                    className="h-3" 
                  />
                </div>
                
                {/* Steps list */}
                <div className="space-y-2">
                  {restoreProgress.completedSteps.map((step, i) => (
                    <div key={i} className="flex items-center gap-2 text-sm text-green-600">
                      <CheckCircle2 className="h-4 w-4" />
                      <span>{step} ripristinato</span>
                    </div>
                  ))}
                  {restoreProgress.isRunning && (
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                      <Loader2 className="h-4 w-4 animate-spin" />
                      <span>{restoreProgress.currentStep}</span>
                    </div>
                  )}
                </div>
                
                {/* Error message */}
                {restoreProgress.error && (
                  <div className="bg-destructive/10 border border-destructive/30 rounded-md p-3">
                    <p className="text-sm text-destructive">{restoreProgress.error}</p>
                  </div>
                )}
              </div>
              
              {/* Footer only shown when not running */}
              {!restoreProgress.isRunning && (
                <DialogFooter>
                  <Button 
                    variant={restoreProgress.error ? "destructive" : "default"}
                    onClick={() => {
                      setRestoreDialogOpen(false);
                      setRestoreProgress(null);
                    }}
                  >
                    {restoreProgress.error ? 'Chiudi' : 'Fatto'}
                  </Button>
                </DialogFooter>
              )}
            </>
          ) : (
            /* Show selection options when not restoring */
            <>
              <DialogHeader>
                <DialogTitle className="flex items-center gap-2 text-destructive">
                  <AlertCircle className="h-5 w-5" />
                  Ripristino Database
                </DialogTitle>
                <DialogDescription>
                  Seleziona cosa ripristinare dal backup.
                </DialogDescription>
              </DialogHeader>
              
              <div className="space-y-3 py-4">
                {/* Tutto */}
                <div 
                  className={`flex items-center space-x-3 p-3 rounded-lg border-2 cursor-pointer transition-colors ${
                    restoreOptions.communes && restoreOptions.cats && restoreOptions.associations
                      ? 'border-primary bg-primary/5'
                      : 'border-muted hover:border-muted-foreground/30'
                  }`}
                  onClick={() => {
                    const allSelected = restoreOptions.communes && restoreOptions.cats && restoreOptions.associations;
                    setRestoreOptions({ communes: !allSelected, cats: !allSelected, associations: !allSelected });
                  }}
                >
                  <Checkbox 
                    id="restore-all" 
                    checked={restoreOptions.communes && restoreOptions.cats && restoreOptions.associations}
                    onCheckedChange={(checked) => 
                      setRestoreOptions({ communes: !!checked, cats: !!checked, associations: !!checked })
                    }
                  />
                  <div className="grid gap-0.5 leading-none flex-1">
                    <Label htmlFor="restore-all" className="font-semibold cursor-pointer">
                      Tutto
                    </Label>
                    <p className="text-xs text-muted-foreground">
                      Ripristino completo del database
                    </p>
                  </div>
                </div>

                <Separator className="my-2" />
                
                {/* Comuni */}
                <div 
                  className={`flex items-center space-x-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                    restoreOptions.communes ? 'border-primary/50 bg-primary/5' : 'border-muted hover:border-muted-foreground/30'
                  }`}
                  onClick={() => setRestoreOptions(prev => ({ ...prev, communes: !prev.communes }))}
                >
                  <Checkbox 
                    id="restore-communes" 
                    checked={restoreOptions.communes}
                    onCheckedChange={(checked) => 
                      setRestoreOptions(prev => ({ ...prev, communes: !!checked }))
                    }
                  />
                  <div className="grid gap-0.5 leading-none flex-1">
                    <Label htmlFor="restore-communes" className="font-medium cursor-pointer">
                      Comuni
                    </Label>
                    <p className="text-xs text-muted-foreground">
                      Geometrie dei comuni italiani
                    </p>
                  </div>
                </div>
                
                {/* CAT */}
                <div 
                  className={`flex items-center space-x-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                    restoreOptions.cats ? 'border-primary/50 bg-primary/5' : 'border-muted hover:border-muted-foreground/30'
                  }`}
                  onClick={() => setRestoreOptions(prev => ({ ...prev, cats: !prev.cats }))}
                >
                  <Checkbox 
                    id="restore-cats" 
                    checked={restoreOptions.cats}
                    onCheckedChange={(checked) => 
                      setRestoreOptions(prev => ({ ...prev, cats: !!checked }))
                    }
                  />
                  <div className="grid gap-0.5 leading-none flex-1">
                    <Label htmlFor="restore-cats" className="font-medium cursor-pointer">
                      CAT
                    </Label>
                    <p className="text-xs text-muted-foreground">
                      Lista periti e sospensioni
                    </p>
                  </div>
                </div>
                
                {/* Associazioni */}
                <div 
                  className={`flex items-center space-x-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                    restoreOptions.associations ? 'border-primary/50 bg-primary/5' : 'border-muted hover:border-muted-foreground/30'
                  }`}
                  onClick={() => setRestoreOptions(prev => ({ ...prev, associations: !prev.associations }))}
                >
                  <Checkbox 
                    id="restore-associations" 
                    checked={restoreOptions.associations}
                    onCheckedChange={(checked) => 
                      setRestoreOptions(prev => ({ ...prev, associations: !!checked }))
                    }
                  />
                  <div className="grid gap-0.5 leading-none flex-1">
                    <Label htmlFor="restore-associations" className="font-medium cursor-pointer">
                      Associazioni
                    </Label>
                    <p className="text-xs text-muted-foreground">
                      Assegnazioni CAT ai comuni
                    </p>
                  </div>
                </div>
              </div>

              <div className="bg-destructive/10 border border-destructive/30 rounded-md p-3">
                <p className="text-xs text-destructive font-medium">
                  ⚠️ I dati selezionati verranno eliminati e sostituiti con il backup
                </p>
              </div>
              
              <DialogFooter className="mt-4">
                <Button variant="outline" onClick={() => setRestoreDialogOpen(false)}>
                  Annulla
                </Button>
                <Button 
                  variant="destructive" 
                  onClick={executeRestore}
                  disabled={!restoreOptions.communes && !restoreOptions.cats && !restoreOptions.associations}
                >
                  <RotateCcw className="h-4 w-4 mr-2" />
                  Ripristina
                </Button>
              </DialogFooter>
            </>
          )}
        </DialogContent>
      </Dialog>
    </Card>
  );
};
