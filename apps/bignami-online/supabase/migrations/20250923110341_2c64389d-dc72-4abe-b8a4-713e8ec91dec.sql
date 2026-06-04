-- Update RLS policies for comments to handle different visibility levels
DROP POLICY "Users can view comments" ON public.comments;

CREATE POLICY "Users can view public comments" 
ON public.comments 
FOR SELECT 
USING (visibility = 'public');

CREATE POLICY "Users can view their own private comments" 
ON public.comments 
FOR SELECT 
USING (visibility = 'private' AND auth.uid() = user_id);

CREATE POLICY "Studio members can view studio comments" 
ON public.comments 
FOR SELECT 
USING (
  visibility = 'studio' AND 
  EXISTS (
    SELECT 1 FROM studio_members sm1, studio_members sm2
    WHERE sm1.user_id = auth.uid() 
    AND sm2.user_id = comments.user_id
    AND sm1.studio_id = sm2.studio_id
  )
);