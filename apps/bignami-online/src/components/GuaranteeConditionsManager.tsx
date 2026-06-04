import { useState } from "react";
import { Card } from "@perx/ui/components/ui/card";
import { Button } from "@perx/ui/components/ui/button";
import { Badge } from "@perx/ui/components/ui/badge";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@perx/ui/components/ui/collapsible";
import { PlusIcon, EditIcon, TrashIcon, ChevronDownIcon, ChevronRightIcon } from "lucide-react";
import { CoverageItem, GuaranteeMaximum, GuaranteeDeductible, GuaranteeExclusionGroup, GuaranteeDamageDefinition, Section } from "@/types";
import { 
  useGuaranteeMaximums, 
  useGuaranteeDeductibles, 
  useGuaranteeExclusionGroups,
  useGuaranteeDamageDefinitions,
  useCreateGuaranteeMaximum,
  useCreateGuaranteeDeductible,
  useCreateGuaranteeExclusionGroup,
  useCreateGuaranteeDamageDefinition,
  useUpdateGuaranteeMaximum,
  useUpdateGuaranteeDeductible,
  useUpdateGuaranteeExclusionGroup,
  useUpdateGuaranteeDamageDefinition,
  useDeleteGuaranteeMaximum,
  useDeleteGuaranteeDeductible,
  useDeleteGuaranteeExclusionGroup,
  useDeleteGuaranteeDamageDefinition
} from "@/hooks/useGuaranteeConditions";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { GuaranteeConditionEditDialog } from "./GuaranteeConditionEditDialog";
import { RichTextDisplay } from "@perx/ui/components/ui/rich-text-display";
import { toast } from "sonner";

interface GuaranteeConditionsManagerProps {
  guaranteeItem: CoverageItem;
  isEditMode: boolean;
}

