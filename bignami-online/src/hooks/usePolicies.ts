import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import type { Policy, PolicyEdition, Coverage } from "@/types";

export const usePolicies = () => {
  return useQuery({
    queryKey: ["policies-with-coverages"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("policies")
        .select(`
          *,
          companies!inner(id, name, code, aliases),
          policy_editions(
            *,
            coverages(
              *,
              sections(*),
              common_limits(*),
              coverage_items(*)
            )
          )
        `)
        .order("created_at", { ascending: false });
      
      if (error) throw error;
      
      // Trasforma i dati per garantire che arrays vuoti siano [] invece di null
      const transformedData = (data || []).map(policy => ({
        ...policy,
        policy_editions: (policy.policy_editions || []).map(edition => ({
          ...edition,
          coverages: (edition.coverages || []).map(coverage => ({
            ...coverage,
            sections: coverage.sections || [],
            common_limits: coverage.common_limits || [],
            coverage_items: coverage.coverage_items || []
          }))
        }))
      }));
      
      return transformedData;
    },
  });
};

export const useCreatePolicy = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (policy: Omit<Policy, "id" | "created_at">) => {
      const { data, error } = await supabase
        .from("policies")
        .insert([policy])
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};

export const useCreatePolicyEdition = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (edition: Omit<PolicyEdition, "id" | "created_at">) => {
      const { data, error } = await supabase
        .from("policy_editions")
        .insert([edition])
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};

export const useUpdateCoverage = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, updates }: { id: string; updates: Partial<any> }) => {
      const { data, error } = await supabase
        .from("coverages")
        .update(updates)
        .eq("id", id)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};

export const useUpdateSection = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, updates }: { id: string; updates: Partial<any> }) => {
      const { data, error } = await supabase
        .from("sections")
        .update(updates)
        .eq("id", id)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};

export const useUpdateCommonLimit = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, updates }: { id: string; updates: Partial<any> }) => {
      const { data, error } = await supabase
        .from("common_limits")
        .update(updates)
        .eq("id", id)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};

export const useCreateSection = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (section: any) => {
      const { data, error } = await supabase
        .from("sections")
        .insert(section)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};

export const useCreateCoverage = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (coverage: Omit<Coverage, "id" | "created_at">) => {
      const { data, error } = await supabase
        .from("coverages")
        .insert(coverage)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};

export const useCreateCoverageItem = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (item: any) => {
      const { data, error } = await supabase
        .from("coverage_items")
        .insert(item)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};

export const useUpdateCoverageItem = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, updates }: { id: string; updates: Partial<any> }) => {
      const { data, error } = await supabase
        .from("coverage_items")
        .update(updates)
        .eq("id", id)
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};

export const useDeleteCoverageItem = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from("coverage_items")
        .delete()
        .eq("id", id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};

export const useDeleteSection = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from("sections")
        .delete()
        .eq("id", id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
    },
  });
};