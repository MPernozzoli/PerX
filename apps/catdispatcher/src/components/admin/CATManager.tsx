import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { Plus, Edit2, Save, X, Palette, MapPin, Calendar, Trash2, ChevronDown, ChevronUp, AlertTriangle, Search } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible';

interface CAT {
  id: string;
  name: string;
  code: string | null;
  color_hex: string | null;
  notes: string | null;
  active: boolean | null;
}

interface Suspension {
  id: string;
  cat_id: string;
  start_date: string;
  end_date: string;
  reason: 'malattia' | 'ferie' | 'altro';
  created_at: string | null;
}

const CATManager = () => {
  const navigate = useNavigate();
  const [editingId, setEditingId] = useState<string | null>(null);
  const [isCreating, setIsCreating] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [formData, setFormData] = useState({
    name: '',
    color_hex: '#0066FF',
    code: '',
    notes: '',
    active: true
  });
  const [expandedSuspensions, setExpandedSuspensions] = useState<Set<string>>(new Set());
  const [expandedArchive, setExpandedArchive] = useState<Set<string>>(new Set());
  const [newSuspension, setNewSuspension] = useState<{
    catId: string | null;
    start_date: string;
    end_date: string;
    reason: 'malattia' | 'ferie' | 'altro';
  }>({ catId: null, start_date: '', end_date: '', reason: 'malattia' });
  const [editingSuspension, setEditingSuspension] = useState<Suspension | null>(null);
  const queryClient = useQueryClient();

  const today = new Date().toISOString().split('T')[0];

  // Function to convert hex to HSL for color comparison
  const hexToHSL = (hex: string): [number, number, number] => {
    const r = parseInt(hex.slice(1, 3), 16) / 255;
    const g = parseInt(hex.slice(3, 5), 16) / 255;
    const b = parseInt(hex.slice(5, 7), 16) / 255;

    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    let h = 0, s = 0, l = (max + min) / 2;

    if (max !== min) {
      const d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      switch (max) {
        case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
        case g: h = ((b - r) / d + 2) / 6; break;
        case b: h = ((r - g) / d + 4) / 6; break;
      }
    }

    return [h * 360, s * 100, l * 100];
  };

  // Function to check if two colors are too similar
  const areColorsSimilar = (color1: string, color2: string): boolean => {
    const [h1, s1, l1] = hexToHSL(color1);
    const [h2, s2, l2] = hexToHSL(color2);

    const hDiff = Math.min(Math.abs(h1 - h2), 360 - Math.abs(h1 - h2));
    const sDiff = Math.abs(s1 - s2);
    const lDiff = Math.abs(l1 - l2);

    return hDiff < 30 && sDiff < 20 && lDiff < 20;
  };

  // Function to generate a random color that's not similar to existing ones
  const generateUniqueColor = (existingColors: string[]): string => {
    const maxAttempts = 50;
    let attempts = 0;

    while (attempts < maxAttempts) {
      const h = Math.floor(Math.random() * 360);
      const s = 60 + Math.floor(Math.random() * 30);
      const l = 45 + Math.floor(Math.random() * 20);

      const c = (1 - Math.abs(2 * l / 100 - 1)) * s / 100;
      const x = c * (1 - Math.abs((h / 60) % 2 - 1));
      const m = l / 100 - c / 2;
      
      let r = 0, g = 0, b = 0;
      if (h < 60) { r = c; g = x; b = 0; }
      else if (h < 120) { r = x; g = c; b = 0; }
      else if (h < 180) { r = 0; g = c; b = x; }
      else if (h < 240) { r = 0; g = x; b = c; }
      else if (h < 300) { r = x; g = 0; b = c; }
      else { r = c; g = 0; b = x; }

      const toHex = (n: number) => {
        const hex = Math.round((n + m) * 255).toString(16);
        return hex.length === 1 ? '0' + hex : hex;
      };
      
      const hexColor = `#${toHex(r)}${toHex(g)}${toHex(b)}`.toUpperCase();

      const isSimilarToExisting = existingColors.some(existing => 
        areColorsSimilar(hexColor, existing)
      );

      if (!isSimilarToExisting) {
        return hexColor;
      }

      attempts++;
    }

    const h = Math.floor(Math.random() * 360);
    return `hsl(${h}, 70%, 55%)`;
  };

  const { data: cats, isLoading } = useQuery({
    queryKey: ['cats-admin'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('cats')
        .select('*')
        .order('name', { ascending: true });
      
      if (error) throw error;
      return data as CAT[];
    }
  });

  // Fetch all suspensions
  const { data: suspensions } = useQuery({
    queryKey: ['cat-suspensions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('cat_suspensions')
        .select('*')
        .order('start_date', { ascending: true });
      
      if (error) throw error;
      return data as Suspension[];
    }
  });

  // Helper to get suspensions for a specific CAT
  const getSuspensionsForCat = (catId: string) => {
    if (!suspensions) return { active: [], archived: [] };
    const catSuspensions = suspensions.filter(s => s.cat_id === catId);
    return {
      active: catSuspensions.filter(s => s.end_date >= today),
      archived: catSuspensions.filter(s => s.end_date < today)
    };
  };

  // Check if CAT has active suspension
  const hasActiveSuspension = (catId: string) => {
    if (!suspensions) return false;
    return suspensions.some(s => 
      s.cat_id === catId && 
      s.start_date <= today && 
      s.end_date >= today
    );
  };

  // Get active suspension details
  const getActiveSuspensionDetails = (catId: string) => {
    if (!suspensions) return null;
    return suspensions.find(s => 
      s.cat_id === catId && 
      s.start_date <= today && 
      s.end_date >= today
    );
  };

  const createMutation = useMutation({
    mutationFn: async (data: typeof formData) => {
      const { error } = await supabase
        .from('cats')
        .insert([{ ...data, code: data.code || data.name.substring(0, 10).toUpperCase() }]);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['cats-admin'] });
      toast.success('CAT creato');
      setIsCreating(false);
      resetForm();
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore creazione CAT');
    }
  });

  const updateMutation = useMutation({
    mutationFn: async ({ id, data }: { id: string; data: Partial<CAT> }) => {
      const { error } = await supabase
        .from('cats')
        .update(data)
        .eq('id', id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['cats-admin'] });
      toast.success('CAT aggiornato');
      setEditingId(null);
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore aggiornamento CAT');
    }
  });

  // Suspension mutations
  const createSuspensionMutation = useMutation({
    mutationFn: async (data: { cat_id: string; start_date: string; end_date: string; reason: string }) => {
      const { error } = await supabase
        .from('cat_suspensions')
        .insert([data]);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['cat-suspensions'] });
      toast.success('Sospensione creata');
      setNewSuspension({ catId: null, start_date: '', end_date: '', reason: 'malattia' });
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore creazione sospensione');
    }
  });

  const updateSuspensionMutation = useMutation({
    mutationFn: async ({ id, data }: { id: string; data: Partial<Suspension> }) => {
      const { error } = await supabase
        .from('cat_suspensions')
        .update(data)
        .eq('id', id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['cat-suspensions'] });
      toast.success('Sospensione aggiornata');
      setEditingSuspension(null);
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore aggiornamento sospensione');
    }
  });

  const deleteSuspensionMutation = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('cat_suspensions')
        .delete()
        .eq('id', id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['cat-suspensions'] });
      toast.success('Sospensione eliminata');
    },
    onError: (error: any) => {
      toast.error(error.message || 'Errore eliminazione sospensione');
    }
  });

  const resetForm = () => {
    const existingColors = cats?.map(cat => cat.color_hex).filter(Boolean) as string[] || [];
    const newColor = generateUniqueColor(existingColors);
    
    setFormData({
      name: '',
      color_hex: newColor,
      code: '',
      notes: '',
      active: true
    });
  };

  const startEdit = (cat: CAT) => {
    setEditingId(cat.id);
    setFormData({
      name: cat.name,
      color_hex: cat.color_hex || '#0066FF',
      code: cat.code || '',
      notes: cat.notes || '',
      active: cat.active ?? true
    });
  };

  const cancelEdit = () => {
    setEditingId(null);
    resetForm();
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!formData.name) {
      toast.error('Nome obbligatorio');
      return;
    }

    if (editingId) {
      updateMutation.mutate({ id: editingId, data: formData });
    } else {
      createMutation.mutate(formData);
    }
  };

  const handleAddSuspension = (catId: string) => {
    if (!newSuspension.start_date || !newSuspension.end_date) {
      toast.error('Date obbligatorie');
      return;
    }
    if (newSuspension.end_date < newSuspension.start_date) {
      toast.error('Data fine deve essere >= data inizio');
      return;
    }
    createSuspensionMutation.mutate({
      cat_id: catId,
      start_date: newSuspension.start_date,
      end_date: newSuspension.end_date,
      reason: newSuspension.reason
    });
  };

  const handleUpdateSuspension = () => {
    if (!editingSuspension) return;
    if (editingSuspension.end_date < editingSuspension.start_date) {
      toast.error('Data fine deve essere >= data inizio');
      return;
    }
    updateSuspensionMutation.mutate({
      id: editingSuspension.id,
      data: {
        start_date: editingSuspension.start_date,
        end_date: editingSuspension.end_date,
        reason: editingSuspension.reason
      }
    });
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
      case 'malattia': return 'Malattia';
      case 'ferie': return 'Ferie';
      case 'altro': return 'Altro';
      default: return reason;
    }
  };

  const toggleSuspensionsExpanded = (catId: string) => {
    setExpandedSuspensions(prev => {
      const next = new Set(prev);
      if (next.has(catId)) {
        next.delete(catId);
      } else {
        next.add(catId);
      }
      return next;
    });
  };

  const toggleArchiveExpanded = (catId: string) => {
    setExpandedArchive(prev => {
      const next = new Set(prev);
      if (next.has(catId)) {
        next.delete(catId);
      } else {
        next.add(catId);
      }
      return next;
    });
  };

  if (isLoading) {
    return <div className="text-center py-8">Caricamento...</div>;
  }

  // Filtra i CAT in base alla ricerca
  const filteredCats = cats?.filter(cat => {
    if (!searchQuery.trim()) return true;
    const query = searchQuery.toLowerCase();
    return (
      cat.name.toLowerCase().includes(query) ||
      cat.notes?.toLowerCase().includes(query)
    );
  });

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <Badge variant="secondary">
          {filteredCats?.length || 0} di {cats?.length || 0} CAT
        </Badge>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => navigate('/admin/gis-editor')}>
            <MapPin className="h-4 w-4 mr-2" />
            Gestisci Associazioni
          </Button>
          <Dialog open={isCreating} onOpenChange={setIsCreating}>
            <DialogTrigger asChild>
              <Button onClick={() => { resetForm(); setIsCreating(true); }}>
                <Plus className="h-4 w-4 mr-2" />
                Nuovo CAT
              </Button>
            </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Crea Nuovo CAT</DialogTitle>
            </DialogHeader>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="name">Nome CAT *</Label>
                <Input
                  id="name"
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  placeholder="es. Teknovideo"
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="color">Colore</Label>
                <div className="flex gap-2">
                  <Input
                    id="color"
                    type="color"
                    value={formData.color_hex}
                    onChange={(e) => setFormData({ ...formData, color_hex: e.target.value })}
                    className="w-20 h-10"
                  />
                  <Input
                    value={formData.color_hex}
                    onChange={(e) => setFormData({ ...formData, color_hex: e.target.value })}
                    placeholder="#0066FF"
                    className="flex-1"
                  />
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="notes">Note</Label>
                <Textarea
                  id="notes"
                  value={formData.notes}
                  onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
                  placeholder="Note aggiuntive..."
                  rows={3}
                />
              </div>
              <div className="flex items-center gap-2">
                <Switch
                  id="active"
                  checked={formData.active}
                  onCheckedChange={(checked) => setFormData({ ...formData, active: checked })}
                />
                <Label htmlFor="active">Attivo</Label>
              </div>
              <div className="flex gap-2">
                <Button type="submit" className="flex-1">
                  <Save className="h-4 w-4 mr-2" />
                  Crea CAT
                </Button>
                <Button type="button" variant="outline" onClick={() => setIsCreating(false)}>
                  Annulla
                </Button>
              </div>
            </form>
          </DialogContent>
          </Dialog>
        </div>
      </div>

      {/* Barra di ricerca */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          placeholder="Cerca CAT per nome, note o alias..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="pl-10"
        />
        {searchQuery && (
          <Button
            variant="ghost"
            size="sm"
            className="absolute right-1 top-1/2 -translate-y-1/2 h-7 w-7 p-0"
            onClick={() => setSearchQuery('')}
          >
            <X className="h-4 w-4" />
          </Button>
        )}
      </div>

      <div className="grid gap-4">
        {filteredCats?.map((cat) => {
          const isEditing = editingId === cat.id;
          const { active: activeSuspensions, archived: archivedSuspensions } = getSuspensionsForCat(cat.id);
          const isCurrentlySuspended = hasActiveSuspension(cat.id);
          const activeSuspensionDetails = getActiveSuspensionDetails(cat.id);
          const isSuspensionsExpanded = expandedSuspensions.has(cat.id);
          const isArchiveExpanded = expandedArchive.has(cat.id);
          
          return (
            <Card key={cat.id} className="p-4">
              {isEditing ? (
                <form onSubmit={handleSubmit} className="space-y-4">
                  <div className="space-y-2">
                    <Label>Nome CAT *</Label>
                    <Input
                      value={formData.name}
                      onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                      required
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Colore</Label>
                    <div className="flex gap-2">
                      <Input
                        type="color"
                        value={formData.color_hex}
                        onChange={(e) => setFormData({ ...formData, color_hex: e.target.value })}
                        className="w-20 h-10"
                      />
                      <Input
                        value={formData.color_hex}
                        onChange={(e) => setFormData({ ...formData, color_hex: e.target.value })}
                        className="flex-1"
                      />
                    </div>
                  </div>
                  <div className="space-y-2">
                    <Label>Note</Label>
                    <Textarea
                      value={formData.notes}
                      onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
                      rows={2}
                    />
                  </div>
                  <div className="flex items-center gap-2">
                    <Switch
                      checked={formData.active}
                      onCheckedChange={(checked) => setFormData({ ...formData, active: checked })}
                    />
                    <Label>Attivo</Label>
                  </div>
                  <div className="flex gap-2">
                    <Button type="submit" size="sm">
                      <Save className="h-4 w-4 mr-2" />
                      Salva
                    </Button>
                    <Button type="button" variant="outline" size="sm" onClick={cancelEdit}>
                      <X className="h-4 w-4 mr-2" />
                      Annulla
                    </Button>
                  </div>
                </form>
              ) : (
                <div className="space-y-4">
                  {/* CAT Header */}
                  <div className="flex items-start justify-between">
                    <div className="flex items-start gap-4 flex-1">
                      <div 
                        className="w-12 h-12 rounded-md border-2 flex items-center justify-center"
                        style={{ 
                          backgroundColor: cat.color_hex + '20',
                          borderColor: cat.color_hex 
                        }}
                      >
                        <Palette className="h-6 w-6" style={{ color: cat.color_hex }} />
                      </div>
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1 flex-wrap">
                          <h3 className="text-lg font-semibold">{cat.name}</h3>
                          {!cat.active && (
                            <Badge variant="outline">Disattivato</Badge>
                          )}
                          {isCurrentlySuspended && activeSuspensionDetails && (
                            <Badge variant="destructive" className="flex items-center gap-1">
                              <AlertTriangle className="h-3 w-3" />
                              In sospensione fino al {formatDate(activeSuspensionDetails.end_date)}
                              {activeSuspensionDetails.reason !== 'altro' && ` (${getReasonLabel(activeSuspensionDetails.reason)})`}
                            </Badge>
                          )}
                        </div>
                        {cat.notes && (
                          <p className="text-sm text-muted-foreground">{cat.notes}</p>
                        )}
                        <p className="text-xs text-muted-foreground mt-1">
                          Colore: {cat.color_hex}
                        </p>
                      </div>
                    </div>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => startEdit(cat)}
                    >
                      <Edit2 className="h-4 w-4" />
                    </Button>
                  </div>

                  {/* Suspensions Section */}
                  <Collapsible open={isSuspensionsExpanded} onOpenChange={() => toggleSuspensionsExpanded(cat.id)}>
                    <CollapsibleTrigger asChild>
                      <Button variant="ghost" size="sm" className="w-full justify-between">
                        <span className="flex items-center gap-2">
                          <Calendar className="h-4 w-4" />
                          Sospensioni ({activeSuspensions.length} attive/programmate)
                        </span>
                        {isSuspensionsExpanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                      </Button>
                    </CollapsibleTrigger>
                    <CollapsibleContent className="space-y-3 pt-3">
                      {/* Active/Scheduled Suspensions */}
                      {activeSuspensions.length > 0 && (
                        <div className="space-y-2">
                          {activeSuspensions.map(suspension => (
                            <div key={suspension.id} className="flex items-center gap-2 p-2 bg-muted/50 rounded-lg">
                              {editingSuspension?.id === suspension.id ? (
                                <div className="flex-1 flex flex-wrap items-center gap-2">
                                  <Input
                                    type="date"
                                    value={editingSuspension.start_date}
                                    onChange={(e) => setEditingSuspension({ ...editingSuspension, start_date: e.target.value })}
                                    className="w-36"
                                  />
                                  <span>-</span>
                                  <Input
                                    type="date"
                                    value={editingSuspension.end_date}
                                    onChange={(e) => setEditingSuspension({ ...editingSuspension, end_date: e.target.value })}
                                    className="w-36"
                                  />
                                  <Select
                                    value={editingSuspension.reason}
                                    onValueChange={(value: 'malattia' | 'ferie' | 'altro') => 
                                      setEditingSuspension({ ...editingSuspension, reason: value })
                                    }
                                  >
                                    <SelectTrigger className="w-32">
                                      <SelectValue />
                                    </SelectTrigger>
                                    <SelectContent>
                                      <SelectItem value="malattia">Malattia</SelectItem>
                                      <SelectItem value="ferie">Ferie</SelectItem>
                                      <SelectItem value="altro">Altro</SelectItem>
                                    </SelectContent>
                                  </Select>
                                  <Button size="sm" onClick={handleUpdateSuspension}>
                                    <Save className="h-3 w-3" />
                                  </Button>
                                  <Button size="sm" variant="ghost" onClick={() => setEditingSuspension(null)}>
                                    <X className="h-3 w-3" />
                                  </Button>
                                </div>
                              ) : (
                                <>
                                  <div className="flex-1 text-sm">
                                    <span className="font-medium">
                                      {formatDate(suspension.start_date)} - {formatDate(suspension.end_date)}
                                    </span>
                                    <Badge variant="secondary" className="ml-2">
                                      {getReasonLabel(suspension.reason)}
                                    </Badge>
                                    {suspension.start_date <= today && suspension.end_date >= today && (
                                      <Badge variant="destructive" className="ml-2">In corso</Badge>
                                    )}
                                  </div>
                                  <Button size="sm" variant="ghost" onClick={() => setEditingSuspension(suspension)}>
                                    <Edit2 className="h-3 w-3" />
                                  </Button>
                                  <Button 
                                    size="sm" 
                                    variant="ghost" 
                                    onClick={() => deleteSuspensionMutation.mutate(suspension.id)}
                                  >
                                    <Trash2 className="h-3 w-3" />
                                  </Button>
                                </>
                              )}
                            </div>
                          ))}
                        </div>
                      )}

                      {/* Add New Suspension Form */}
                      <div className="flex flex-wrap items-center gap-2 p-2 border border-dashed rounded-lg">
                        <Input
                          type="date"
                          placeholder="Data inizio"
                          value={newSuspension.catId === cat.id ? newSuspension.start_date : ''}
                          onChange={(e) => setNewSuspension({ ...newSuspension, catId: cat.id, start_date: e.target.value })}
                          className="w-36"
                        />
                        <span>-</span>
                        <Input
                          type="date"
                          placeholder="Data fine"
                          value={newSuspension.catId === cat.id ? newSuspension.end_date : ''}
                          onChange={(e) => setNewSuspension({ ...newSuspension, catId: cat.id, end_date: e.target.value })}
                          className="w-36"
                        />
                        <Select
                          value={newSuspension.catId === cat.id ? newSuspension.reason : 'malattia'}
                          onValueChange={(value: 'malattia' | 'ferie' | 'altro') => 
                            setNewSuspension({ ...newSuspension, catId: cat.id, reason: value })
                          }
                        >
                          <SelectTrigger className="w-32">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="malattia">Malattia</SelectItem>
                            <SelectItem value="ferie">Ferie</SelectItem>
                            <SelectItem value="altro">Altro</SelectItem>
                          </SelectContent>
                        </Select>
                        <Button 
                          size="sm" 
                          onClick={() => handleAddSuspension(cat.id)}
                          disabled={newSuspension.catId !== cat.id || !newSuspension.start_date || !newSuspension.end_date}
                        >
                          <Plus className="h-3 w-3 mr-1" />
                          Aggiungi
                        </Button>
                      </div>

                      {/* Archived Suspensions */}
                      {archivedSuspensions.length > 0 && (
                        <Collapsible open={isArchiveExpanded} onOpenChange={() => toggleArchiveExpanded(cat.id)}>
                          <CollapsibleTrigger asChild>
                            <Button variant="ghost" size="sm" className="w-full justify-between text-muted-foreground">
                              <span>Archivio ({archivedSuspensions.length})</span>
                              {isArchiveExpanded ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
                            </Button>
                          </CollapsibleTrigger>
                          <CollapsibleContent className="space-y-2 pt-2">
                            {archivedSuspensions.map(suspension => (
                              <div key={suspension.id} className="flex items-center gap-2 p-2 bg-muted/30 rounded-lg opacity-60">
                                <div className="flex-1 text-sm">
                                  <span>
                                    {formatDate(suspension.start_date)} - {formatDate(suspension.end_date)}
                                  </span>
                                  <Badge variant="outline" className="ml-2">
                                    {getReasonLabel(suspension.reason)}
                                  </Badge>
                                </div>
                              </div>
                            ))}
                          </CollapsibleContent>
                        </Collapsible>
                      )}
                    </CollapsibleContent>
                  </Collapsible>
                </div>
              )}
            </Card>
          );
        })}
        {!filteredCats?.length && (
          <Card className="p-8 text-center">
            <p className="text-muted-foreground">
              {searchQuery 
                ? `Nessun CAT trovato per "${searchQuery}"`
                : 'Nessun CAT presente. Crea il primo CAT per iniziare.'
              }
            </p>
          </Card>
        )}
      </div>
    </div>
  );
};

export default CATManager;
