import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { RichTextEditor } from "@/components/ui/rich-text-editor";
import { Coverage, ValueType } from "@/types";
import { SaveIcon, XIcon } from "lucide-react";

interface EditCoverageDialogProps {
  coverage: Coverage;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (coverage: Partial<Coverage>) => void;
}

export const EditCoverageDialog = ({ 
  coverage, 
  open, 
  onOpenChange, 
  onSave 
}: EditCoverageDialogProps) => {
  const [formData, setFormData] = useState({
    overview_text: coverage.overview_text || '',
    definitions: coverage.definitions?.join('\n') || '',
    common_exclusions: coverage.common_exclusions?.join('\n') || '',
    common_interpretations: coverage.common_interpretations?.join('\n') || '',
    common_notes: coverage.common_notes?.join('\n') || '',
    value_type: coverage.value_type || 'valore_intero' as ValueType,
    primo_rischio_value: coverage.primo_rischio_value || '',
    page_reference: coverage.page_reference || '',
    article_number: coverage.article_number || ''
  });

  const handleSave = () => {
    const updatedCoverage = {
      id: coverage.id,
      overview_text: formData.overview_text,
      definitions: formData.definitions ? formData.definitions.split('\n').filter(d => d.trim()) : [],
      common_exclusions: formData.common_exclusions ? formData.common_exclusions.split('\n').filter(e => e.trim()) : [],
      common_interpretations: formData.common_interpretations ? formData.common_interpretations.split('\n').filter(i => i.trim()) : [],
      common_notes: formData.common_notes ? formData.common_notes.split('\n').filter(n => n.trim()) : [],
      value_type: formData.value_type,
      primo_rischio_value: formData.primo_rischio_value || null,
      page_reference: formData.page_reference || null,
      article_number: formData.article_number || null
    };
    onSave(updatedCoverage);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Modifica Coverage - {coverage.guarantee}</DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Riferimenti */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label htmlFor="page_reference">Pagina</Label>
              <Input
                id="page_reference"
                value={formData.page_reference}
                onChange={(e) => setFormData(prev => ({ ...prev, page_reference: e.target.value }))}
                placeholder="es. 15"
              />
            </div>
            <div>
              <Label htmlFor="article_number">N° Articolo</Label>
              <Input
                id="article_number"
                value={formData.article_number}
                onChange={(e) => setFormData(prev => ({ ...prev, article_number: e.target.value }))}
                placeholder="es. Art. 2.1"
              />
            </div>
          </div>

          {/* Tipo di Valore */}
          <div className="grid grid-cols-2 gap-4">
            <div>
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
              <div>
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

          {/* Testo Overview */}
          <div>
            <Label>Testo Overview</Label>
            <RichTextEditor
              content={formData.overview_text}
              onChange={(content) => setFormData(prev => ({ ...prev, overview_text: content }))}
              placeholder="Descrivi la coverage..."
            />
          </div>

          {/* Definizioni */}
          <div>
            <Label>Definizioni (una per riga)</Label>
            <RichTextEditor
              content={formData.definitions}
              onChange={(content) => setFormData(prev => ({ ...prev, definitions: content }))}
              placeholder="Inserisci le definizioni..."
            />
          </div>

          {/* Esclusioni Comuni */}
          <div>
            <Label>Esclusioni Comuni (una per riga)</Label>
            <RichTextEditor
              content={formData.common_exclusions}
              onChange={(content) => setFormData(prev => ({ ...prev, common_exclusions: content }))}
              placeholder="Inserisci le esclusioni..."
            />
          </div>

          {/* Interpretazioni Comuni */}
          <div>
            <Label>Interpretazioni Comuni (una per riga)</Label>
            <RichTextEditor
              content={formData.common_interpretations}
              onChange={(content) => setFormData(prev => ({ ...prev, common_interpretations: content }))}
              placeholder="Inserisci le interpretazioni..."
            />
          </div>

          {/* Note Comuni */}
          <div>
            <Label>Note Comuni (una per riga)</Label>
            <RichTextEditor
              content={formData.common_notes}
              onChange={(content) => setFormData(prev => ({ ...prev, common_notes: content }))}
              placeholder="Inserisci le note..."
            />
          </div>
        </div>

        <div className="flex justify-end gap-2 pt-4">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            <XIcon className="h-4 w-4 mr-2" />
            Annulla
          </Button>
          <Button onClick={handleSave}>
            <SaveIcon className="h-4 w-4 mr-2" />
            Salva
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};