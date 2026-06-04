import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@perx/ui/components/ui/dialog";
import { Button } from "@perx/ui/components/ui/button";
import { Input } from "@perx/ui/components/ui/input";
import { Label } from "@perx/ui/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@perx/ui/components/ui/select";
import { RichTextEditor } from "@perx/ui/components/ui/rich-text-editor";
import { PartyType, ValueType } from "@/types";
import { SaveIcon, XIcon } from "lucide-react";

interface AddSectionDialogProps {
  coverageId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (sectionData: {
    party: PartyType;
    exact_name?: string;
    definition: string;
    exclusions?: string[];
    emoji?: string;
    value_type?: ValueType;
  }) => void;
}

const EMOJI_OPTIONS = [
  '🏠', '📦', '⚡', '🔧', '💻', '📋', '🏢', '🚗', '🛡️', '💰', 
  '📄', '🔒', '⚠️', '🎯', '📊', '🔥', '💧', '🌩️', '🌪️'
];

export const AddSectionDialog = ({ 
  coverageId, 
  open, 
  onOpenChange, 
  onSave 
}: AddSectionDialogProps) => {
  const [formData, setFormData] = useState({
    party: 'altro' as PartyType,
    exact_name: '',
    emoji: '📋',
    definition: '',
    exclusions: '',
    value_type: 'valore_intero' as ValueType,
  });

  const partyTypes: { value: PartyType; label: string }[] = [
    { value: 'fabbricato', label: 'Fabbricato' },
    { value: 'contenuto', label: 'Contenuto' },
    { value: 'impianti', label: 'Impianti' },
    { value: 'macchinari', label: 'Macchinari' },
    { value: 'elettronica', label: 'Elettronica' },
    { value: 'altro', label: 'Altro' }
  ];

  const updatePartyType = (value: PartyType) => {
    const selectedType = partyTypes.find(t => t.value === value);
    setFormData(prev => ({ 
      ...prev, 
      party: value,
      exact_name: prev.exact_name || selectedType?.label || ''
    }));
  };

  const handleSave = () => {
    onSave({
      party: formData.party,
      exact_name: formData.exact_name,
      definition: formData.definition,
      exclusions: formData.exclusions.split('\n').filter(e => e.trim()),
      emoji: formData.emoji,
      value_type: formData.value_type
    });
    onOpenChange(false);
    // Reset form
    setFormData({
      party: 'altro',
      exact_name: '',
      emoji: '📋',
      definition: '',
      exclusions: '',
      value_type: 'valore_intero'
    });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Aggiungi Nuova Partita</DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Tipo e Nome Esatto */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label>Tipo Partita</Label>
              <Select value={formData.party} onValueChange={updatePartyType}>
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
              <Label>Nome Esatto</Label>
              <Input
                value={formData.exact_name}
                onChange={(e) => setFormData(prev => ({ ...prev, exact_name: e.target.value }))}
                placeholder="Nome specifico della partita..."
              />
            </div>
          </div>

          {/* Icona */}
          <div className="w-1/2">
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

          {/* Tipo di Valore */}
          <div className="w-1/2">
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

          {/* Definizione */}
          <div>
            <Label>Definizione della Partita *</Label>
            <RichTextEditor
              content={formData.definition}
              onChange={(content) => setFormData(prev => ({ ...prev, definition: content }))}
              placeholder="Definisci cosa comprende questa partita..."
            />
          </div>

          {/* Esclusioni Comuni della Partita */}
          <div>
            <Label>Esclusioni Comuni della Partita</Label>
            <RichTextEditor
              content={formData.exclusions}
              onChange={(content) => setFormData(prev => ({ ...prev, exclusions: content }))}
              placeholder="Inserisci le esclusioni comuni di questa partita (una per riga)..."
            />
          </div>
        </div>

        <div className="flex justify-end gap-2 pt-4">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            <XIcon className="h-4 w-4 mr-2" />
            Annulla
          </Button>
          <Button 
            onClick={handleSave}
            disabled={!formData.definition}
          >
            <SaveIcon className="h-4 w-4 mr-2" />
            Aggiungi Partita
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};