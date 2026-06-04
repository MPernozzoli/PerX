import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Loader2, CheckCircle, AlertCircle, Edit3, Save, X, Plus, Trash2 } from 'lucide-react';
import type { AIExtractedData } from '@/hooks/useAIExtractPolicy';
import { toast } from 'sonner';

interface AIProcessingModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirm: (data: AIExtractedData) => void;
  onCancel: () => void;
  processing: boolean;
  extractedData: AIExtractedData | null;
  partialData?: AIExtractedData | null;
  progress?: { current: number; total: number };
  currentChunk?: string;
}

export const AIProcessingModal = ({
  open,
  onOpenChange,
  onConfirm,
  onCancel,
  processing,
  extractedData,
  partialData,
  progress,
  currentChunk
}: AIProcessingModalProps) => {
  const [editedData, setEditedData] = useState<AIExtractedData | null>(null);
  const [activeTab, setActiveTab] = useState('coverage');
  const [editingSection, setEditingSection] = useState<string | null>(null);

  // Initialize edited data when extracted data changes
  useEffect(() => {
    if (extractedData) {
      setEditedData(JSON.parse(JSON.stringify(extractedData))); // Deep clone
    }
  }, [extractedData]);

  const handleSave = () => {
    if (editedData) {
      onConfirm(editedData);
    }
  };

  const handleCancel = () => {
    setEditedData(null);
    setEditingSection(null);
    onCancel();
  };

  const updateCoverageField = (field: string, value: any) => {
    if (!editedData) return;
    setEditedData({
      ...editedData,
      coverage_updates: {
        ...editedData.coverage_updates,
        [field]: value
      }
    });
  };

  const updateSection = (index: number, field: string, value: any) => {
    if (!editedData) return;
    const updatedSections = [...editedData.sections_to_create];
    updatedSections[index] = {
      ...updatedSections[index],
      [field]: value
    };
    setEditedData({
      ...editedData,
      sections_to_create: updatedSections
    });
  };

  const removeSection = (index: number) => {
    if (!editedData) return;
    const updatedSections = editedData.sections_to_create.filter((_, i) => i !== index);
    setEditedData({
      ...editedData,
      sections_to_create: updatedSections
    });
  };

  const addSection = () => {
    if (!editedData) return;
    const newSection = {
      party: 'fabbricato' as const,
      exact_name: 'Nuova Partita',
      emoji: '🏠',
      definition: '<p>Definizione della partita</p>',
      value_type: 'valore_intero' as const,
      deroga_percentage: 10,
      determinazione: ['A Nuovo'],
      notes: []
    };
    setEditedData({
      ...editedData,
      sections_to_create: [...editedData.sections_to_create, newSection]
    });
  };

  const updateGuarantee = (index: number, field: string, value: any) => {
    if (!editedData) return;
    const updatedGuarantees = [...editedData.guarantees_to_create];
    updatedGuarantees[index] = {
      ...updatedGuarantees[index],
      [field]: value
    };
    setEditedData({
      ...editedData,
      guarantees_to_create: updatedGuarantees
    });
  };

  const removeGuarantee = (index: number) => {
    if (!editedData) return;
    const updatedGuarantees = editedData.guarantees_to_create.filter((_, i) => i !== index);
    setEditedData({
      ...editedData,
      guarantees_to_create: updatedGuarantees
    });
  };

  const addGuarantee = () => {
    if (!editedData) return;
    const newGuarantee = {
      guarantee_name: 'Nuova Garanzia',
      guarantee_group: 'INC' as const,
      order_index: editedData.guarantees_to_create.length,
      maximum_value: 'Su frontespizio',
      maximum_applies_to: 'per sinistro',
      deductible_value: 'Su frontespizio',
      deductible_applies_to: 'per sinistro',
      available_parties_refs: [],
      common_exclusions: [],
      guarantee_exclusions: []
    };
    setEditedData({
      ...editedData,
      guarantees_to_create: [...editedData.guarantees_to_create, newGuarantee]
    });
  };

  if (!open) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-6xl max-h-[90vh] overflow-hidden">
        <DialogHeader>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              {processing ? (
                <Loader2 className="h-5 w-5 animate-spin text-primary" />
              ) : (
                <CheckCircle className="h-5 w-5 text-green-500" />
              )}
              <DialogTitle>
                {processing ? 'Elaborazione IA in corso...' : 'Risultati Estrazione IA'}
              </DialogTitle>
            </div>
            {!processing && editedData && (
              <div className="flex gap-2">
                <Button variant="outline" onClick={handleCancel}>
                  <X className="h-4 w-4 mr-2" />
                  Annulla
                </Button>
                <Button onClick={handleSave}>
                  <Save className="h-4 w-4 mr-2" />
                  Applica Modifiche
                </Button>
              </div>
            )}
          </div>
        </DialogHeader>

        {processing && (
          <div className="space-y-6">
            <div className="flex flex-col items-center justify-center py-4 space-y-4">
              <Loader2 className="h-8 w-8 animate-spin text-primary mb-4" />
              <div className="text-center space-y-2">
                <p className="text-muted-foreground">L'IA sta analizzando il PDF...</p>
                {progress && progress.total > 0 && (
                  <div className="w-full max-w-md space-y-2">
                    <div className="flex justify-between text-sm">
                      <span>Chunk {progress.current} di {progress.total}</span>
                      <span>{Math.round((progress.current / progress.total) * 100)}%</span>
                    </div>
                    <div className="w-full bg-muted rounded-full h-2">
                      <div 
                        className="bg-primary h-2 rounded-full transition-all duration-300" 
                        style={{ width: `${(progress.current / progress.total) * 100}%` }}
                      />
                    </div>
                  </div>
                )}
                {currentChunk && (
                  <p className="text-xs text-muted-foreground">
                    Elaborando: {currentChunk}
                  </p>
                )}
              </div>
            </div>

            {/* Show partial results during processing */}
            {partialData && (
              <div className="border-t pt-4">
                <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                  <CheckCircle className="h-5 w-5 text-green-500" />
                  Risultati Parziali
                </h3>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div className="bg-blue-50 p-3 rounded-lg">
                    <div className="font-medium text-blue-800">Partite Trovate</div>
                    <div className="text-2xl font-bold text-blue-600">
                      {partialData.sections_to_create.length}
                    </div>
                    {partialData.sections_to_create.slice(0, 3).map((section, i) => (
                      <div key={i} className="text-xs text-blue-700 mt-1">
                        {section.emoji} {section.exact_name}
                      </div>
                    ))}
                    {partialData.sections_to_create.length > 3 && (
                      <div className="text-xs text-blue-600 mt-1">
                        +{partialData.sections_to_create.length - 3} altre...
                      </div>
                    )}
                  </div>
                  
                  <div className="bg-green-50 p-3 rounded-lg">
                    <div className="font-medium text-green-800">Garanzie Trovate</div>
                    <div className="text-2xl font-bold text-green-600">
                      {partialData.guarantees_to_create.length}
                    </div>
                    {partialData.guarantees_to_create.slice(0, 3).map((guarantee, i) => (
                      <div key={i} className="text-xs text-green-700 mt-1">
                        {guarantee.guarantee_name}
                      </div>
                    ))}
                    {partialData.guarantees_to_create.length > 3 && (
                      <div className="text-xs text-green-600 mt-1">
                        +{partialData.guarantees_to_create.length - 3} altre...
                      </div>
                    )}
                  </div>
                </div>
                
                {partialData.common_limits_to_create.length > 0 && (
                  <div className="mt-4 bg-purple-50 p-3 rounded-lg">
                    <div className="font-medium text-purple-800">Limiti Comuni</div>
                    <div className="text-sm text-purple-600">
                      {partialData.common_limits_to_create.length} limiti trovati
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {!processing && editedData && (
          <div className="flex flex-col h-full">
            <div className="mb-4 p-3 bg-amber-50 border border-amber-200 rounded-lg">
              <div className="flex items-center gap-2 text-amber-800">
                <AlertCircle className="h-4 w-4" />
                <span className="font-medium">Attenzione</span>
              </div>
              <p className="text-sm text-amber-700 mt-1">
                L'IA può commettere errori. Verifica e modifica i dati estratti prima di applicarli alla polizza.
              </p>
            </div>

            <Tabs value={activeTab} onValueChange={setActiveTab} className="flex-1">
              <TabsList className="grid w-full grid-cols-4">
                <TabsTrigger value="coverage">
                  Copertura
                  {editedData.coverage_updates && (
                    <Badge variant="secondary" className="ml-2">
                      {Object.keys(editedData.coverage_updates).filter(k => editedData.coverage_updates[k as keyof typeof editedData.coverage_updates]).length}
                    </Badge>
                  )}
                </TabsTrigger>
                <TabsTrigger value="sections">
                  Partite
                  <Badge variant="secondary" className="ml-2">
                    {editedData.sections_to_create.length}
                  </Badge>
                </TabsTrigger>
                <TabsTrigger value="guarantees">
                  Garanzie
                  <Badge variant="secondary" className="ml-2">
                    {editedData.guarantees_to_create.length}
                  </Badge>
                </TabsTrigger>
                <TabsTrigger value="limits">
                  Limiti Comuni
                  <Badge variant="secondary" className="ml-2">
                    {editedData.common_limits_to_create.length}
                  </Badge>
                </TabsTrigger>
              </TabsList>

              <ScrollArea className="h-[500px] mt-4">
                <TabsContent value="coverage" className="space-y-4">
                  <Card>
                    <CardHeader>
                      <CardTitle className="text-lg">Aggiornamenti Copertura</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      <div>
                        <label className="text-sm font-medium">Testo Panoramica</label>
                        <Textarea 
                          value={editedData.coverage_updates?.overview_text || ''}
                          onChange={(e) => updateCoverageField('overview_text', e.target.value)}
                          rows={3}
                        />
                      </div>
                      
                      <div>
                        <label className="text-sm font-medium">Tipo Valore</label>
                        <Select 
                          value={editedData.coverage_updates?.value_type || ''}
                          onValueChange={(value) => updateCoverageField('value_type', value)}
                        >
                          <SelectTrigger>
                            <SelectValue placeholder="Seleziona tipo valore" />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="valore_intero">Valore Intero</SelectItem>
                            <SelectItem value="primo_rischio_assoluto">Primo Rischio Assoluto</SelectItem>
                            <SelectItem value="primo_rischio_assoluto_fino_a">Primo Rischio Assoluto Fino a</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>

                      {editedData.coverage_updates?.value_type === 'primo_rischio_assoluto_fino_a' && (
                        <div>
                          <label className="text-sm font-medium">Valore Primo Rischio</label>
                          <Input 
                            value={editedData.coverage_updates?.primo_rischio_value || ''}
                            onChange={(e) => updateCoverageField('primo_rischio_value', e.target.value)}
                            placeholder="es. € 50.000,00"
                          />
                        </div>
                      )}
                    </CardContent>
                  </Card>
                </TabsContent>

                <TabsContent value="sections" className="space-y-4">
                  <div className="flex justify-between items-center">
                    <h3 className="text-lg font-semibold">Partite da Creare</h3>
                    <Button onClick={addSection} size="sm">
                      <Plus className="h-4 w-4 mr-2" />
                      Aggiungi Partita
                    </Button>
                  </div>
                  
                  {editedData.sections_to_create.map((section, index) => (
                    <Card key={index} className="relative">
                      <CardHeader className="pb-3">
                        <div className="flex items-center justify-between">
                          <CardTitle className="text-base flex items-center gap-2">
                            <span>{section.emoji}</span>
                            {section.exact_name}
                          </CardTitle>
                          <Button 
                            variant="ghost" 
                            size="sm"
                            onClick={() => removeSection(index)}
                            className="text-red-500 hover:text-red-700"
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </div>
                      </CardHeader>
                      <CardContent className="space-y-3">
                        <div className="grid grid-cols-2 gap-3">
                          <div>
                            <label className="text-sm font-medium">Nome Esatto</label>
                            <Input 
                              value={section.exact_name}
                              onChange={(e) => updateSection(index, 'exact_name', e.target.value)}
                            />
                          </div>
                          <div>
                            <label className="text-sm font-medium">Emoji</label>
                            <Input 
                              value={section.emoji}
                              onChange={(e) => updateSection(index, 'emoji', e.target.value)}
                            />
                          </div>
                        </div>
                        
                        <div>
                          <label className="text-sm font-medium">Definizione</label>
                          <Textarea 
                            value={section.definition?.replace(/<[^>]*>/g, '') || ''}
                            onChange={(e) => updateSection(index, 'definition', `<p>${e.target.value}</p>`)}
                            rows={2}
                          />
                        </div>

                        <div className="grid grid-cols-2 gap-3">
                          <div>
                            <label className="text-sm font-medium">Tipo Valore</label>
                            <Select 
                              value={section.value_type || ''}
                              onValueChange={(value) => updateSection(index, 'value_type', value)}
                            >
                              <SelectTrigger>
                                <SelectValue />
                              </SelectTrigger>
                              <SelectContent>
                                <SelectItem value="valore_intero">Valore Intero</SelectItem>
                                <SelectItem value="primo_rischio_assoluto">Primo Rischio Assoluto</SelectItem>
                                <SelectItem value="primo_rischio_assoluto_fino_a">Primo Rischio Assoluto Fino a</SelectItem>
                              </SelectContent>
                            </Select>
                          </div>
                          <div>
                            <label className="text-sm font-medium">Deroga %</label>
                            <Input 
                              type="number"
                              value={section.deroga_percentage || ''}
                              onChange={(e) => updateSection(index, 'deroga_percentage', parseInt(e.target.value) || 0)}
                            />
                          </div>
                        </div>
                      </CardContent>
                    </Card>
                  ))}
                </TabsContent>

                <TabsContent value="guarantees" className="space-y-4">
                  <div className="flex justify-between items-center">
                    <h3 className="text-lg font-semibold">Garanzie da Creare</h3>
                    <Button onClick={addGuarantee} size="sm">
                      <Plus className="h-4 w-4 mr-2" />
                      Aggiungi Garanzia
                    </Button>
                  </div>
                  
                  {editedData.guarantees_to_create.map((guarantee, index) => (
                    <Card key={index} className="relative">
                      <CardHeader className="pb-3">
                        <div className="flex items-center justify-between">
                          <CardTitle className="text-base">
                            {guarantee.guarantee_name}
                            <Badge variant="outline" className="ml-2">
                              {guarantee.guarantee_group}
                            </Badge>
                          </CardTitle>
                          <Button 
                            variant="ghost" 
                            size="sm"
                            onClick={() => removeGuarantee(index)}
                            className="text-red-500 hover:text-red-700"
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </div>
                      </CardHeader>
                      <CardContent className="space-y-3">
                        <div className="grid grid-cols-2 gap-3">
                          <div>
                            <label className="text-sm font-medium">Nome Garanzia</label>
                            <Input 
                              value={guarantee.guarantee_name}
                              onChange={(e) => updateGuarantee(index, 'guarantee_name', e.target.value)}
                            />
                          </div>
                          <div>
                            <label className="text-sm font-medium">Gruppo</label>
                            <Select 
                              value={guarantee.guarantee_group}
                              onValueChange={(value) => updateGuarantee(index, 'guarantee_group', value)}
                            >
                              <SelectTrigger>
                                <SelectValue />
                              </SelectTrigger>
                              <SelectContent>
                                <SelectItem value="FE">Fenomeno Elettrico</SelectItem>
                                <SelectItem value="AC">Acqua Condotta</SelectItem>
                                <SelectItem value="FA">Fenomeni Atmosferici</SelectItem>
                                <SelectItem value="FUR">Furto</SelectItem>
                                <SelectItem value="INC">Incendio</SelectItem>
                                <SelectItem value="RC">Responsabilità Civile</SelectItem>
                                <SelectItem value="CR">Cristalli</SelectItem>
                              </SelectContent>
                            </Select>
                          </div>
                        </div>

                        <div className="grid grid-cols-2 gap-3">
                          <div>
                            <label className="text-sm font-medium">Massimale</label>
                            <Input 
                              value={guarantee.maximum_value || ''}
                              onChange={(e) => updateGuarantee(index, 'maximum_value', e.target.value)}
                              placeholder="es. € 100.000,00"
                            />
                          </div>
                          <div>
                            <label className="text-sm font-medium">Franchigia</label>
                            <Input 
                              value={guarantee.deductible_value || ''}
                              onChange={(e) => updateGuarantee(index, 'deductible_value', e.target.value)}
                              placeholder="es. € 500,00"
                            />
                          </div>
                        </div>

                        {guarantee.description && (
                          <div>
                            <label className="text-sm font-medium">Descrizione</label>
                            <Textarea 
                              value={guarantee.description?.replace(/<[^>]*>/g, '') || ''}
                              onChange={(e) => updateGuarantee(index, 'description', `<p>${e.target.value}</p>`)}
                              rows={2}
                            />
                          </div>
                        )}
                      </CardContent>
                    </Card>
                  ))}
                </TabsContent>

                <TabsContent value="limits" className="space-y-4">
                  <h3 className="text-lg font-semibold">Limiti Comuni da Creare</h3>
                  {editedData.common_limits_to_create.map((limit, index) => (
                    <Card key={index}>
                      <CardContent className="pt-4">
                        <div className="grid grid-cols-2 gap-4">
                          <div>
                            <label className="text-sm font-medium">Etichetta</label>
                            <p className="text-sm">{limit.label}</p>
                          </div>
                          <div>
                            <label className="text-sm font-medium">Valore</label>
                            <p className="text-sm">{limit.value}</p>
                          </div>
                          <div className="col-span-2">
                            <label className="text-sm font-medium">Ambito</label>
                            <p className="text-sm text-muted-foreground">{limit.scope}</p>
                          </div>
                        </div>
                      </CardContent>
                    </Card>
                  ))}
                </TabsContent>
              </ScrollArea>
            </Tabs>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
};