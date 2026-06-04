import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useToast } from "@/hooks/use-toast";

export interface EditApproval {
  id: string;
  target_id: string;
  target_type: string;
  user_id: string;
  created_at: string;
  change_summary: string;
  diff?: any;
  status: 'pending' | 'approved' | 'rejected';
  visibility: string;
  approved_by?: string;
  approved_at?: string;
  rejection_reason?: string;
  user?: {
    name: string;
    email: string;
  };
}

export const usePendingEdits = () => {
  return useQuery({
    queryKey: ["pending-edits"],
    queryFn: async (): Promise<EditApproval[]> => {
      const { data, error } = await supabase
        .from("edit_history")
        .select("*")
        .eq("status", "pending")
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
        status: edit.status as EditApproval['status'],
        user: profilesMap[edit.user_id] ? {
          name: profilesMap[edit.user_id].name,
          email: profilesMap[edit.user_id].email
        } : undefined
      }));
    }
  });
};

export const useApproveEdit = () => {
  const queryClient = useQueryClient();
  const { toast } = useToast();

  return useMutation({
    mutationFn: async (editId: string) => {
      const { data, error } = await supabase
        .from("edit_history")
        .update({
          status: "approved",
          approved_by: (await supabase.auth.getUser()).data.user?.id!,
          approved_at: new Date().toISOString()
        })
        .eq("id", editId)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["pending-edits"] });
      toast({
        title: "Modifica approvata",
        description: "La modifica è stata approvata con successo."
      });
    },
    onError: () => {
      toast({
        title: "Errore",
        description: "Si è verificato un errore durante l'approvazione.",
        variant: "destructive"
      });
    }
  });
};

export const useRejectEdit = () => {
  const queryClient = useQueryClient();
  const { toast } = useToast();

  return useMutation({
    mutationFn: async ({ editId, reason }: { editId: string; reason: string }) => {
      const { data, error } = await supabase
        .from("edit_history")
        .update({
          status: "rejected",
          approved_by: (await supabase.auth.getUser()).data.user?.id!,
          approved_at: new Date().toISOString(),
          rejection_reason: reason
        })
        .eq("id", editId)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["pending-edits"] });
      toast({
        title: "Modifica rifiutata",
        description: "La modifica è stata rifiutata."
      });
    },
    onError: () => {
      toast({
        title: "Errore",
        description: "Si è verificato un errore durante il rifiuto.",
        variant: "destructive"
      });
    }
  });
};