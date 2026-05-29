import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { SaveIcon, XIcon } from "lucide-react";
import { ValueType } from "@/types";

interface AddGuaranteeDialogProps {
  coverageId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (guaranteeData: {
    guarantee_name: string;
    guarantee_group: string;
    // Massimale fields
    maximum_on_frontespizio?: boolean;
    maximum_exact_value?: string;
    maximum_percentage_of_party?: string;
    maximum_minimum?: string;
    maximum_maximum?: string;
    maximum_notes?: string;
    maximum_page_reference?: string;
    maximum_article_number?: string;
    maximum_applies_to?: string[];
    // Franchigia fields
    deductible_exact_value?: string;
    deductible_on_frontespizio?: boolean;
    deductible_percentage?: string;
    deductible_minimum?: string;
    deductible_maximum?: string;
    deductible_notes?: string;
    deductible_page_reference?: string;
    deductible_article_number?: string;
    deductible_applies_to?: string[];
    // Esclusioni
    guarantee_exclusions?: string[];
    exclusions_page_reference?: string;
    exclusions_article_number?: string;
    exclusions_apply_to?: string[];
  }) => void;
}

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

export const AddGuaranteeDialog = ({ 
  coverageId, 
  open, 
  onOpenChange, 
  onSave 
}: AddGuaranteeDialogProps) => {
  // Get sections for party selectors
  const { data: sectionsData, isLoading: sectionsLoading } = useQuery({
    queryKey: ['sections', coverageId],
    queryFn: async () => {
      console.log('Fetching sections for coverageId:', coverageId);
      const { data, error } = await supabase.from('sections').select('*').eq('coverage_id', coverageId);
      if (error) {
        console.error('Error fetching sections:', error);
        throw error;
      }
      console.log('Sections fetched:', data);
      return data;
    },
    enabled: !!coverageId
  });
  
  const availableParties = Array.isArray(sectionsData) ? sectionsData : [];
  
  console.log('Available parties in AddGuaranteeDialog:', availableParties);

  const [formData, setFormData] = useState({
    guarantee_name: '',
    guarantee_group: 'FE',
    
    // New guarantee details fields
    description: '',
    value_type: 'valore_intero' as ValueType,
    primo_rischio_value: '',
    common_exclusions: '' as string,
    available_parties: [] as string[],
    
    // Massimale fields
    maximum_on_frontespizio: false,
    maximum_exact_value: '',
    maximum_percentage_of_party: '',
    maximum_minimum: '',
    maximum_maximum: '',
    maximum_notes: '',
    maximum_page_reference: '',
    maximum_article_number: '',
    maximum_applies_to: [] as string[],
    
    // Franchigia fields  
    deductible_exact_value: '',
    deductible_on_frontespizio: false,
    deductible_percentage: '',
    deductible_minimum: '',
    deductible_maximum: '',
    deductible_notes: '',
    deductible_page_reference: '',
    deductible_article_number: '',
    deductible_applies_to: [] as string[],
    
    // Esclusioni
    guarantee_exclusions: '' as string,
    exclusions_page_reference: '',
    exclusions_article_number: '',
    exclusions_apply_to: [] as string[]
  });

  const updateGuaranteeGroup = (value: string) => {
    const selectedGroup = GUARANTEE_GROUPS.find(g => g.value === value);
    setFormData(prev => ({
      ...prev,
      guarantee_group: value,
      guarantee_name: prev.guarantee_name || selectedGroup?.label || ''
    }));
  };

  const handleSave = () => {
    const saveData = {
      ...formData,
      guarantee_exclusions: formData.guarantee_exclusions ? formData.guarantee_exclusions.split('\n').filter(line => line.trim()) : [],
      common_exclusions: formData.common_exclusions ? formData.common_exclusions.split('\n').filter(line => line.trim()) : [],
      available_parties: formData.available_parties.length > 0 ? formData.available_parties : null,
    };
    onSave(saveData);
    onOpenChange(false);
    
    // Reset form
    setFormData({
      guarantee_name: '',
      guarantee_group: 'FE',
      description: '',
      value_type: 'valore_intero',
      primo_rischio_value: '',
      common_exclusions: '',
      available_parties: [],
      maximum_on_frontespizio: false,
      maximum_exact_value: '',
      maximum_percentage_of_party: '',
      maximum_minimum: '',
      maximum_maximum: '',
      maximum_notes: '',
      maximum_page_reference: '',
      maximum_article_number: '',
      maximum_applies_to: [],
      deductible_exact_value: '',
      deductible_on_frontespizio: false,
      deductible_percentage: '',
      deductible_minimum: '',
      deductible_maximum: '',
      deductible_notes: '',
      deductible_page_reference: '',
      deductible_article_number: '',
      deductible_applies_to: [],
      guarantee_exclusions: '',
      exclusions_page_reference: '',
      exclusions_article_number: '',
      exclusions_apply_to: []
    });
  };

  const togglePartySelection = (partyId: string, field: 'maximum_applies_to' | 'deductible_applies_to' | 'exclusions_apply_to' | 'available_parties') => {
    setFormData(prev => ({
      ...prev,
      [field]: prev[field].includes(partyId)
        ? prev[field].filter(id => id !== partyId)
        : [...prev[field], partyId]
    }));
  };

  const selectAllParties = (field: 'maximum_applies_to' | 'deductible_applies_to' | 'exclusions_apply_to' | 'available_parties') => {
    const allPartyIds = availableParties.map(p => p.id);
    setFormData(prev => ({
      ...prev,
      [field]: prev[field].length === allPartyIds.length ? [] : allPartyIds
    }));
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-6xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Aggiungi Nuova Garanzia</DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          
          {/* Informazioni di base della garanzia */}
          <div className="space-y-4 p-4 border rounded-lg bg-blue-50/30">
            <h4 className="font-medium text-lg text-blue-800">Informazioni Garanzia</h4>
            
            {/* Gruppo e Nome Garanzia */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label htmlFor="guarantee_group">Gruppo Garanzia</Label>
                <Select value={formData.guarantee_group} onValueChange={updateGuaranteeGroup}>
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
              <div>
                <Label htmlFor="guarantee_name">Nome Esatto Garanzia *</Label>
                <Input
                  id="guarantee_name"
                  value={formData.guarantee_name}
                  onChange={(e) => setFormData(prev => ({ ...prev, guarantee_name: e.target.value }))}
                  placeholder="Nome specifico della garanzia..."
                />
              </div>
            </div>

            {/* Descrizione garanzia */}
            <div>
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

            {/* Esclusioni Comuni della Garanzia */}
            <div>
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
            <h4 className="font-medium text-lg text-yellow-800">Disponibilità per Partite</h4>
            <p className="text-sm text-muted-foreground">
              Seleziona le partite per cui questa garanzia sarà disponibile.
              Se non selezioni nulla, la garanzia sarà disponibile per tutte le partite.
            </p>
            
            {sectionsLoading ? (
              <div className="text-sm text-muted-foreground">Caricamento partite...</div>
            ) : availableParties.length === 0 ? (
              <div className="text-sm text-muted-foreground">
                Nessuna partita disponibile. Assicurati di aver creato almeno una partita prima di aggiungere garanzie.
              </div>
            ) : (
              <div className="flex flex-wrap gap-2">
                <Button
                  type="button"
                  variant={formData.available_parties.length === availableParties.length ? "default" : "outline"}
                  size="sm"
                  onClick={() => selectAllParties('available_parties')}
                >
                  {formData.available_parties.length === availableParties.length ? 'Deseleziona' : 'Seleziona'} tutte
                </Button>
                {availableParties.map((party) => (
                  <Button
                    key={party.id}
                    type="button"
                    variant={formData.available_parties.includes(party.id) ? "default" : "outline"}
                    size="sm"
                    onClick={() => togglePartySelection(party.id, 'available_parties')}
                  >
                    {party.emoji} {party.exact_name || party.party}
                  </Button>
                ))}
              </div>
            )}
          </div>

          {/* Massimale Section */}
          <div className="space-y-4 p-4 border rounded-lg bg-green-50/30">
            <h4 className="font-medium text-lg text-green-800">Massimale</h4>
            
            <div className="space-y-4">
              {/* Massimale su frontespizio */}
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="maximum_on_frontespizio"
                  checked={formData.maximum_on_frontespizio}
                  onCheckedChange={(checked) => 
                    setFormData(prev => ({ ...prev, maximum_on_frontespizio: !!checked }))}
                />
                <Label htmlFor="maximum_on_frontespizio">Su frontespizio di Polizza</Label>
              </div>

              {!formData.maximum_on_frontespizio && (
                <>
                  {/* Valore esatto */}
                  <div>
                    <Label htmlFor="maximum_exact_value">Valore Esatto (€)</Label>
                    <Input
                      id="maximum_exact_value"
                      value={formData.maximum_exact_value}
                      onChange={(e) => setFormData(prev => ({ ...prev, maximum_exact_value: e.target.value }))}
                      placeholder="es. 100000"
                    />
                  </div>

                  {/* Percentuale della partita */}
                  <div className="grid grid-cols-4 gap-4">
                    <div>
                      <Label htmlFor="maximum_percentage_of_party">% della partita</Label>
                      <Input
                        id="maximum_percentage_of_party"
                        value={formData.maximum_percentage_of_party}
                        onChange={(e) => setFormData(prev => ({ ...prev, maximum_percentage_of_party: e.target.value }))}
                        placeholder="es. 80"
                      />
                    </div>
                    <div>
                      <Label htmlFor="maximum_minimum">Minimo (€)</Label>
                      <Input
                        id="maximum_minimum"
                        value={formData.maximum_minimum}
                        onChange={(e) => setFormData(prev => ({ ...prev, maximum_minimum: e.target.value }))}
                        placeholder="es. 10000"
                      />
                    </div>
                    <div>
                      <Label htmlFor="maximum_maximum">Massimo (€)</Label>
                      <Input
                        id="maximum_maximum"
                        value={formData.maximum_maximum}
                        onChange={(e) => setFormData(prev => ({ ...prev, maximum_maximum: e.target.value }))}
                        placeholder="es. 500000"
                      />
                    </div>
                    <div>
                      <Label htmlFor="maximum_notes">Note</Label>
                      <Input
                        id="maximum_notes"
                        value={formData.maximum_notes}
                        onChange={(e) => setFormData(prev => ({ ...prev, maximum_notes: e.target.value }))}
                        placeholder="Note aggiuntive..."
                      />
                    </div>
                  </div>
                </>
              )}

              {/* Riferimenti pagina/articolo */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <Label htmlFor="maximum_page_reference">Pagina</Label>
                  <Input
                    id="maximum_page_reference"
                    value={formData.maximum_page_reference}
                    onChange={(e) => setFormData(prev => ({ ...prev, maximum_page_reference: e.target.value }))}
                    placeholder="es. Pag. 15"
                  />
                </div>
                <div>
                  <Label htmlFor="maximum_article_number">Articolo</Label>
                  <Input
                    id="maximum_article_number"
                    value={formData.maximum_article_number}
                    onChange={(e) => setFormData(prev => ({ ...prev, maximum_article_number: e.target.value }))}
                    placeholder="es. Art. 2.1"
                  />
                </div>
              </div>

              {/* Selezione partite per massimale */}
              <div>
                <Label>Applicabile a partite:</Label>
                <div className="flex flex-wrap gap-2 mt-2">
                  <Button
                    type="button"
                    variant={formData.maximum_applies_to.length === availableParties.length ? "default" : "outline"}
                    size="sm"
                    onClick={() => selectAllParties('maximum_applies_to')}
                  >
                    {formData.maximum_applies_to.length === availableParties.length ? 'Deseleziona' : 'Seleziona'} tutte
                  </Button>
                  {availableParties.map((party) => (
                    <Button
                      key={party.id}
                      type="button"
                      variant={formData.maximum_applies_to.includes(party.id) ? "default" : "outline"}
                      size="sm"
                      onClick={() => togglePartySelection(party.id, 'maximum_applies_to')}
                    >
                      {party.emoji} {party.exact_name || party.party}
                    </Button>
                  ))}
                </div>
              </div>
            </div>
          </div>

          {/* Franchigia Section */}
          <div className="space-y-4 p-4 border rounded-lg bg-orange-50/30">
            <h4 className="font-medium text-lg text-orange-800">Franchigia/Scoperto</h4>
            
            <div className="space-y-4">
              {/* Franchigia su frontespizio */}
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="deductible_on_frontespizio"
                  checked={formData.deductible_on_frontespizio}
                  onCheckedChange={(checked) => 
                    setFormData(prev => ({ ...prev, deductible_on_frontespizio: !!checked }))}
                />
                <Label htmlFor="deductible_on_frontespizio">Su frontespizio di Polizza</Label>
              </div>

              {!formData.deductible_on_frontespizio && (
                <>
                  {/* Franchigia esatta */}
                  <div>
                    <Label htmlFor="deductible_exact_value">Franchigia Esatta (€)</Label>
                    <Input
                      id="deductible_exact_value"
                      value={formData.deductible_exact_value}
                      onChange={(e) => setFormData(prev => ({ ...prev, deductible_exact_value: e.target.value }))}
                      placeholder="es. 500"
                    />
                  </div>

                  {/* Scoperto percentuale */}
                  <div className="grid grid-cols-4 gap-4">
                    <div>
                      <Label htmlFor="deductible_percentage">Scoperto (%)</Label>
                      <Input
                        id="deductible_percentage"
                        value={formData.deductible_percentage}
                        onChange={(e) => setFormData(prev => ({ ...prev, deductible_percentage: e.target.value }))}
                        placeholder="es. 10"
                      />
                    </div>
                    <div>
                      <Label htmlFor="deductible_minimum">Minimo (€)</Label>
                      <Input
                        id="deductible_minimum"
                        value={formData.deductible_minimum}
                        onChange={(e) => setFormData(prev => ({ ...prev, deductible_minimum: e.target.value }))}
                        placeholder="es. 250"
                      />
                    </div>
                    <div>
                      <Label htmlFor="deductible_maximum">Massimo (€)</Label>
                      <Input
                        id="deductible_maximum"
                        value={formData.deductible_maximum}
                        onChange={(e) => setFormData(prev => ({ ...prev, deductible_maximum: e.target.value }))}
                        placeholder="es. 2500"
                      />
                    </div>
                    <div>
                      <Label htmlFor="deductible_notes">Note</Label>
                      <Input
                        id="deductible_notes"
                        value={formData.deductible_notes}
                        onChange={(e) => setFormData(prev => ({ ...prev, deductible_notes: e.target.value }))}
                        placeholder="Note aggiuntive..."
                      />
                    </div>
                  </div>
                </>
              )}

              {/* Riferimenti pagina/articolo */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <Label htmlFor="deductible_page_reference">Pagina</Label>
                  <Input
                    id="deductible_page_reference"
                    value={formData.deductible_page_reference}
                    onChange={(e) => setFormData(prev => ({ ...prev, deductible_page_reference: e.target.value }))}
                    placeholder="es. Pag. 18"
                  />
                </div>
                <div>
                  <Label htmlFor="deductible_article_number">Articolo</Label>
                  <Input
                    id="deductible_article_number"
                    value={formData.deductible_article_number}
                    onChange={(e) => setFormData(prev => ({ ...prev, deductible_article_number: e.target.value }))}
                    placeholder="es. Art. 3.2"
                  />
                </div>
              </div>

              {/* Selezione partite per franchigia */}
              <div>
                <Label>Applicabile a partite:</Label>
                <div className="flex flex-wrap gap-2 mt-2">
                  <Button
                    type="button"
                    variant={formData.deductible_applies_to.length === availableParties.length ? "default" : "outline"}
                    size="sm"
                    onClick={() => selectAllParties('deductible_applies_to')}
                  >
                    {formData.deductible_applies_to.length === availableParties.length ? 'Deseleziona' : 'Seleziona'} tutte
                  </Button>
                  {availableParties.map((party) => (
                    <Button
                      key={party.id}
                      type="button"
                      variant={formData.deductible_applies_to.includes(party.id) ? "default" : "outline"}
                      size="sm"
                      onClick={() => togglePartySelection(party.id, 'deductible_applies_to')}
                    >
                      {party.emoji} {party.exact_name || party.party}
                    </Button>
                  ))}
                </div>
              </div>
            </div>
          </div>

          {/* Esclusioni Section */}
          <div className="space-y-4 p-4 border rounded-lg bg-red-50/30">
            <h4 className="font-medium text-lg text-red-800">Esclusioni</h4>
            
            <div className="space-y-4">
              <div>
                <Label htmlFor="guarantee_exclusions">Esclusioni (una per riga)</Label>
                <Textarea
                  id="guarantee_exclusions"
                  value={formData.guarantee_exclusions}
                  onChange={(e) => setFormData(prev => ({ ...prev, guarantee_exclusions: e.target.value }))}
                  placeholder="Inserisci le esclusioni, una per riga..."
                  rows={4}
                />
              </div>

              {/* Riferimenti pagina/articolo */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <Label htmlFor="exclusions_page_reference">Pagina</Label>
                  <Input
                    id="exclusions_page_reference"
                    value={formData.exclusions_page_reference}
                    onChange={(e) => setFormData(prev => ({ ...prev, exclusions_page_reference: e.target.value }))}
                    placeholder="es. Pag. 20"
                  />
                </div>
                <div>
                  <Label htmlFor="exclusions_article_number">Articolo</Label>
                  <Input
                    id="exclusions_article_number"
                    value={formData.exclusions_article_number}
                    onChange={(e) => setFormData(prev => ({ ...prev, exclusions_article_number: e.target.value }))}
                    placeholder="es. Art. 4.1"
                  />
                </div>
              </div>

              {/* Selezione partite per esclusioni */}
              <div>
                <Label>Applicabile a partite:</Label>
                <div className="flex flex-wrap gap-2 mt-2">
                  <Button
                    type="button"
                    variant={formData.exclusions_apply_to.length === availableParties.length ? "default" : "outline"}
                    size="sm"
                    onClick={() => selectAllParties('exclusions_apply_to')}
                  >
                    {formData.exclusions_apply_to.length === availableParties.length ? 'Deseleziona' : 'Seleziona'} tutte
                  </Button>
                  {availableParties.map((party) => (
                    <Button
                      key={party.id}
                      type="button"
                      variant={formData.exclusions_apply_to.includes(party.id) ? "default" : "outline"}
                      size="sm"
                      onClick={() => togglePartySelection(party.id, 'exclusions_apply_to')}
                    >
                      {party.emoji} {party.exact_name || party.party}
                    </Button>
                  ))}
                </div>
              </div>
            </div>
          </div>

        </div>

        <div className="flex justify-end gap-2 pt-4">
          <Button variant="outline" onClick={() => onOpenChange(false)} className="gap-2">
            <XIcon className="h-4 w-4" />
            Annulla
          </Button>
          <Button 
            onClick={handleSave} 
            disabled={!formData.guarantee_name.trim()}
            className="gap-2"
          >
            <SaveIcon className="h-4 w-4" />
            Salva Garanzia
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};