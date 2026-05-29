import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export const usePolicyByCode = (companyCode?: string, policyCode?: string, editionCode?: string) => {
  return useQuery({
    queryKey: ["policy-by-code", companyCode, policyCode, editionCode],
    queryFn: async () => {
      if (!companyCode || !policyCode) return null;
      
      let query = supabase
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
        .eq("companies.code", companyCode)
        .eq("code", policyCode)
        .single();
        
      const { data: policy, error } = await query;
      
      if (error) throw error;
      if (!policy) return null;
      
      // Transform the data to ensure empty arrays are [] instead of null
      const transformedPolicy = {
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
      };
      
      // If edition code is specified, find that specific edition
      let activeEdition = null;
      if (editionCode) {
        activeEdition = transformedPolicy.policy_editions.find(ed => ed.code === editionCode);
      }
      
      return {
        policy: transformedPolicy,
        activeEdition,
        editions: transformedPolicy.policy_editions
      };
    },
    enabled: !!companyCode && !!policyCode,
  });
};