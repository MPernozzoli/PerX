import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { GuaranteeMaximum, GuaranteeDeductible, GuaranteeExclusionGroup, GuaranteeDamageDefinition } from "@/types";

// Hook for fetching guarantee maximums
export const useGuaranteeMaximums = (coverageItemId: string) => {
  return useQuery({
    queryKey: ['guarantee-maximums', coverageItemId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('guarantee_maximums')
        .select('*')
        .eq('coverage_item_id', coverageItemId)
        .order('order_index', { ascending: true });
      
      if (error) throw error;
      return data as GuaranteeMaximum[];
    },
    enabled: !!coverageItemId
  });
};

// Hook for fetching guarantee deductibles
export const useGuaranteeDeductibles = (coverageItemId: string) => {
  return useQuery({
    queryKey: ['guarantee-deductibles', coverageItemId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('guarantee_deductibles')
        .select('*')
        .eq('coverage_item_id', coverageItemId)
        .order('order_index', { ascending: true });
      
      if (error) throw error;
      return data as GuaranteeDeductible[];
    },
    enabled: !!coverageItemId
  });
};

// Hook for fetching guarantee exclusion groups
export const useGuaranteeExclusionGroups = (coverageItemId: string) => {
  return useQuery({
    queryKey: ['guarantee-exclusion-groups', coverageItemId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('guarantee_exclusion_groups')
        .select('*')
        .eq('coverage_item_id', coverageItemId)
        .order('order_index', { ascending: true });
      
      if (error) throw error;
      return data as GuaranteeExclusionGroup[];
    },
    enabled: !!coverageItemId
  });
};

// Hook for fetching guarantee damage definitions
export const useGuaranteeDamageDefinitions = (coverageItemId: string) => {
  return useQuery({
    queryKey: ['guarantee-damage-definitions', coverageItemId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('guarantee_damage_definitions')
        .select('*')
        .eq('coverage_item_id', coverageItemId)
        .order('order_index', { ascending: true });
      
      if (error) throw error;
      return data as GuaranteeDamageDefinition[];
    },
    enabled: !!coverageItemId
  });
};

// Mutations for creating conditions
export const useCreateGuaranteeMaximum = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (data: Omit<GuaranteeMaximum, 'id' | 'created_at'>) => {
      const { data: result, error } = await supabase
        .from('guarantee_maximums')
        .insert(data)
        .select()
        .single();
      
      if (error) throw error;
      return result;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-maximums', data.coverage_item_id] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

export const useCreateGuaranteeDeductible = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (data: Omit<GuaranteeDeductible, 'id' | 'created_at'>) => {
      const { data: result, error } = await supabase
        .from('guarantee_deductibles')
        .insert(data)
        .select()
        .single();
      
      if (error) throw error;
      return result;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-deductibles', data.coverage_item_id] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

export const useCreateGuaranteeExclusionGroup = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (data: Omit<GuaranteeExclusionGroup, 'id' | 'created_at'>) => {
      const { data: result, error } = await supabase
        .from('guarantee_exclusion_groups')
        .insert(data)
        .select()
        .single();
      
      if (error) throw error;
      return result;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-exclusion-groups', data.coverage_item_id] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

export const useCreateGuaranteeDamageDefinition = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (data: Omit<GuaranteeDamageDefinition, 'id' | 'created_at'>) => {
      const { data: result, error } = await supabase
        .from('guarantee_damage_definitions')
        .insert(data)
        .select()
        .single();
      
      if (error) throw error;
      return result;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-damage-definitions', data.coverage_item_id] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

// Mutations for updating conditions
export const useUpdateGuaranteeMaximum = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, updates }: { id: string; updates: Partial<GuaranteeMaximum> }) => {
      const { data, error } = await supabase
        .from('guarantee_maximums')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-maximums', data.coverage_item_id] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

export const useUpdateGuaranteeDeductible = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, updates }: { id: string; updates: Partial<GuaranteeDeductible> }) => {
      const { data, error } = await supabase
        .from('guarantee_deductibles')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-deductibles', data.coverage_item_id] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

export const useUpdateGuaranteeExclusionGroup = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, updates }: { id: string; updates: Partial<GuaranteeExclusionGroup> }) => {
      const { data, error } = await supabase
        .from('guarantee_exclusion_groups')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-exclusion-groups', data.coverage_item_id] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

export const useUpdateGuaranteeDamageDefinition = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, updates }: { id: string; updates: Partial<GuaranteeDamageDefinition> }) => {
      const { data, error } = await supabase
        .from('guarantee_damage_definitions')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-damage-definitions', data.coverage_item_id] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

// Mutations for deleting conditions
export const useDeleteGuaranteeMaximum = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('guarantee_maximums')
        .delete()
        .eq('id', id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-maximums'] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

export const useDeleteGuaranteeDeductible = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('guarantee_deductibles')
        .delete()
        .eq('id', id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-deductibles'] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

export const useDeleteGuaranteeExclusionGroup = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('guarantee_exclusion_groups')
        .delete()
        .eq('id', id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-exclusion-groups'] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};

export const useDeleteGuaranteeDamageDefinition = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('guarantee_damage_definitions')
        .delete()
        .eq('id', id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['guarantee-damage-definitions'] });
      queryClient.invalidateQueries({ queryKey: ['policies-with-coverages'] });
    }
  });
};