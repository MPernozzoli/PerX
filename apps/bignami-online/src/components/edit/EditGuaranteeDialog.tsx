import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@perx/ui/components/ui/dialog";
import { Button } from "@perx/ui/components/ui/button";
import { Input } from "@perx/ui/components/ui/input";
import { Label } from "@perx/ui/components/ui/label";
import { Textarea } from "@perx/ui/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@perx/ui/components/ui/select";
import { Separator } from "@perx/ui/components/ui/separator";
import { Checkbox } from "@perx/ui/components/ui/checkbox";
import { CoverageItem, ValueType } from "@/types";
import { GuaranteeConditionsManager } from "@/components/GuaranteeConditionsManager";
import { Badge } from "@perx/ui/components/ui/badge";
import { TrashIcon } from "lucide-react";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@perx/ui/components/ui/alert-dialog";

interface EditGuaranteeDialogProps {
  guarantee: CoverageItem;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (updates: Partial<CoverageItem>) => void;
  onDelete?: () => void;
}

export const EditGuaranteeDialog = ({ guarantee, open, onOpenChange, onSave, onDelete }: EditGuaranteeDialogProps) => {
  // Get sections for party selector
  const { data: sectionsData } = useQuery({
    queryKey: ['sections', guarantee.coverage_id],
    queryFn: async () => {
      const { data, error } = await supabase.from('sections').select('*').eq('coverage_id', guarantee.coverage_id);
      if (error) throw error;
      return data;
    },
    enabled: !!guarantee.coverage_id
  });
  
  const availableParties = Array.isArray(sectionsData) ? sectionsData : [];
  const [formData, setFormData] = useState({
    exact_name: guarantee.exact_name || "",
    description: guarantee.description || "",
    value_type: guarantee.value_type || 'valore_intero' as ValueType,
    primo_rischio_value: guarantee.primo_rischio_value || "",
    common_exclusions: guarantee.common_exclusions?.join('\n') || "",
    guarantee_group: guarantee.guarantee_group || 'FE',
    available_parties: guarantee.available_parties || [] as string[],
  });

  const GUARANTEE_GROUPS = [
    { value: 'FE', label: 'Fenomeno Elettrico' },
    { value: 'AC', label: 'Acqua Condotta' },
    { value: 'FA', label: 'Fenomeni Atmosferici' },
    { value: 'FUR', label: 'Furto' },
    { value: 'INC', label: 'Incendio' },
    { value: 'RC', label: 'Responsabilità Civile' },
    { value: 'CR', label: 'Cristalli' },
    { value: 'ALL', label: 'All Risks' },
    { value: 'ALT', label: 'Altro' }
  ];

  const getValueTypeDisplay = (valueType?: ValueType, primoRischioValue?: string) => {
    switch(valueType) {
      case 'primo_rischio_assoluto':
        return (
          <Badge className="bg-accent text-accent-foreground text-xs">
            Primo Rischio Assoluto
          </Badge>
        );
      case 'primo_rischio_assoluto_fino_a':
        return (
          <div className="flex items-center gap-2">
            <Badge className="bg-accent text-accent-foreground text-xs">
              Primo Rischio Assoluto fino a
            </Badge>
            <span className="font-mono text-sm">{primoRischioValue}</span>
          </div>
        );
      case 'valore_intero':
      default:
        return (
          <Badge className="bg-muted text-muted-foreground text-xs">
            Valore Intero
          </Badge>
        );
    }
  };

  const handleSave = () => {
    const updates: Partial<CoverageItem> = {
      exact_name: formData.exact_name || undefined,
      description: formData.description || undefined,
      value_type: formData.value_type,
      primo_rischio_value: formData.value_type === 'primo_rischio_assoluto_fino_a' ? formData.primo_rischio_value : undefined,
      common_exclusions: formData.common_exclusions ? formData.common_exclusions.split('\n').filter(line => line.trim()) : [],
      guarantee_group: formData.guarantee_group,
      available_parties: formData.available_parties.length > 0 ? formData.available_parties : null,
    };
    
    onSave(updates);
    onOpenChange(false);
  };

  const togglePartySelection = (partyId: string) => {
    setFormData(prev => ({
      ...prev,
      available_parties: prev.available_parties.includes(partyId)
        ? prev.available_parties.filter(id => id !== partyId)
        : [...prev.available_parties, partyId]
    }));
  };

  const selectAllParties = () => {
    const allPartyIds = availableParties.map(p => p.id);
    setFormData(prev => ({
      ...prev,
      available_parties: prev.available_parties.length === allPartyIds.length ? [] : allPartyIds
    }));
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-6xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Modifica Garanzia: {guarantee.exact_name || guarantee.guarantee_name}</DialogTitle>
          <DialogDescription>
            Configura tutti i dettagli, le condizioni e le esclusioni per questa garanzia
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-6">
          
          {/* Informazioni di base della garanzia */}
          <div className="space-y-4 p-4 border rounded-lg bg-blue-50/30">
            <h3 className="text-lg font-semibold text-blue-800">Informazioni Garanzia</h3>
            
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="exact_name">Nome Esatto</Label>
                <Input
                  id="exact_name"
                  value={formData.exact_name}
                  onChange={(e) => setFormData(prev => ({ ...prev, exact_name: e.target.value }))}
                  placeholder="Nome esatto della garanzia"
                />
              </div>
              
              <div className="space-y-2">
                <Label>Gruppo Garanzia</Label>
                <Select 
                  value={formData.guarantee_group} 
                  onValueChange={(value) => setFormData(prev => ({ ...prev, guarantee_group: value }))}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {GUARANTEE_GROUPS.map(group => (
                      <SelectItem key={group.value} value={group.value}>
                        {group.value} - {group.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="description">Descrizione Garanzia</Label>
              <Textarea
                id="description"
                value={formData.description}
                onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
                placeholder="Descrizione dettagliata della garanzia..."
                rows={3}
              />
            </div>

            {/* Tipo di Valore */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Tipo di Valore</Label>
                <Select 
                  value={formData.value_type} 
                  onValueChange={(value: ValueType) => setFormData(prev => ({ ...prev, value_type: value }))}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="valore_intero">Valore Intero</SelectItem>
                    <SelectItem value="primo_rischio_assoluto">Primo Rischio Assoluto</SelectItem>
                    <SelectItem value="primo_rischio_assoluto_fino_a">Primo Rischio Assoluto fino a</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              {formData.value_type === 'primo_rischio_assoluto_fino_a' && (
                <div className="space-y-2">
                  <Label htmlFor="primo_rischio_value">Valore Primo Rischio</Label>
                  <Input
                    id="primo_rischio_value"
                    value={formData.primo_rischio_value}
                    onChange={(e) => setFormData(prev => ({ ...prev, primo_rischio_value: e.target.value }))}
                    placeholder="es. € 50.000"
                  />
                </div>
              )}
            </div>

            {/* Preview tipo valore */}
            <div className="flex items-center gap-2">
              <Label className="text-sm">Anteprima:</Label>
              {getValueTypeDisplay(formData.value_type, formData.primo_rischio_value)}
            </div>

            {/* Esclusioni Comuni della Garanzia */}
            <div className="space-y-2">
              <Label htmlFor="common_exclusions">Esclusioni Comuni della Garanzia</Label>
              <Textarea
                id="common_exclusions"
                value={formData.common_exclusions}
                onChange={(e) => setFormData(prev => ({ ...prev, common_exclusions: e.target.value }))}
                placeholder="Inserisci le esclusioni comuni, una per riga..."
                rows={4}
              />
            </div>
          </div>

          {/* Disponibilità per Partite */}
          <div className="space-y-4 p-4 border rounded-lg bg-yellow-50/30">
            <h3 className="text-lg font-semibold text-yellow-800">Disponibilità per Partite</h3>
            <p className="text-sm text-muted-foreground">
              Seleziona le partite per cui questa garanzia sarà disponibile.
              Se non selezioni nulla, la garanzia sarà disponibile per tutte le partite.
            </p>
            
            <div className="flex flex-wrap gap-2">
              <Button
                type="button"
                variant={formData.available_parties.length === availableParties.length ? "default" : "outline"}
                size="sm"
                onClick={selectAllParties}
              >
                {formData.available_parties.length === availableParties.length ? 'Deseleziona' : 'Seleziona'} tutte
              </Button>
              {availableParties.map((party) => (
                <Button
                  key={party.id}
                  type="button"
                  variant={formData.available_parties.includes(party.id) ? "default" : "outline"}
                  size="sm"
                  onClick={() => togglePartySelection(party.id)}
                >
                  {party.emoji} {party.exact_name || party.party}
                </Button>
              ))}
            </div>
          </div>

          <Separator />

          {/* Condizioni Multiple - Massimali, Franchigie, Esclusioni Specifiche */}
          <div className="space-y-4">
            <h3 className="text-lg font-semibold">Condizioni della Garanzia</h3>
            <p className="text-sm text-muted-foreground">
              Configura i massimali, le franchigie e le esclusioni specifiche per questa garanzia.
              Ogni condizione può essere assegnata a partite specifiche.
            </p>
            
            <GuaranteeConditionsManager 
              guaranteeItem={guarantee}
              isEditMode={true}
            />
          </div>

        </div>

        <div className="flex justify-between pt-4 mt-6 border-t">
          <div>
            {onDelete && (
              <AlertDialog>
                <AlertDialogTrigger asChild>
                  <Button variant="destructive" className="gap-2">
                    <TrashIcon className="h-4 w-4" />
                    Elimina Garanzia
                  </Button>
                </AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader>
                    <AlertDialogTitle>Conferma eliminazione</AlertDialogTitle>
                    <AlertDialogDescription>
                      Sei sicuro di voler eliminare questa garanzia? Questa azione non può essere annullata.
                      Verranno eliminate anche tutte le condizioni associate (massimali, franchigie, esclusioni).
                    </AlertDialogDescription>
                  </AlertDialogHeader>
                  <AlertDialogFooter>
                    <AlertDialogCancel>Annulla</AlertDialogCancel>
                    <AlertDialogAction onClick={onDelete} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
                      Elimina
                    </AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            )}
          </div>
          
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)}>
              Annulla
            </Button>
            <Button onClick={handleSave}>
              Salva Modifiche
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};