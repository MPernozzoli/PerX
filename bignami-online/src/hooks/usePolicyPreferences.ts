import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

interface PolicyPreferences {
  selected_guarantee_group: string;
  active_guarantees: Record<string, boolean>;
}

export const usePolicyPreferences = (policyId: string, editionId: string) => {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const { data: preferences } = useQuery({
    queryKey: ['policy-preferences', policyId, editionId, user?.id],
    queryFn: async () => {
      if (!user?.id) return null;
      
      const { data, error } = await supabase
        .from('user_policy_interactions')
        .select('selected_guarantee_group, active_guarantees')
        .eq('policy_id', policyId)
        .eq('policy_edition_id', editionId)
        .eq('user_id', user.id)
        .maybeSingle();

      if (error) throw error;
      return data;
    },
    enabled: !!user?.id && !!policyId && !!editionId,
  });

  const savePreferences = useMutation({
    mutationFn: async (newPreferences: PolicyPreferences) => {
      if (!user?.id) throw new Error('User not authenticated');

      const { data, error } = await supabase
        .from('user_policy_interactions')
        .upsert({
          policy_id: policyId,
          policy_edition_id: editionId,
          user_id: user.id,
          selected_guarantee_group: newPreferences.selected_guarantee_group,
          active_guarantees: newPreferences.active_guarantees,
          last_viewed: new Date().toISOString(),
        })
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ 
        queryKey: ['policy-preferences', policyId, editionId, user?.id] 
      });
    },
  });

  return {
    preferences,
    savePreferences: savePreferences.mutateAsync,
  };
};