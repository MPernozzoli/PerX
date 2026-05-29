import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useToast } from "@/hooks/use-toast";

export interface BulkImport {
  id: string;
  user_id: string;
  filename: string;
  file_url: string;
  status: 'pending' | 'processing' | 'completed' | 'failed';
  ai_analysis?: any;
  created_at: string;
  processed_at?: string;
  error_message?: string;
  imported_policies_count: number;
}

export const useBulkImports = () => {
  return useQuery({
    queryKey: ["bulk-imports"],
    queryFn: async (): Promise<BulkImport[]> => {
      const { data, error } = await supabase
        .from("bulk_imports")
        .select("*")
        .order("created_at", { ascending: false });

      if (error) throw error;
      return (data || []).map(item => ({
        ...item,
        status: item.status as BulkImport['status']
      }));
    }
  });
};

export const useCreateBulkImport = () => {
  const queryClient = useQueryClient();
  const { toast } = useToast();

  return useMutation({
    mutationFn: async ({ filename, file_url }: { filename: string; file_url: string }) => {
      const { data, error } = await supabase
        .from("bulk_imports")
        .insert({
          filename,
          file_url,
          user_id: (await supabase.auth.getUser()).data.user?.id!
        })
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["bulk-imports"] });
      toast({
        title: "Import avviato",
        description: "Il file Excel è stato caricato e sarà processato a breve."
      });
    },
    onError: (error: any) => {
      toast({
        title: "Errore",
        description: "Si è verificato un errore durante il caricamento del file.",
        variant: "destructive"
      });
    }
  });
};

export const useUpdateBulkImport = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, updates }: { id: string; updates: Partial<BulkImport> }) => {
      const { data, error } = await supabase
        .from("bulk_imports")
        .update(updates)
        .eq("id", id)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["bulk-imports"] });
    }
  });
};