export const GuaranteeConditionsManager = ({ guaranteeItem, isEditMode }: GuaranteeConditionsManagerProps) => {
  const [maximumsExpanded, setMaximumsExpanded] = useState(true);
  const [deductiblesExpanded, setDeductiblesExpanded] = useState(true);
  const [exclusionsExpanded, setExclusionsExpanded] = useState(true);
  const [damageDefinitionsExpanded, setDamageDefinitionsExpanded] = useState(true);
  
  // Edit dialog state
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [editingCondition, setEditingCondition] = useState<any>(null);
  const [editingConditionType, setEditingConditionType] = useState<'maximum' | 'deductible' | 'exclusion' | 'damage_definition'>('maximum');
  
  // Get available sections for assignment
  const { data: sectionsData } = useQuery({
    queryKey: ['sections', guaranteeItem.coverage_id],
    queryFn: async () => {
      const { data, error } = await supabase.from('sections').select('*').eq('coverage_id', guaranteeItem.coverage_id);
      if (error) throw error;
      return data;
    }
  });
  
  const availableParties = Array.isArray(sectionsData) ? sectionsData as Section[] : [];

  // Fetch guarantee conditions
  const { data: maximums = [] } = useGuaranteeMaximums(guaranteeItem.id);
  const { data: deductibles = [] } = useGuaranteeDeductibles(guaranteeItem.id);
  const { data: exclusionGroups = [] } = useGuaranteeExclusionGroups(guaranteeItem.id);
  const { data: damageDefinitions = [] } = useGuaranteeDamageDefinitions(guaranteeItem.id);

  // Mutations
  const createMaximum = useCreateGuaranteeMaximum();
  const createDeductible = useCreateGuaranteeDeductible();
  const createExclusionGroup = useCreateGuaranteeExclusionGroup();
  const createDamageDefinition = useCreateGuaranteeDamageDefinition();
  const updateMaximum = useUpdateGuaranteeMaximum();
  const updateDeductible = useUpdateGuaranteeDeductible();
  const updateExclusionGroup = useUpdateGuaranteeExclusionGroup();
  const updateDamageDefinition = useUpdateGuaranteeDamageDefinition();
  const deleteMaximum = useDeleteGuaranteeMaximum();
  const deleteDeductible = useDeleteGuaranteeDeductible();
  const deleteExclusionGroup = useDeleteGuaranteeExclusionGroup();
  const deleteDamageDefinition = useDeleteGuaranteeDamageDefinition();

  const formatMaximumDisplay = (maximum: GuaranteeMaximum) => {
    if (maximum.on_frontespizio) {
      return <Badge className="bg-badge-frontespizio text-white text-xs">Su frontespizio</Badge>;
    }
    
    if (maximum.exact_value) {
      return <span className="font-mono text-xs bg-green-50 text-green-800 px-2 py-1 rounded">€ {maximum.exact_value}</span>;
    }
    
    if (maximum.percentage_of_party) {
      let display = `${maximum.percentage_of_party}%`;
      if (maximum.minimum_value || maximum.maximum_value) {
        display += ' (';
        if (maximum.minimum_value) display += `min € ${maximum.minimum_value}`;
        if (maximum.minimum_value && maximum.maximum_value) display += ', ';
        if (maximum.maximum_value) display += `max € ${maximum.maximum_value}`;
        display += ')';
      }
      return <Badge className="bg-green-100 text-green-800 text-xs">{display}</Badge>;
    }
    
    return <span className="text-xs text-muted-foreground">Non specificato</span>;
  };

  const formatDeductibleDisplay = (deductible: GuaranteeDeductible) => {
    if (deductible.on_frontespizio) {
      return <Badge className="bg-badge-frontespizio text-white text-xs">Su frontespizio</Badge>;
    }
    
    if (deductible.exact_value) {
      return <span className="font-mono text-xs bg-orange-50 text-orange-800 px-2 py-1 rounded">€ {deductible.exact_value}</span>;
    }
    
    if (deductible.percentage) {
      let display = `${deductible.percentage}%`;
      if (deductible.minimum_value || deductible.maximum_value) {
        display += ' (';
        if (deductible.minimum_value) display += `min € ${deductible.minimum_value}`;
        if (deductible.minimum_value && deductible.maximum_value) display += ', ';
        if (deductible.maximum_value) display += `max € ${deductible.maximum_value}`;
        display += ')';
      }
      return <Badge className="bg-orange-100 text-orange-800 text-xs">{display}</Badge>;
    }
    
    return <span className="text-xs text-muted-foreground">Non specificato</span>;
  };

  const formatDamageDefinitionDisplay = (definition: GuaranteeDamageDefinition) => {
    const typeLabels = {
      'a_nuovo': 'A Nuovo',
      'vsu_si': 'VSU+SI',
      'massimo_doppio': 'Massimo il Doppio',
      'massimo_triplo': 'Massimo il Triplo',
      'valore_stato_uso': 'Valore a stato d\'uso'
    };
    
    return <Badge className="bg-blue-100 text-blue-800 text-xs">
      {typeLabels[definition.definition_type]}
    </Badge>;
  };

  const handleAddMaximum = async () => {
    const newMaximum = {
      coverage_item_id: guaranteeItem.id,
      on_frontespizio: false,
      order_index: maximums.length
    };
    
    try {
      const result = await createMaximum.mutateAsync(newMaximum);
      handleEditCondition(result, 'maximum');
      toast.success("Massimale aggiunto");
    } catch (error) {
      console.error("Error adding maximum:", error);
      toast.error("Errore nell'aggiungere il massimale");
    }
  };

  const handleAddDeductible = async () => {
    const newDeductible = {
      coverage_item_id: guaranteeItem.id,
      on_frontespizio: false,
      order_index: deductibles.length
    };
    
    try {
      const result = await createDeductible.mutateAsync(newDeductible);
      handleEditCondition(result, 'deductible');
      toast.success("Franchigia aggiunta");
    } catch (error) {
      console.error("Error adding deductible:", error);
      toast.error("Errore nell'aggiungere la franchigia");
    }
  };

  const handleAddDamageDefinition = async () => {
    const newDefinition = {
      coverage_item_id: guaranteeItem.id,
      definition_type: 'a_nuovo' as const,
      order_index: damageDefinitions.length
    };
    
    try {
      const result = await createDamageDefinition.mutateAsync(newDefinition);
      handleEditCondition(result, 'damage_definition');
      toast.success("Definizione dal danno aggiunta");
    } catch (error) {
      console.error("Error adding damage definition:", error);
      toast.error("Errore nell'aggiungere la definizione dal danno");
    }
  };

  const handleAddExclusionGroup = async () => {
    const newExclusion = {
      coverage_item_id: guaranteeItem.id,
      exclusions: [""],
      order_index: exclusionGroups.length
    };
    
    try {
      const result = await createExclusionGroup.mutateAsync(newExclusion);
      handleEditCondition(result, 'exclusion');
      toast.success("Gruppo di esclusioni aggiunto");
    } catch (error) {
      console.error("Error adding exclusion group:", error);
      toast.error("Errore nell'aggiungere le esclusioni");
    }
  };

  const handleEditCondition = (condition: any, type: 'maximum' | 'deductible' | 'exclusion' | 'damage_definition') => {
    setEditingCondition(condition);
    setEditingConditionType(type);
    setEditDialogOpen(true);
  };

  const handleSaveCondition = async (updates: any) => {
    if (!editingCondition) return;
    
    try {
      if (editingConditionType === 'maximum') {
        await updateMaximum.mutateAsync({ id: editingCondition.id, updates });
      } else if (editingConditionType === 'deductible') {
        await updateDeductible.mutateAsync({ id: editingCondition.id, updates });
      } else if (editingConditionType === 'exclusion') {
        await updateExclusionGroup.mutateAsync({ id: editingCondition.id, updates });
      } else if (editingConditionType === 'damage_definition') {
        await updateDamageDefinition.mutateAsync({ id: editingCondition.id, updates });
      }
    } catch (error) {
      throw error;
    }
  };

  return (
    <div className="space-y-4">
      
      {/* Maximums Section */}
      <Collapsible open={maximumsExpanded} onOpenChange={setMaximumsExpanded}>
        <CollapsibleTrigger asChild>
          <div className="flex items-center justify-between p-3 bg-green-50/30 rounded-lg border cursor-pointer hover:bg-green-50/50">
            <div className="flex items-center gap-2">
              {maximumsExpanded ? <ChevronDownIcon className="h-4 w-4" /> : <ChevronRightIcon className="h-4 w-4" />}
              <h4 className="font-medium text-green-800">Massimali ({maximums.length})</h4>
            </div>
            {isEditMode && (
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  handleAddMaximum();
                }}
                className="gap-1"
              >
                <PlusIcon className="h-3 w-3" />
                Aggiungi
              </Button>
            )}
          </div>
        </CollapsibleTrigger>
        
        <CollapsibleContent className="space-y-3 mt-2">
          {maximums.map((maximum) => (
            <Card key={maximum.id} className="p-4">
              <div className="flex items-start justify-between mb-3">
                <div className="flex items-center gap-2">
                  {formatMaximumDisplay(maximum)}
                  {maximum.notes && (
                    <span className="text-xs text-muted-foreground">- {maximum.notes}</span>
                  )}
                </div>
                {isEditMode && (
                  <div className="flex gap-1">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleEditCondition(maximum, 'maximum')}
                      className="text-green-600 hover:text-green-800"
                    >
                      <EditIcon className="h-3 w-3" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => deleteMaximum.mutate(maximum.id)}
                      className="text-red-600 hover:text-red-800"
                    >
                      <TrashIcon className="h-3 w-3" />
                    </Button>
                  </div>
                )}
              </div>
              
              {(maximum.page_reference || maximum.article_number) && (
                <div className="text-xs text-muted-foreground mb-2">
                  {maximum.page_reference && `${maximum.page_reference}`}
                  {maximum.page_reference && maximum.article_number && " - "}
                  {maximum.article_number && maximum.article_number}
                </div>
              )}
              
              {maximum.applies_to && maximum.applies_to.length > 0 && (
                <div className="flex flex-wrap gap-1">
                  {maximum.applies_to.map(sectionKey => {
                    // Gestisci sia il formato "id:determinazione" che il semplice "id"
                    const [sectionId, determinazione] = sectionKey.includes(':') 
                      ? sectionKey.split(':') 
                      : [sectionKey, null];
                    const section = availableParties.find(p => p.id === sectionId);
                    
                    if (!section) return null;
                    
                    const displayName = determinazione 
                      ? `${section.exact_name || section.party} (${determinazione})`
                      : section.exact_name || section.party;
                      
                    return (
                      <Badge key={sectionKey} variant="outline" className="text-xs">
                        {section.emoji} {displayName}
                      </Badge>
                    );
                  })}
                </div>
              )}
            </Card>
          ))}
          
          {maximums.length === 0 && (
            <div className="text-center text-muted-foreground py-4 text-sm">
              Nessun massimale configurato
            </div>
          )}
        </CollapsibleContent>
      </Collapsible>

      {/* Deductibles Section */}
      <Collapsible open={deductiblesExpanded} onOpenChange={setDeductiblesExpanded}>
        <CollapsibleTrigger asChild>
          <div className="flex items-center justify-between p-3 bg-orange-50/30 rounded-lg border cursor-pointer hover:bg-orange-50/50">
            <div className="flex items-center gap-2">
              {deductiblesExpanded ? <ChevronDownIcon className="h-4 w-4" /> : <ChevronRightIcon className="h-4 w-4" />}
              <h4 className="font-medium text-orange-800">Franchigie ({deductibles.length})</h4>
            </div>
            {isEditMode && (
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  handleAddDeductible();
                }}
                className="gap-1"
              >
                <PlusIcon className="h-3 w-3" />
                Aggiungi
              </Button>
            )}
          </div>
        </CollapsibleTrigger>
        
        <CollapsibleContent className="space-y-3 mt-2">
          {deductibles.map((deductible) => (
            <Card key={deductible.id} className="p-4">
              <div className="flex items-start justify-between mb-3">
                <div className="flex items-center gap-2">
                  {formatDeductibleDisplay(deductible)}
                  {deductible.notes && (
                    <span className="text-xs text-muted-foreground">- {deductible.notes}</span>
                  )}
                </div>
                {isEditMode && (
                  <div className="flex gap-1">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleEditCondition(deductible, 'deductible')}
                      className="text-orange-600 hover:text-orange-800"
                    >
                      <EditIcon className="h-3 w-3" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => deleteDeductible.mutate(deductible.id)}
                      className="text-red-600 hover:text-red-800"
                    >
                      <TrashIcon className="h-3 w-3" />
                    </Button>
                  </div>
                )}
              </div>
              
              {(deductible.page_reference || deductible.article_number) && (
                <div className="text-xs text-muted-foreground mb-2">
                  {deductible.page_reference && `${deductible.page_reference}`}
                  {deductible.page_reference && deductible.article_number && " - "}
                  {deductible.article_number && deductible.article_number}
                </div>
              )}
              
              {deductible.applies_to && deductible.applies_to.length > 0 && (
                <div className="flex flex-wrap gap-1">
                  {deductible.applies_to.map(sectionKey => {
                    // Gestisci sia il formato "id:determinazione" che il semplice "id"
                    const [sectionId, determinazione] = sectionKey.includes(':') 
                      ? sectionKey.split(':') 
                      : [sectionKey, null];
                    const section = availableParties.find(p => p.id === sectionId);
                    
                    if (!section) return null;
                    
                    const displayName = determinazione 
                      ? `${section.exact_name || section.party} (${determinazione})`
                      : section.exact_name || section.party;
                      
                    return (
                      <Badge key={sectionKey} variant="outline" className="text-xs">
                        {section.emoji} {displayName}
                      </Badge>
                    );
                  })}
                </div>
              )}
            </Card>
          ))}
          
          {deductibles.length === 0 && (
            <div className="text-center text-muted-foreground py-4 text-sm">
              Nessuna franchigia configurata
            </div>
          )}
        </CollapsibleContent>
      </Collapsible>

      {/* Exclusions Section */}
      <Collapsible open={exclusionsExpanded} onOpenChange={setExclusionsExpanded}>
        <CollapsibleTrigger asChild>
          <div className="flex items-center justify-between p-3 bg-red-50/30 rounded-lg border cursor-pointer hover:bg-red-50/50">
            <div className="flex items-center gap-2">
              {exclusionsExpanded ? <ChevronDownIcon className="h-4 w-4" /> : <ChevronRightIcon className="h-4 w-4" />}
              <h4 className="font-medium text-red-800">Esclusioni ({exclusionGroups.length})</h4>
            </div>
            {isEditMode && (
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  handleAddExclusionGroup();
                }}
                className="gap-1"
              >
                <PlusIcon className="h-3 w-3" />
                Aggiungi
              </Button>
            )}
          </div>
        </CollapsibleTrigger>
        
        <CollapsibleContent className="space-y-3 mt-2">
          {exclusionGroups.map((group) => (
            <Card key={group.id} className="p-4">
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1">
                  <div className="text-sm space-y-1">
                    {group.exclusions.map((exclusion, idx) => (
                      <div key={idx} className="text-muted-foreground">
                        • <RichTextDisplay content={exclusion} />
                      </div>
                    ))}
                  </div>
                </div>
                {isEditMode && (
                  <div className="flex gap-1">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleEditCondition(group, 'exclusion')}
                      className="text-red-600 hover:text-red-800"
                    >
                      <EditIcon className="h-3 w-3" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => deleteExclusionGroup.mutate(group.id)}
                      className="text-red-600 hover:text-red-800"
                    >
                      <TrashIcon className="h-3 w-3" />
                    </Button>
                  </div>
                )}
              </div>
              
              {(group.page_reference || group.article_number) && (
                <div className="text-xs text-muted-foreground mb-2">
                  {group.page_reference && `${group.page_reference}`}
                  {group.page_reference && group.article_number && " - "}
                  {group.article_number && group.article_number}
                </div>
              )}
              
              {group.applies_to && group.applies_to.length > 0 && (
                <div className="flex flex-wrap gap-1">
                  {group.applies_to.map(sectionKey => {
                    // Gestisci sia il formato "id:determinazione" che il semplice "id"
                    const [sectionId, determinazione] = sectionKey.includes(':') 
                      ? sectionKey.split(':') 
                      : [sectionKey, null];
                    const section = availableParties.find(p => p.id === sectionId);
                    
                    if (!section) return null;
                    
                    const displayName = determinazione 
                      ? `${section.exact_name || section.party} (${determinazione})`
                      : section.exact_name || section.party;
                      
                    return (
                      <Badge key={sectionKey} variant="outline" className="text-xs">
                        {section.emoji} {displayName}
                      </Badge>
                    );
                  })}
                </div>
              )}
            </Card>
          ))}
          
          {exclusionGroups.length === 0 && (
            <div className="text-center text-muted-foreground py-4 text-sm">
              Nessuna esclusione configurata
            </div>
          )}
        </CollapsibleContent>
      </Collapsible>

      {/* Damage Definitions Section */}
      <Collapsible open={damageDefinitionsExpanded} onOpenChange={setDamageDefinitionsExpanded}>
        <CollapsibleTrigger asChild>
          <div className="flex items-center justify-between p-3 bg-blue-50/30 rounded-lg border cursor-pointer hover:bg-blue-50/50">
            <div className="flex items-center gap-2">
              {damageDefinitionsExpanded ? <ChevronDownIcon className="h-4 w-4" /> : <ChevronRightIcon className="h-4 w-4" />}
              <h4 className="font-medium text-blue-800">Definizione dal Danno ({damageDefinitions.length})</h4>
            </div>
            {isEditMode && (
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  handleAddDamageDefinition();
                }}
                className="gap-1"
              >
                <PlusIcon className="h-3 w-3" />
                Aggiungi
              </Button>
            )}
          </div>
        </CollapsibleTrigger>
        
        <CollapsibleContent className="space-y-3 mt-2">
          {damageDefinitions.map((definition) => (
            <Card key={definition.id} className="p-4">
              <div className="flex items-start justify-between mb-3">
                <div className="flex items-center gap-2">
                  {formatDamageDefinitionDisplay(definition)}
                  {definition.notes && (
                    <span className="text-xs text-muted-foreground">
                      - <RichTextDisplay content={definition.notes} />
                    </span>
                  )}
                </div>
                {isEditMode && (
                  <div className="flex gap-1">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleEditCondition(definition, 'damage_definition')}
                      className="text-blue-600 hover:text-blue-800"
                    >
                      <EditIcon className="h-3 w-3" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => deleteDamageDefinition.mutate(definition.id)}
                      className="text-red-600 hover:text-red-800"
                    >
                      <TrashIcon className="h-3 w-3" />
                    </Button>
                  </div>
                )}
              </div>
              
              {(definition.page_reference || definition.article_number) && (
                <div className="text-xs text-muted-foreground mb-2">
                  {definition.page_reference && `${definition.page_reference}`}
                  {definition.page_reference && definition.article_number && " - "}
                  {definition.article_number && definition.article_number}
                </div>
              )}
              
              {definition.applies_to && definition.applies_to.length > 0 && (
                <div className="flex flex-wrap gap-1">
                  {definition.applies_to.map(sectionKey => {
                    // Gestisci sia il formato "id:determinazione" che il semplice "id"
                    const [sectionId, determinazione] = sectionKey.includes(':') 
                      ? sectionKey.split(':') 
                      : [sectionKey, null];
                    const section = availableParties.find(p => p.id === sectionId);
                    
                    if (!section) return null;
                    
                    const displayName = determinazione 
                      ? `${section.exact_name || section.party} (${determinazione})`
                      : section.exact_name || section.party;
                      
                    return (
                      <Badge key={sectionKey} variant="outline" className="text-xs">
                        {section.emoji} {displayName}
                      </Badge>
                    );
                  })}
                </div>
              )}
            </Card>
          ))}
          
          {damageDefinitions.length === 0 && (
            <div className="text-center text-muted-foreground py-4 text-sm">
              Nessuna definizione dal danno configurata
            </div>
          )}
        </CollapsibleContent>
      </Collapsible>

      {/* Edit Dialog */}
      <GuaranteeConditionEditDialog
        open={editDialogOpen}
        onOpenChange={setEditDialogOpen}
        condition={editingCondition}
        conditionType={editingConditionType}
        availableParties={availableParties}
        onSave={handleSaveCondition}
      />
    </div>
  );
};