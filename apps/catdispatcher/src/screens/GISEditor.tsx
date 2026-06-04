import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { Session } from '@supabase/supabase-js';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { ArrowLeft, Save, X, AlertTriangle } from 'lucide-react';
import { toast } from 'sonner';
import GISInspector from '@/components/admin/GISInspector';
import GISMap from '@/components/admin/GISMap';
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

export type InterventionMode = 'sopralluogo' | 'rfs';

export interface CATAssignment {
  id: string;
  cat_id: string;
  commune_id: string;
  is_primary: boolean;
  intervention_type: string;
  active: boolean;
}

export interface CAT {
  id: string;
  name: string;
  color_hex: string | null;
  active: boolean | null;
}

// Pending changes structure
export interface PendingChange {
  type: 'add' | 'remove';
  communeId: string;
  catId: string;
  interventionType: InterventionMode;
  isPrimary?: boolean;
  originalAssignmentId?: string; // For removals
}

const GISEditor = () => {
  const navigate = useNavigate();
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  
  // State management
  const [selectedCatId, setSelectedCatId] = useState<string | null>(null);
  const [currentMode, setCurrentMode] = useState<InterventionMode>('sopralluogo');
  const [showLabels, setShowLabels] = useState(false);
  const [showProvinceBorders, setShowProvinceBorders] = useState(false);
  const [showRegionBorders, setShowRegionBorders] = useState(false);
  
  // Data
  const [cats, setCats] = useState<CAT[]>([]);
  const [assignments, setAssignments] = useState<CATAssignment[]>([]);
  
  // Boundary geometries
  const [provinceGeoms, setProvinceGeoms] = useState<any[]>([]);
  const [regionGeoms, setRegionGeoms] = useState<any[]>([]);
  const hasProvinceGeoms = provinceGeoms.length > 0;
  const hasRegionGeoms = regionGeoms.length > 0;
  
  // Pending changes (local, not saved to DB yet)
  const [pendingChanges, setPendingChanges] = useState<PendingChange[]>([]);
  
  // Exit confirmation dialog
  const [showExitDialog, setShowExitDialog] = useState(false);
  const [pendingNavigation, setPendingNavigation] = useState<string | null>(null);

  const hasUnsavedChanges = pendingChanges.length > 0;

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      if (!session) {
        navigate('/login');
      }
      setLoading(false);
    });
  }, [navigate]);

  // Fetch CATs
  useEffect(() => {
    const fetchCats = async () => {
      const { data, error } = await supabase
        .from('cats')
        .select('id, name, color_hex, active')
        .eq('active', true)
        .order('name');
      
      if (!error && data) {
        setCats(data);
      }
    };
    
    fetchCats();
  }, []);

  // Fetch province and region geometries
  useEffect(() => {
    const fetchBoundaries = async () => {
      // Fetch provinces
      const { data: provinces } = await (supabase as any)
        .from('provinces')
        .select('name, geom, regione');
      
      if (provinces && provinces.length > 0) {
        console.log(`Loaded ${provinces.length} province boundaries`);
        setProvinceGeoms(provinces);
      }

      // Fetch regions
      const { data: regions } = await (supabase as any)
        .from('regions')
        .select('name, geom');
      
      if (regions && regions.length > 0) {
        console.log(`Loaded ${regions.length} region boundaries`);
        setRegionGeoms(regions);
      }
    };
    
    fetchBoundaries();
  }, []);

  // Fetch assignments with pagination
  const fetchAssignments = useCallback(async () => {
    const allAssignments: CATAssignment[] = [];
    let page = 0;
    const pageSize = 1000;
    let hasMore = true;

    while (hasMore) {
      const { data, error } = await supabase
        .from('cat_commune')
        .select('id, cat_id, commune_id, is_primary, intervention_type, active')
        .eq('active', true)
        .range(page * pageSize, (page + 1) * pageSize - 1);
      
      if (error) {
        console.error('Error fetching assignments:', error);
        break;
      }
      
      if (data && data.length > 0) {
        allAssignments.push(...data);
        hasMore = data.length === pageSize;
        page++;
      } else {
        hasMore = false;
      }
    }

    console.log(`Loaded ${allAssignments.length} assignments`);
    setAssignments(allAssignments);
  }, []);

  useEffect(() => {
    fetchAssignments();
  }, [fetchAssignments]);

  // Compute effective assignments (DB + pending changes)
  const effectiveAssignments = useCallback((): CATAssignment[] => {
    let result = [...assignments];
    
    pendingChanges.forEach(change => {
      if (change.type === 'remove') {
        result = result.filter(a => a.id !== change.originalAssignmentId);
      } else if (change.type === 'add') {
        // Add a temporary assignment
        result.push({
          id: `pending-${change.communeId}-${change.catId}-${change.interventionType}`,
          cat_id: change.catId,
          commune_id: change.communeId,
          is_primary: change.isPrimary || false,
          intervention_type: change.interventionType,
          active: true
        });
      }
    });
    
    return result;
  }, [assignments, pendingChanges]);

  // Filter assignments by current mode
  const filteredAssignments = effectiveAssignments().filter(a => 
    a.intervention_type === currentMode || a.intervention_type === 'both'
  );

  // Handle local assignment change (doesn't save to DB)
  const handleLocalAssignmentChange = useCallback((change: PendingChange) => {
    setPendingChanges(prev => {
      // Check if this change cancels out an existing pending change
      const oppositeIndex = prev.findIndex(p => 
        p.communeId === change.communeId && 
        p.catId === change.catId && 
        p.interventionType === change.interventionType &&
        p.type !== change.type
      );
      
      if (oppositeIndex >= 0) {
        // Cancel out the opposite change
        const newChanges = [...prev];
        newChanges.splice(oppositeIndex, 1);
        return newChanges;
      }
      
      // Check if same change already exists
      const existingIndex = prev.findIndex(p => 
        p.communeId === change.communeId && 
        p.catId === change.catId && 
        p.interventionType === change.interventionType &&
        p.type === change.type
      );
      
      if (existingIndex >= 0) {
        return prev; // Already exists
      }
      
      return [...prev, change];
    });
  }, []);

  // Save all pending changes to DB
  const saveChanges = async () => {
    if (pendingChanges.length === 0) return;
    
    setSaving(true);
    
    try {
      // Process removals first
      const removals = pendingChanges.filter(c => c.type === 'remove');
      if (removals.length > 0) {
        const removalIds = removals.map(r => r.originalAssignmentId).filter(Boolean);
        if (removalIds.length > 0) {
          const { error } = await supabase
            .from('cat_commune')
            .delete()
            .in('id', removalIds);
          
          if (error) throw error;
        }
      }
      
      // Process additions
      const additions = pendingChanges.filter(c => c.type === 'add');
      if (additions.length > 0) {
        const inserts = additions.map(a => ({
          cat_id: a.catId,
          commune_id: a.communeId,
          intervention_type: a.interventionType,
          is_primary: a.isPrimary || false,
          active: true
        }));
        
        const { error } = await supabase
          .from('cat_commune')
          .insert(inserts);
        
        if (error) throw error;
      }
      
      toast.success(`${pendingChanges.length} modifiche salvate`);
      setPendingChanges([]);
      await fetchAssignments();
    } catch (error: any) {
      toast.error(error.message || 'Errore durante il salvataggio');
    } finally {
      setSaving(false);
    }
  };

  // Discard all pending changes
  const discardChanges = () => {
    setPendingChanges([]);
    toast.info('Modifiche annullate');
  };

  // Handle navigation with unsaved changes check
  const handleNavigate = (path: string) => {
    if (hasUnsavedChanges) {
      setPendingNavigation(path);
      setShowExitDialog(true);
    } else {
      navigate(path);
    }
  };

  // Handle exit dialog actions
  const handleExitWithSave = async () => {
    await saveChanges();
    setShowExitDialog(false);
    if (pendingNavigation) {
      navigate(pendingNavigation);
    }
  };

  const handleExitWithoutSave = () => {
    setPendingChanges([]);
    setShowExitDialog(false);
    if (pendingNavigation) {
      navigate(pendingNavigation);
    }
  };

  const handleCancelExit = () => {
    setShowExitDialog(false);
    setPendingNavigation(null);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
      </div>
    );
  }

  return (
    <div className="h-screen flex flex-col">
      {/* Header */}
      <div className="flex items-center gap-4 p-4 border-b bg-background">
        <Button variant="ghost" size="sm" onClick={() => handleNavigate('/admin')}>
          <ArrowLeft className="h-4 w-4 mr-2" />
          Torna all'admin
        </Button>
        <div className="flex-1">
          <h1 className="text-xl font-semibold">Editor Associazioni CAT</h1>
          <p className="text-sm text-muted-foreground">
            Clicca su un comune/quartiere per assegnare il CAT selezionato
          </p>
        </div>
        
        {/* Save/Cancel buttons */}
        <div className="flex items-center gap-2">
          {hasUnsavedChanges && (
            <Badge variant="secondary" className="mr-2">
              {pendingChanges.length} modific{pendingChanges.length === 1 ? 'a' : 'he'} non salvat{pendingChanges.length === 1 ? 'a' : 'e'}
            </Badge>
          )}
          <Button
            variant="outline"
            size="sm"
            onClick={discardChanges}
            disabled={!hasUnsavedChanges || saving}
          >
            <X className="h-4 w-4 mr-2" />
            Annulla
          </Button>
          <Button
            size="sm"
            onClick={saveChanges}
            disabled={!hasUnsavedChanges || saving}
          >
            {saving ? (
              <div className="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent mr-2" />
            ) : (
              <Save className="h-4 w-4 mr-2" />
            )}
            Salva
          </Button>
        </div>
      </div>

      {/* Main content */}
      <div className="flex-1 flex overflow-hidden">
        {/* Inspector Panel */}
        <div className="w-80 border-r bg-background overflow-y-auto">
          <GISInspector
            cats={cats}
            assignments={filteredAssignments}
            selectedCatId={selectedCatId}
            onSelectCat={setSelectedCatId}
            currentMode={currentMode}
            onModeChange={setCurrentMode}
            showLabels={showLabels}
            onShowLabelsChange={setShowLabels}
            showProvinceBorders={showProvinceBorders}
            onShowProvinceBordersChange={setShowProvinceBorders}
            showRegionBorders={showRegionBorders}
            onShowRegionBordersChange={setShowRegionBorders}
            hasProvinceGeoms={hasProvinceGeoms}
            hasRegionGeoms={hasRegionGeoms}
          />
        </div>

        {/* Map */}
        <div className="flex-1 relative">
          <GISMap
            session={session}
            selectedCatId={selectedCatId}
            currentMode={currentMode}
            assignments={filteredAssignments}
            allAssignments={effectiveAssignments()}
            cats={cats}
            showLabels={showLabels}
            showProvinceBorders={showProvinceBorders}
            showRegionBorders={showRegionBorders}
            onLocalChange={handleLocalAssignmentChange}
            pendingChanges={pendingChanges}
            provinceGeoms={provinceGeoms}
            regionGeoms={regionGeoms}
          />
        </div>
      </div>

      {/* Exit Confirmation Dialog */}
      <AlertDialog open={showExitDialog} onOpenChange={setShowExitDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-yellow-500" />
              Modifiche non salvate
            </AlertDialogTitle>
            <AlertDialogDescription>
              Hai {pendingChanges.length} modific{pendingChanges.length === 1 ? 'a' : 'he'} non salvat{pendingChanges.length === 1 ? 'a' : 'e'}. 
              Cosa vuoi fare?
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter className="flex-col sm:flex-row gap-2">
            <AlertDialogCancel onClick={handleCancelExit}>
              Annulla
            </AlertDialogCancel>
            <Button variant="destructive" onClick={handleExitWithoutSave}>
              Esci senza salvare
            </Button>
            <AlertDialogAction onClick={handleExitWithSave}>
              <Save className="h-4 w-4 mr-2" />
              Salva ed esci
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
};

export default GISEditor;
