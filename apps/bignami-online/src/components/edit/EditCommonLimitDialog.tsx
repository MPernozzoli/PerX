import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@perx/ui/components/ui/dialog";
import { Button } from "@perx/ui/components/ui/button";
import { Input } from "@perx/ui/components/ui/input";
import { Label } from "@perx/ui/components/ui/label";
import { Checkbox } from "@perx/ui/components/ui/checkbox";
import { RichTextEditor } from "@perx/ui/components/ui/rich-text-editor";
import { CommonLimit } from "@/types";
import { SaveIcon, XIcon } from "lucide-react";

interface EditCommonLimitDialogProps {
  limit: CommonLimit;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (limit: Partial<CommonLimit>) => void;
}

export const EditCommonLimitDialog = ({ 
  limit, 
  open, 
  onOpenChange, 
  onSave 
}: EditCommonLimitDialogProps) => {
  const [formData, setFormData] = useState({
    label: limit.label || '',
    scope: limit.scope || '',
    value: limit.value || '',
    on_frontespizio: limit.on_frontespizio || false,
    page_reference: (limit as any).page_reference || '',
    article_number: (limit as any).article_number || ''
  });

  const handleSave = () => {
    const updatedLimit = {
      ...limit,
      label: formData.label,
      scope: formData.scope,
      value: formData.value,
      on_frontespizio: formData.on_frontespizio,
      page_reference: formData.page_reference,
      article_number: formData.article_number
    };
    onSave(updatedLimit);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Modifica Limite Comune</DialogTitle>
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

          {/* Etichetta */}
          <div>
            <Label htmlFor="label">Etichetta</Label>
            <Input
              id="label"
              value={formData.label}
              onChange={(e) => setFormData(prev => ({ ...prev, label: e.target.value }))}
              placeholder="Nome del limite comune"
            />
          </div>

          {/* Ambito */}
          <div>
            <Label>Ambito di Applicazione</Label>
            <RichTextEditor
              content={formData.scope}
              onChange={(content) => setFormData(prev => ({ ...prev, scope: content }))}
              placeholder="Descrivi l'ambito di applicazione del limite..."
            />
          </div>

          {/* Valore */}
          <div>
            <Label htmlFor="value">Valore</Label>
            <Input
              id="value"
              value={formData.value}
              onChange={(e) => setFormData(prev => ({ ...prev, value: e.target.value }))}
              placeholder="es. € 50.000 o 10%"
            />
          </div>

          {/* Su Frontespizio */}
          <div className="flex items-center space-x-2">
            <Checkbox
              id="on_frontespizio"
              checked={formData.on_frontespizio}
              onCheckedChange={(checked) => setFormData(prev => ({ 
                ...prev, 
                on_frontespizio: checked === true 
              }))}
            />
            <Label htmlFor="on_frontespizio">Su Frontespizio</Label>
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