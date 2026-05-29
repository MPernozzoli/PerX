import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface GuaranteeGroup {
  id: string;
  code: string;
  name: string;
  is_active: boolean;
}

export const useGuaranteeGroups = () => {
  return useQuery({
    queryKey: ["guarantee-groups"],
    queryFn: async (): Promise<GuaranteeGroup[]> => {
      const { data, error } = await supabase
        .from("guarantee_groups")
        .select("*")
        .eq("is_active", true)
        .order("code");
      
      if (error) throw error;
      return data || [];
    },
  });
};