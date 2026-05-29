import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface EditHistory {
  id: string;
  target_id: string;
  target_type: string;
  user_id: string;
  created_at: string;
  change_summary: string;
  diff?: any;
  status: string;
  visibility: string;
  user?: {
    name: string;
    email: string;
  };
}

export const useEditHistory = (targetId: string, targetType: string) => {
  return useQuery({
    queryKey: ["edit-history", targetId, targetType],
    queryFn: async (): Promise<EditHistory[]> => {
      const { data, error } = await supabase
        .from("edit_history")
        .select("*")
        .eq("target_id", targetId)
        .eq("target_type", targetType)
        .order("created_at", { ascending: false });

      if (error) throw error;

      if (!data || data.length === 0) return [];

      // Get user profiles for all edit authors
      const userIds = [...new Set(data.map(edit => edit.user_id))];
      const { data: profiles } = await supabase
        .from("profiles")
        .select("id, name, email")
        .in("id", userIds);

      const profilesMap = (profiles || []).reduce((acc, profile) => {
        acc[profile.id] = profile;
        return acc;
      }, {} as Record<string, any>);

      return data.map(edit => ({
        ...edit,
        user: profilesMap[edit.user_id] ? {
          name: profilesMap[edit.user_id].name,
          email: profilesMap[edit.user_id].email
        } : undefined
      }));
    },
    enabled: !!targetId && !!targetType // Only run query when we have valid parameters
  });
};