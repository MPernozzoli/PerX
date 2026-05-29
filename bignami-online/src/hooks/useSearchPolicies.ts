import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import type { PolicyWithEditions, SearchQuery } from "@/types";

interface SearchFilters {
  company?: string;
  policy?: string;
  year?: number;
  type?: string;
  guarantee?: string;
}

export const useSearchPolicies = (query: string, filters?: SearchFilters) => {
  return useQuery({
    queryKey: ["search-policies", query, filters],
    queryFn: async (): Promise<PolicyWithEditions[]> => {
      let queryBuilder = supabase
        .from("policies")
        .select(`
          *,
          companies!inner(*),
          policy_editions!inner(
            *,
            coverages(
              *,
              sections(*),
              common_limits(*),
              coverage_items(*)
            )
          )
        `);

      // Text search across policy name, company name, and company aliases
      if (query.trim()) {
        const searchTerm = `%${query.toLowerCase()}%`;
        queryBuilder = queryBuilder.or(
          `name.ilike.${searchTerm},companies.name.ilike.${searchTerm},companies.aliases.cs.{${query.toLowerCase()}}`
        );
      }

      // Apply filters
      if (filters?.company) {
        queryBuilder = queryBuilder.eq("companies.name", filters.company);
      }

      if (filters?.type) {
        queryBuilder = queryBuilder.eq("type", filters.type);
      }

      if (filters?.year) {
        queryBuilder = queryBuilder.eq("policy_editions.year", filters.year);
      }

      const { data, error } = await queryBuilder
        .eq("policy_editions.status", "published")
        .order("created_at", { ascending: false });

      if (error) throw error;

      // Transform data to match PolicyWithEditions interface
      return (data || []).map(policy => ({
        ...policy,
        type: policy.type as 'domestica' | 'azienda' | 'agricola',
        company: policy.companies,
        editions: policy.policy_editions.map(edition => ({
          ...edition,
          status: edition.status as 'draft' | 'published'
        })) || [],
        latestEdition: policy.policy_editions?.sort((a, b) => b.year - a.year)[0] ? {
          ...policy.policy_editions.sort((a, b) => b.year - a.year)[0],
          status: policy.policy_editions.sort((a, b) => b.year - a.year)[0].status as 'draft' | 'published'
        } : undefined
      }));
    },
    enabled: !!query.trim() || !!Object.values(filters || {}).some(Boolean)
  });
};