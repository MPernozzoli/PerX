import { Badge } from "@/components/ui/badge";
import { CoverageItem, ValueType } from "@/types";
import { 
  useGuaranteeMaximums, 
  useGuaranteeDeductibles, 
  useGuaranteeExclusionGroups,
  useGuaranteeDamageDefinitions
} from "@/hooks/useGuaranteeConditions";
import { RichTextDisplay } from "@/components/ui/rich-text-display";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

interface GuaranteeConditionsForSectionProps {
  sectionId: string;
  coverageItems: any[]; // Use any[] to avoid type issues with database types
  selectedDeterminazione?: string;
}

export const GuaranteeConditionsForSection = ({ 
  sectionId, 
  coverageItems, 
  selectedDeterminazione 
}: GuaranteeConditionsForSectionProps) => {
  
  // Get section data for determinazione logic
  const { data: sectionData } = useQuery({
    queryKey: ['section', sectionId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('sections')
        .select('*')
        .eq('id', sectionId)
        .single();
      
      if (error) throw error;
      return data;
    },
    enabled: !!sectionId
  });

  const formatMaximumDisplay = (maximum: any) => {
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

  const formatDeductibleDisplay = (deductible: any) => {
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

  const formatDamageDefinitionDisplay = (definition: any) => {
    const typeLabels = {
      'a_nuovo': 'A Nuovo',
      'vsu_si': 'VSU+SI',
      'massimo_doppio': 'Massimo il Doppio',
      'massimo_triplo': 'Massimo il Triplo',
      'valore_stato_uso': "Valore a stato d'uso"
    };
    
    return <Badge className="bg-blue-100 text-blue-800 text-xs">
      {typeLabels[definition.definition_type as keyof typeof typeLabels]}
    </Badge>;
  };

  // Helper function to check if a condition applies to this section
  const appliesToSection = (condition: any) => {
    // If applies_to is empty or null, it applies to all sections
    if (!condition.applies_to || condition.applies_to.length === 0) {
      return true;
    }
    
    // If no determinazione is selected, show all conditions for this section
    if (!selectedDeterminazione) {
      return condition.applies_to.some((apply: string) => apply.startsWith(`${sectionId}:`));
    }
    
    // If a determinazione is selected, show only conditions that apply to that specific sectionId:determinazione combination
    const targetApply = `${sectionId}:${selectedDeterminazione}`;
    return condition.applies_to.includes(targetApply);
  };

  // Helper function to check if condition should show determinazione labels
  const shouldShowDeterminazioneLabels = (condition: any, section: any) => {
    if (!condition.applies_to || selectedDeterminazione) {
      return false;
    }
    
    // Get all applies_to entries for this section
    const sectionApplies = condition.applies_to.filter((apply: string) => apply.startsWith(`${sectionId}:`));
    
    // If the section has determinazioni, check if the condition applies to all or just some
    if (section?.determinazione && section.determinazione.length > 0) {
      const sectionDeterminazioni = section.determinazione;
      const conditionDeterminazioni = sectionApplies
        .map((apply: string) => apply.split(':')[1])
        .filter(Boolean);
      
      // If condition applies to all determinazioni of this section, don't show labels
      if (conditionDeterminazioni.length === sectionDeterminazioni.length) {
        const allMatch = sectionDeterminazioni.every(det => conditionDeterminazioni.includes(det));
        if (allMatch) return false;
      }
    }
    
    return sectionApplies.length > 0;
  };

  // Helper function to get determinazione labels for a condition
  const getDeterminazioneLabels = (condition: any, section: any) => {
    if (!shouldShowDeterminazioneLabels(condition, section)) {
      return [];
    }
    
    return condition.applies_to
      .filter((apply: string) => apply.startsWith(`${sectionId}:`))
      .map((apply: string) => apply.split(':')[1])
      .filter(Boolean);
  };

  return (
    <div className="space-y-4">
      {coverageItems.map(item => {
        const GuaranteeConditions = () => {
          const { data: maximums = [] } = useGuaranteeMaximums(item.id);
          const { data: deductibles = [] } = useGuaranteeDeductibles(item.id);
          const { data: exclusionGroups = [] } = useGuaranteeExclusionGroups(item.id);
          const { data: damageDefinitions = [] } = useGuaranteeDamageDefinitions(item.id);

          // Filter conditions that apply to this section
          const applicableMaximums = maximums.filter(appliesToSection);
          const applicableDeductibles = deductibles.filter(appliesToSection);
          const applicableExclusions = exclusionGroups.filter(appliesToSection);
          const applicableDamageDefinitions = damageDefinitions.filter(appliesToSection);

          // Only show if there are applicable conditions
          if (applicableMaximums.length === 0 && applicableDeductibles.length === 0 && 
              applicableExclusions.length === 0 && applicableDamageDefinitions.length === 0) {
            return null;
          }

          return (
            <div className="border-l-4 border-primary/20 pl-4 space-y-3">
              <div className="flex items-center gap-2">
                <Badge className="bg-primary/10 text-primary text-xs">
                  {item.guarantee_group}
                </Badge>
                <span className="font-medium text-sm">{item.guarantee_name}</span>
              </div>

              {/* Massimali */}
              {applicableMaximums.length > 0 && (
                <div className="space-y-2">
                  <div className="text-xs font-medium text-green-700">Massimali:</div>
                   {applicableMaximums.map((maximum) => (
                     <div key={maximum.id} className="ml-2 space-y-1">
                       <div className="flex items-center gap-2">
                         {formatMaximumDisplay(maximum)}
                         {getDeterminazioneLabels(maximum, sectionData).map(det => (
                           <Badge key={det} variant="outline" className="text-xs">
                             {det}
                           </Badge>
                         ))}
                       </div>
                      {maximum.notes && (
                        <div className="text-xs text-muted-foreground ml-2">
                          <RichTextDisplay content={maximum.notes} />
                        </div>
                      )}
                      {(maximum.page_reference || maximum.article_number) && (
                        <div className="text-xs text-muted-foreground ml-2">
                          {maximum.page_reference && `${maximum.page_reference}`}
                          {maximum.page_reference && maximum.article_number && " - "}
                          {maximum.article_number && maximum.article_number}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}

              {/* Franchigie */}
              {applicableDeductibles.length > 0 && (
                <div className="space-y-2">
                  <div className="text-xs font-medium text-orange-700">Franchigie:</div>
                   {applicableDeductibles.map((deductible) => (
                     <div key={deductible.id} className="ml-2 space-y-1">
                       <div className="flex items-center gap-2">
                         {formatDeductibleDisplay(deductible)}
                         {getDeterminazioneLabels(deductible, sectionData).map(det => (
                           <Badge key={det} variant="outline" className="text-xs">
                             {det}
                           </Badge>
                         ))}
                       </div>
                      {deductible.notes && (
                        <div className="text-xs text-muted-foreground ml-2">
                          <RichTextDisplay content={deductible.notes} />
                        </div>
                      )}
                      {(deductible.page_reference || deductible.article_number) && (
                        <div className="text-xs text-muted-foreground ml-2">
                          {deductible.page_reference && `${deductible.page_reference}`}
                          {deductible.page_reference && deductible.article_number && " - "}
                          {deductible.article_number && deductible.article_number}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}

              {/* Esclusioni */}
              {applicableExclusions.length > 0 && (
                <div className="space-y-2">
                  <div className="text-xs font-medium text-red-700">Esclusioni Specifiche:</div>
                  {applicableExclusions.map((group) => (
                    <div key={group.id} className="ml-2 space-y-1">
                      <div className="text-xs space-y-1">
                        {group.exclusions.map((exclusion, idx) => (
                          <div key={idx} className="text-muted-foreground">
                            • <RichTextDisplay content={exclusion} />
                          </div>
                        ))}
                      </div>
                      {(group.page_reference || group.article_number) && (
                        <div className="text-xs text-muted-foreground ml-2">
                          {group.page_reference && `${group.page_reference}`}
                          {group.page_reference && group.article_number && " - "}
                          {group.article_number && group.article_number}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}

              {/* Definizioni dal Danno */}
              {applicableDamageDefinitions.length > 0 && (
                <div className="space-y-2">
                  <div className="text-xs font-medium text-blue-700">Definizione dal Danno:</div>
                   {applicableDamageDefinitions.map((definition) => (
                     <div key={definition.id} className="ml-2 space-y-1">
                       <div className="flex items-center gap-2">
                         {formatDamageDefinitionDisplay(definition)}
                         {getDeterminazioneLabels(definition, sectionData).map(det => (
                           <Badge key={det} variant="outline" className="text-xs">
                             {det}
                           </Badge>
                         ))}
                       </div>
                      {definition.notes && (
                        <div className="text-xs text-muted-foreground ml-2">
                          <RichTextDisplay content={definition.notes} />
                        </div>
                      )}
                      {(definition.page_reference || definition.article_number) && (
                        <div className="text-xs text-muted-foreground ml-2">
                          {definition.page_reference && `${definition.page_reference}`}
                          {definition.page_reference && definition.article_number && " - "}
                          {definition.article_number && definition.article_number}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        };

        return <GuaranteeConditions key={item.id} />;
      })}
      
      {coverageItems.length === 0 && (
        <div className="text-sm text-muted-foreground italic">
          Nessuna garanzia configurata
        </div>
      )}
    </div>
  );
};