import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface Comment {
  id: string;
  body: string;
  visibility: 'public' | 'private' | 'studio';
  created_at: string;
  user_id: string;
  target_id: string;
  target_type: string;
  parent_comment_id?: string;
  resolved: boolean;
  user?: {
    name: string;
    email: string;
  };
}

export const useComments = (targetId: string, targetType: string) => {
  return useQuery({
    queryKey: ["comments", targetId, targetType],
    queryFn: async (): Promise<Comment[]> => {
      const { data, error } = await supabase
        .from("comments")
        .select("*")
        .eq("target_id", targetId)
        .eq("target_type", targetType)
        .order("created_at", { ascending: true });

      if (error) throw error;

      if (!data || data.length === 0) return [];

      // Get user profiles for all comment authors
      const userIds = [...new Set(data.map(comment => comment.user_id))];
      const { data: profiles } = await supabase
        .from("profiles")
        .select("id, name, email")
        .in("id", userIds);

      const profilesMap = (profiles || []).reduce((acc, profile) => {
        acc[profile.id] = profile;
        return acc;
      }, {} as Record<string, any>);

      return data.map(comment => ({
        ...comment,
        visibility: comment.visibility as 'public' | 'private' | 'studio',
        resolved: comment.resolved || false,
        user: profilesMap[comment.user_id] ? {
          name: profilesMap[comment.user_id].name,
          email: profilesMap[comment.user_id].email
        } : undefined
      }));
    },
    enabled: !!targetId && !!targetType // Only run query when we have valid parameters
  });
};

export const useCreateComment = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      targetId,
      targetType,
      body,
      visibility,
      parentCommentId
    }: {
      targetId: string;
      targetType: string;
      body: string;
      visibility: 'public' | 'private' | 'studio';
      parentCommentId?: string;
    }) => {
      const { data, error } = await supabase
        .from("comments")
        .insert([{
          target_id: targetId,
          target_type: targetType,
          body,
          visibility,
          parent_comment_id: parentCommentId,
          user_id: (await supabase.auth.getUser()).data.user?.id
        }])
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({
        queryKey: ["comments", variables.targetId, variables.targetType]
      });
    },
  });
};

export const useUpdateComment = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      commentId,
      body,
      resolved
    }: {
      commentId: string;
      body?: string;
      resolved?: boolean;
    }) => {
      const updateData: any = {};
      if (body !== undefined) updateData.body = body;
      if (resolved !== undefined) updateData.resolved = resolved;

      const { data, error } = await supabase
        .from("comments")
        .update(updateData)
        .eq("id", commentId)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["comments"] });
    },
  });
};