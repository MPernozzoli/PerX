import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { RichTextEditor } from "@/components/ui/rich-text-editor";
import { Section, PartyType, InsuranceValueType, ValueType } from "@/types";
import { SaveIcon, XIcon, TrashIcon } from "lucide-react";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog";

interface EditSectionDialogProps {
  section: Section;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (section: Partial<Section>) => void;
  onDelete?: () => void;
}

export const EditSectionDialog = ({ 
  section, 
  open, 
  onOpenChange, 
  onSave,
  onDelete 
}: EditSectionDialogProps) => {
  const [formData, setFormData] = useState({
    party: section.party,
    exact_name: section.exact_name || '',
    definition: section.definition || '',
    exclusions: section.exclusions?.join('\n') || '',
    emoji: section.emoji || '📋',
    value_type: section.value_type || 'valore_intero' as ValueType,
    deroga_percentage: section.deroga_percentage || 0,
    determinazione: section.determinazione || [],
  });

  const partyTypes: { value: PartyType; label: string }[] = [
    { value: 'fabbricato', label: 'Fabbricato' },
    { value: 'contenuto', label: 'Contenuto' },
    { value: 'impianti', label: 'Impianti' },
    { value: 'macchinari', label: 'Macchinari' },
    { value: 'elettronica', label: 'Elettronica' },
    { value: 'altro', label: 'Altro' }
  ];

  const EMOJI_OPTIONS = [
    '🏠', '📦', '⚡', '🔧', '💻', '📋', '🏢', '🚗', '🛡️', '💰', 
    '📄', '🔒', '⚠️', '🎯', '📊', '🔥', '💧', '🌩️', '🌪️'
  ];

  const insuranceValueTypes: { value: InsuranceValueType; label: string }[] = [
    { value: 'exact', label: 'Valore Esatto' },
    { value: 'frontespizio', label: 'Su Frontespizio' },
    { value: 'comune_a_piu_partite', label: 'Comune a più partite' },
    { value: 'coincide_valore_assicurato', label: 'Coincide con valore assicurato della partita' }
  ];

  const handleSave = () => {
    const updatedSection = {
      ...section,
      party: formData.party,
      exact_name: formData.exact_name,
      definition: formData.definition,
      exclusions: formData.exclusions.split('\n').filter(e => e.trim()),
      emoji: formData.emoji,
      value_type: formData.value_type,
      deroga_percentage: formData.value_type !== 'primo_rischio_assoluto' ? formData.deroga_percentage : null,
      determinazione: formData.determinazione,
    };
    onSave(updatedSection);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Modifica Sezione - {section.party}</DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Tipo e Emoji */}
          <div className="grid grid-cols-3 gap-4">
            <div>
              <Label>Tipo Partita</Label>
              <Select value={formData.party} onValueChange={(value: PartyType) => setFormData(prev => ({ ...prev, party: value }))}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {partyTypes.map(type => (
                    <SelectItem key={type.value} value={type.value}>
                      {type.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            
            <div>
              <Label>Icona</Label>
              <Select value={formData.emoji} onValueChange={(value) => setFormData(prev => ({ ...prev, emoji: value }))}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {EMOJI_OPTIONS.map(emoji => (
                    <SelectItem key={emoji} value={emoji}>
                      <span className="text-xl">{emoji}</span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div>
              <Label htmlFor="exact_name">Nome Esatto</Label>
              <Input
                id="exact_name"
                value={formData.exact_name}
                onChange={(e) => setFormData(prev => ({ ...prev, exact_name: e.target.value }))}
                placeholder="Nome specifico della partita"
              />
            </div>
          </div>

          {/* Definizione */}
          <div>
            <Label>Definizione della Partita</Label>
            <RichTextEditor
              content={formData.definition}
              onChange={(content) => setFormData(prev => ({ ...prev, definition: content }))}
              placeholder="Definisci la partita..."
            />
          </div>

          {/* Tipo di Valore e Deroga */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>Tipo di Valore</Label>
              <Select value={formData.value_type} onValueChange={(value: ValueType) => setFormData(prev => ({ ...prev, value_type: value }))}>
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

            {/* Deroga - mostrata solo se NON è Primo Rischio Assoluto */}
            {formData.value_type !== 'primo_rischio_assoluto' && (
              <div>
                <Label>Deroga (%)</Label>
                <Input
                  type="number"
                  value={formData.deroga_percentage}
                  onChange={(e) => setFormData(prev => ({ ...prev, deroga_percentage: Number(e.target.value) }))}
                  placeholder="Percentuale deroga"
                  min="0"
                  max="100"
                />
              </div>
            )}
          </div>

          {/* Determinazione */}
          <div>
            <Label>Determinazione</Label>
            <div className="flex gap-2 mt-2">
              {['Valore a Nuovo', 'Valore Reale'].map((det) => (
                <div key={det} className="flex items-center space-x-2">
                  <input
                    type="checkbox"
                    id={`det-${det}`}
                    checked={formData.determinazione.includes(det)}
                    onChange={(e) => {
                      if (e.target.checked) {
                        setFormData(prev => ({ 
                          ...prev, 
                          determinazione: [...prev.determinazione, det] 
                        }));
                      } else {
                        setFormData(prev => ({ 
                          ...prev, 
                          determinazione: prev.determinazione.filter(d => d !== det) 
                        }));
                      }
                    }}
                    className="rounded"
                  />
                  <Label htmlFor={`det-${det}`} className="text-sm font-normal">
                    {det}
                  </Label>
                </div>
              ))}
            </div>
          </div>

          {/* Esclusioni Comuni della Partita */}
          <div>
            <Label>Esclusioni Comuni della Partita</Label>
            <RichTextEditor
              content={formData.exclusions}
              onChange={(content) => setFormData(prev => ({ ...prev, exclusions: content }))}
              placeholder="Inserisci le esclusioni comuni della partita (una per riga)..."
            />
          </div>
        </div>

        <div className="flex justify-between pt-4">
          <div>
            {onDelete && (
              <AlertDialog>
                <AlertDialogTrigger asChild>
                  <Button variant="destructive" className="gap-2">
                    <TrashIcon className="h-4 w-4" />
                    Elimina Partita
                  </Button>
                </AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader>
                    <AlertDialogTitle>Conferma eliminazione</AlertDialogTitle>
                    <AlertDialogDescription>
                      Sei sicuro di voler eliminare questa partita? Questa azione non può essere annullata.
                      Verranno eliminate anche tutte le condizioni delle garanzie associate a questa partita.
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
              <XIcon className="h-4 w-4 mr-2" />
              Annulla
            </Button>
            <Button onClick={handleSave}>
              <SaveIcon className="h-4 w-4 mr-2" />
              Salva
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};