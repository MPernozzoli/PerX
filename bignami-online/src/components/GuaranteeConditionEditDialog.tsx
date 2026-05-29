import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Checkbox } from "@/components/ui/checkbox";
import { Badge } from "@/components/ui/badge";
import { RichTextEditor } from "@/components/ui/rich-text-editor";
import { GuaranteeMaximum, GuaranteeDeductible, GuaranteeExclusionGroup, GuaranteeDamageDefinition, Section } from "@/types";
import { toast } from "sonner";

interface GuaranteeConditionEditDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  condition: GuaranteeMaximum | GuaranteeDeductible | GuaranteeExclusionGroup | GuaranteeDamageDefinition | null;
  conditionType: 'maximum' | 'deductible' | 'exclusion' | 'damage_definition';
  availableParties: Section[];
  onSave: (updates: any) => Promise<void>;
}

export const GuaranteeConditionEditDialog = ({ 
  open, 
  onOpenChange, 
  condition, 
  conditionType,
  availableParties,
  onSave 
}: GuaranteeConditionEditDialogProps) => {
  const [formData, setFormData] = useState<any>({});

  useEffect(() => {
    if (condition) {
      setFormData({ ...condition });
    } else {
      setFormData({});
    }
  }, [condition]);

  const handleSave = async () => {
    try {
      await onSave(formData);
      onOpenChange(false);
      toast.success("Condizione aggiornata con successo");
    } catch (error) {
      toast.error("Errore nell'aggiornamento della condizione");
    }
  };

  const handlePartyToggle = (partyId: string, checked: boolean) => {
    const currentAppliesTo = formData.applies_to || [];
    if (checked) {
      setFormData({
        ...formData,
        applies_to: [...currentAppliesTo, partyId]
      });
    } else {
      setFormData({
        ...formData,
        applies_to: currentAppliesTo.filter((id: string) => id !== partyId)
      });
    }
  };

  const renderExclusionsEditor = () => {
    const exclusions = formData.exclusions || [""];
    
    return (
      <div className="space-y-2">
        <Label>Esclusioni</Label>
        {exclusions.map((exclusion: string, index: number) => (
          <div key={index} className="space-y-2">
            <RichTextEditor
              content={exclusion}
              onChange={(content) => {
                const newExclusions = [...exclusions];
                newExclusions[index] = content;
                setFormData({ ...formData, exclusions: newExclusions });
              }}
              placeholder={`Esclusione ${index + 1}`}
            />
            {exclusions.length > 1 && (
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => {
                  const newExclusions = exclusions.filter((_: any, i: number) => i !== index);
                  setFormData({ ...formData, exclusions: newExclusions });
                }}
                className="text-red-600 hover:text-red-800"
              >
                Rimuovi
              </Button>
            )}
          </div>
        ))}
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={() => {
            setFormData({ 
              ...formData, 
              exclusions: [...exclusions, ""] 
            });
          }}
        >
          Aggiungi Esclusione
        </Button>
      </div>
    );
  };

  if (!condition) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            Modifica {conditionType === 'maximum' ? 'Massimale' : 
                     conditionType === 'deductible' ? 'Franchigia' : 
                     conditionType === 'exclusion' ? 'Esclusioni' :
                     'Definizione dal Danno'}
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {/* Maximum fields */}
          {conditionType === 'maximum' && (
            <>
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="on_frontespizio"
                  checked={formData.on_frontespizio || false}
                  onCheckedChange={(checked) => 
                    setFormData({ ...formData, on_frontespizio: checked })
                  }
                />
                <Label htmlFor="on_frontespizio">Su frontespizio</Label>
              </div>

              {!formData.on_frontespizio && (
                <>
                  <div>
                    <Label htmlFor="exact_value">Valore Esatto (€)</Label>
                    <Input
                      id="exact_value"
                      value={formData.exact_value || ""}
                      onChange={(e) => setFormData({ ...formData, exact_value: e.target.value })}
                      placeholder="es. 10000"
                    />
                  </div>

                  <div className="grid grid-cols-3 gap-4">
                    <div>
                      <Label htmlFor="percentage_of_party">Percentuale della Partita (%)</Label>
                      <Input
                        id="percentage_of_party"
                        value={formData.percentage_of_party || ""}
                        onChange={(e) => setFormData({ ...formData, percentage_of_party: e.target.value })}
                        placeholder="es. 80"
                      />
                    </div>
                    <div>
                      <Label htmlFor="minimum_value">Valore Minimo (€)</Label>
                      <Input
                        id="minimum_value"
                        value={formData.minimum_value || ""}
                        onChange={(e) => setFormData({ ...formData, minimum_value: e.target.value })}
                        placeholder="es. 5000"
                      />
                    </div>
                    <div>
                      <Label htmlFor="maximum_value">Valore Massimo (€)</Label>
                      <Input
                        id="maximum_value"
                        value={formData.maximum_value || ""}
                        onChange={(e) => setFormData({ ...formData, maximum_value: e.target.value })}
                        placeholder="es. 50000"
                      />
                    </div>
                  </div>
                </>
              )}
            </>
          )}

          {/* Deductible fields */}
          {conditionType === 'deductible' && (
            <>
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="on_frontespizio"
                  checked={formData.on_frontespizio || false}
                  onCheckedChange={(checked) => 
                    setFormData({ ...formData, on_frontespizio: checked })
                  }
                />
                <Label htmlFor="on_frontespizio">Su frontespizio</Label>
              </div>

              {!formData.on_frontespizio && (
                <>
                  <div>
                    <Label htmlFor="exact_value">Valore Esatto (€)</Label>
                    <Input
                      id="exact_value"
                      value={formData.exact_value || ""}
                      onChange={(e) => setFormData({ ...formData, exact_value: e.target.value })}
                      placeholder="es. 500"
                    />
                  </div>

                  <div className="grid grid-cols-3 gap-4">
                    <div>
                      <Label htmlFor="percentage">Percentuale (%)</Label>
                      <Input
                        id="percentage"
                        value={formData.percentage || ""}
                        onChange={(e) => setFormData({ ...formData, percentage: e.target.value })}
                        placeholder="es. 10"
                      />
                    </div>
                    <div>
                      <Label htmlFor="minimum_value">Valore Minimo (€)</Label>
                      <Input
                        id="minimum_value"
                        value={formData.minimum_value || ""}
                        onChange={(e) => setFormData({ ...formData, minimum_value: e.target.value })}
                        placeholder="es. 250"
                      />
                    </div>
                    <div>
                      <Label htmlFor="maximum_value">Valore Massimo (€)</Label>
                      <Input
                        id="maximum_value"
                        value={formData.maximum_value || ""}
                        onChange={(e) => setFormData({ ...formData, maximum_value: e.target.value })}
                        placeholder="es. 2500"
                      />
                    </div>
                  </div>
                </>
              )}
            </>
          )}

          {/* Exclusion fields */}
          {conditionType === 'exclusion' && renderExclusionsEditor()}

          {/* Damage definition fields */}
          {conditionType === 'damage_definition' && (
            <div>
              <Label htmlFor="definition_type">Tipo di Definizione</Label>
              <Select
                value={formData.definition_type || ""}
                onValueChange={(value) => setFormData({ ...formData, definition_type: value })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Seleziona tipo" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="a_nuovo">A Nuovo</SelectItem>
                  <SelectItem value="vsu_si">VSU+SI</SelectItem>
                  <SelectItem value="massimo_doppio">Massimo il Doppio</SelectItem>
                  <SelectItem value="massimo_triplo">Massimo il Triplo</SelectItem>
                  <SelectItem value="valore_stato_uso">Valore a stato d'uso</SelectItem>
                </SelectContent>
              </Select>
            </div>
          )}

          {/* Common fields */}
          <div>
            <Label htmlFor="notes">Note</Label>
            <RichTextEditor
              content={formData.notes || ""}
              onChange={(content) => setFormData({ ...formData, notes: content })}
              placeholder="Note aggiuntive..."
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label htmlFor="page_reference">Riferimento Pagina</Label>
              <Input
                id="page_reference"
                value={formData.page_reference || ""}
                onChange={(e) => setFormData({ ...formData, page_reference: e.target.value })}
                placeholder="es. pag. 15"
              />
            </div>
            <div>
              <Label htmlFor="article_number">Numero Articolo</Label>
              <Input
                id="article_number"
                value={formData.article_number || ""}
                onChange={(e) => setFormData({ ...formData, article_number: e.target.value })}
                placeholder="es. art. 12"
              />
            </div>
          </div>

          {/* Party assignment */}
          <div>
            <Label>Applica alle Partite</Label>
            <p className="text-sm text-muted-foreground mb-2">
              Se non selezioni nessuna partita, la condizione si applicherà a tutte
            </p>
            <div className="flex flex-wrap gap-2">
              {availableParties.map((party) => {
                // Se la partita ha determinazioni, mostra una opzione per ogni combinazione
                if (party.determinazione && party.determinazione.length > 0) {
                  return party.determinazione.map((det) => {
                    const combinationKey = `${party.id}:${det}`;
                    const displayName = `${party.exact_name || party.party} (${det})`;
                    const isSelected = formData.applies_to?.includes(combinationKey) || false;
                    
                    return (
                      <div key={combinationKey} className="flex items-center space-x-2">
                        <Checkbox
                          id={`party_${combinationKey}`}
                          checked={isSelected}
                          onCheckedChange={(checked) => handlePartyToggle(combinationKey, checked as boolean)}
                        />
                        <Label htmlFor={`party_${combinationKey}`} className="flex items-center gap-1">
                          <span>{party.emoji}</span>
                          <span>{displayName}</span>
                        </Label>
                      </div>
                    );
                  });
                }
                
                // Se non ha determinazioni, mostra la partita normale
                const isSelected = formData.applies_to?.includes(party.id) || false;
                return (
                  <div key={party.id} className="flex items-center space-x-2">
                    <Checkbox
                      id={`party_${party.id}`}
                      checked={isSelected}
                      onCheckedChange={(checked) => handlePartyToggle(party.id, checked as boolean)}
                    />
                    <Label htmlFor={`party_${party.id}`} className="flex items-center gap-1">
                      <span>{party.emoji}</span>
                      <span>{party.exact_name || party.party}</span>
                    </Label>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Annulla
          </Button>
          <Button onClick={handleSave}>
            Salva Modifiche
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};