import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import type { PolicyWithEditions } from "@/types";

export const useUserInteractions = (userId?: string) => {
  return useQuery({
    queryKey: ["user-interactions", userId],
    queryFn: async () => {
      if (!userId) return [];
      
      const { data, error } = await supabase
        .from("user_policy_interactions")
        .select("*")
        .eq("user_id", userId)
        .order("last_viewed", { ascending: false });

      if (error) throw error;
      return data || [];
    },
    enabled: !!userId
  });
};

export const useRecentPolicies = (userId?: string) => {
  return useQuery({
    queryKey: ["recent-policies", userId],
    queryFn: async (): Promise<PolicyWithEditions[]> => {
      if (!userId) return [];

      const { data: interactions, error } = await supabase
        .from("user_policy_interactions")
        .select(`
          *,
          policies!inner(
            *,
            companies(*),
            policy_editions!inner(
              *,
              coverages(
                *,
                sections(*),
                common_limits(*),
                coverage_items(*)
              )
            )
          )
        `)
        .eq("user_id", userId)
        .order("last_viewed", { ascending: false })
        .limit(5);

      if (error) throw error;

      return (interactions || []).map(interaction => {
        const policy = interaction.policies;
        const targetEdition = policy.policy_editions.find(
          ed => ed.id === interaction.policy_edition_id
        );
        
        return {
          ...policy,
          type: policy.type as 'domestica' | 'azienda' | 'agricola',
          company: policy.companies,
          editions: policy.policy_editions.map(edition => ({
            ...edition,
            status: edition.status as 'draft' | 'published'
          })) || [],
          latestEdition: targetEdition ? {
            ...targetEdition,
            status: targetEdition.status as 'draft' | 'published'
          } : policy.policy_editions[0] ? {
            ...policy.policy_editions[0],
            status: policy.policy_editions[0].status as 'draft' | 'published'
          } : undefined
        };
      });
    },
    enabled: !!userId
  });
};

export const useFrequentPolicies = (userId?: string) => {
  return useQuery({
    queryKey: ["frequent-policies", userId],
    queryFn: async (): Promise<PolicyWithEditions[]> => {
      if (!userId) return [];

      const { data: interactions, error } = await supabase
        .from("user_policy_interactions")
        .select(`
          *,
          policies!inner(
            *,
            companies(*),
            policy_editions!inner(
              *,
              coverages(
                *,
                sections(*),
                common_limits(*),
                coverage_items(*)
              )
            )
          )
        `)
        .eq("user_id", userId)
        .order("view_count", { ascending: false })
        .limit(5);

      if (error) throw error;

      return (interactions || []).map(interaction => {
        const policy = interaction.policies;
        const targetEdition = policy.policy_editions.find(
          ed => ed.id === interaction.policy_edition_id
        );
        
        return {
          ...policy,
          type: policy.type as 'domestica' | 'azienda' | 'agricola',
          company: policy.companies,
          editions: policy.policy_editions.map(edition => ({
            ...edition,
            status: edition.status as 'draft' | 'published'
          })) || [],
          latestEdition: targetEdition ? {
            ...targetEdition,
            status: targetEdition.status as 'draft' | 'published'
          } : policy.policy_editions[0] ? {
            ...policy.policy_editions[0],
            status: policy.policy_editions[0].status as 'draft' | 'published'
          } : undefined
        };
      });
    },
    enabled: !!userId
  });
};

export const useBookmarkedPolicies = (userId?: string) => {
  return useQuery({
    queryKey: ["bookmarked-policies", userId],
    queryFn: async (): Promise<PolicyWithEditions[]> => {
      if (!userId) return [];

      const { data: interactions, error } = await supabase
        .from("user_policy_interactions")
        .select(`
          *,
          policies!inner(
            *,
            companies(*),
            policy_editions!inner(
              *,
              coverages(
                *,
                sections(*),
                common_limits(*),
                coverage_items(*)
              )
            )
          )
        `)
        .eq("user_id", userId)
        .eq("bookmarked", true)
        .order("view_count", { ascending: false });

      if (error) throw error;

      return (interactions || []).map(interaction => {
        const policy = interaction.policies;
        const targetEdition = policy.policy_editions.find(
          ed => ed.id === interaction.policy_edition_id
        );
        
        return {
          ...policy,
          type: policy.type as 'domestica' | 'azienda' | 'agricola',
          company: policy.companies,
          editions: policy.policy_editions.map(edition => ({
            ...edition,
            status: edition.status as 'draft' | 'published'
          })) || [],
          latestEdition: targetEdition ? {
            ...targetEdition,
            status: targetEdition.status as 'draft' | 'published'
          } : policy.policy_editions[0] ? {
            ...policy.policy_editions[0],
            status: policy.policy_editions[0].status as 'draft' | 'published'
          } : undefined
        };
      });
    },
    enabled: !!userId
  });
};

export const useRecordInteraction = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ 
      policyId, 
      editionId, 
      userId 
    }: { 
      policyId: string;
      editionId: string; 
      userId: string;
    }) => {
      // Check if interaction exists
      const { data: existing } = await supabase
        .from("user_policy_interactions")
        .select("*")
        .eq("user_id", userId)
        .eq("policy_id", policyId)
        .eq("policy_edition_id", editionId)
        .single();

      if (existing) {
        // Update existing interaction
        const { data, error } = await supabase
          .from("user_policy_interactions")
          .update({
            last_viewed: new Date().toISOString(),
            view_count: existing.view_count + 1
          })
          .eq("id", existing.id)
          .select()
          .single();

        if (error) throw error;
        return data;
      } else {
        // Create new interaction
        const { data, error } = await supabase
          .from("user_policy_interactions")
          .insert({
            user_id: userId,
            policy_id: policyId,
            policy_edition_id: editionId,
            last_viewed: new Date().toISOString(),
            view_count: 1,
            bookmarked: false
          })
          .select()
          .single();

        if (error) throw error;
        return data;
      }
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["user-interactions", variables.userId] });
      queryClient.invalidateQueries({ queryKey: ["recent-policies", variables.userId] });
      queryClient.invalidateQueries({ queryKey: ["frequent-policies", variables.userId] });
    }
  });
};

export const useToggleBookmark = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      policyId,
      editionId,
      userId,
      bookmarked
    }: {
      policyId: string;
      editionId: string;
      userId: string;
      bookmarked: boolean;
    }) => {
      const { data, error } = await supabase
        .from("user_policy_interactions")
        .update({ bookmarked })
        .eq("user_id", userId)
        .eq("policy_id", policyId)
        .eq("policy_edition_id", editionId)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["user-interactions", variables.userId] });
      queryClient.invalidateQueries({ queryKey: ["bookmarked-policies", variables.userId] });
    }
  });
};