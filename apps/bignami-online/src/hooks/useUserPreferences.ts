import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

interface UserPreferences {
  default_guarantee?: string;
  default_company?: string;
}

export const useUserPreferences = () => {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const { data: preferences, isLoading } = useQuery({
    queryKey: ['user-preferences', user?.id],
    queryFn: async (): Promise<UserPreferences> => {
      if (!user?.id) return {};
      
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .single();

      if (error) throw error;
      
      return {
        default_guarantee: (data as any)?.default_guarantee || 'FE',
        default_company: (data as any)?.default_company || undefined,
      };
    },
    enabled: !!user?.id,
  });

  const updatePreferences = useMutation({
    mutationFn: async (newPreferences: Partial<UserPreferences>) => {
      if (!user?.id) throw new Error('User not authenticated');

      const { data, error } = await supabase
        .from('profiles')
        .update(newPreferences as any)
        .eq('id', user.id)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ 
        queryKey: ['user-preferences', user?.id] 
      });
    },
  });

  return {
    preferences: preferences || { default_guarantee: 'FE' },
    updatePreferences: updatePreferences.mutateAsync,
    isLoading,
  };
};