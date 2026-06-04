import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export type UserRole = 'admin' | 'moderator' | 'user';

export const useUserRole = (userId?: string) => {
  return useQuery({
    queryKey: ["user-role", userId],
    queryFn: async (): Promise<UserRole[]> => {
      if (!userId) return [];
      
      const { data, error } = await supabase
        .from("user_roles")
        .select("role")
        .eq("user_id", userId);

      if (error) throw error;

      return data.map(item => item.role as UserRole);
    },
    enabled: !!userId
  });
};

export const useIsAdmin = (userId?: string) => {
  const { data: roles = [] } = useUserRole(userId);
  return roles.includes('admin');
};