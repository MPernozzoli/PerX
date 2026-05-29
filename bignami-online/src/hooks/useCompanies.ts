import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import type { Company } from "@/types";

export const useCompanies = () => {
  return useQuery({
    queryKey: ["companies"],
    queryFn: async (): Promise<Company[]> => {
      const { data, error } = await supabase
        .from("companies")
        .select("*")
        .order("name");
      
      if (error) throw error;
      return data || [];
    },
  });
};

export const useCreateCompany = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (company: Omit<Company, "id" | "created_at">) => {
      const { data, error } = await supabase
        .from("companies")
        .insert([company])
        .select()
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["companies"] });
    },
  });
};