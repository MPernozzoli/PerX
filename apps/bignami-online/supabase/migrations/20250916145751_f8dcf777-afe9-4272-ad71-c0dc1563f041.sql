-- Create enum for studio roles
CREATE TYPE public.studio_role AS ENUM ('admin', 'team_leader', 'moderator', 'member');

-- Create studios table
CREATE TABLE public.studios (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  invitation_code TEXT UNIQUE NOT NULL DEFAULT substring(md5(random()::text), 1, 8),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create studio members table
CREATE TABLE public.studio_members (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  studio_id UUID NOT NULL REFERENCES public.studios(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role studio_role NOT NULL DEFAULT 'member',
  companies TEXT[], -- Array of company names for team leaders
  joined_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(studio_id, user_id)
);

-- Create posts table for studio feed
CREATE TABLE public.studio_posts (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  studio_id UUID NOT NULL REFERENCES public.studios(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  tagged_users UUID[] DEFAULT '{}',
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  is_locked BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create post comments table
CREATE TABLE public.post_comments (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID NOT NULL REFERENCES public.studio_posts(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create post likes table
CREATE TABLE public.post_likes (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID NOT NULL REFERENCES public.studio_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(post_id, user_id)
);

-- Create communication formats table
CREATE TABLE public.communication_formats (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  studio_id UUID NOT NULL REFERENCES public.studios(id) ON DELETE CASCADE,
  category TEXT NOT NULL, -- 'whatsapp', 'email', 'interlocutory'
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.studios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.studio_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.studio_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communication_formats ENABLE ROW LEVEL SECURITY;

-- Create function to check studio membership and roles
CREATE OR REPLACE FUNCTION public.has_studio_role(_studio_id UUID, _user_id UUID, _role studio_role)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.studio_members
    WHERE studio_id = _studio_id 
    AND user_id = _user_id 
    AND role = _role
  )
$$;

CREATE OR REPLACE FUNCTION public.is_studio_member(_studio_id UUID, _user_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.studio_members
    WHERE studio_id = _studio_id 
    AND user_id = _user_id
  )
$$;

-- RLS Policies for studios
CREATE POLICY "Users can view studios they are members of"
ON public.studios FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.studio_members
    WHERE studio_id = studios.id AND user_id = auth.uid()
  )
);

CREATE POLICY "Admins can update studio settings"
ON public.studios FOR UPDATE
USING (
  public.has_studio_role(id, auth.uid(), 'admin')
);

-- RLS Policies for studio_members
CREATE POLICY "Members can view other members in same studio"
ON public.studio_members FOR SELECT
USING (
  public.is_studio_member(studio_id, auth.uid())
);

CREATE POLICY "Admins can manage members"
ON public.studio_members FOR ALL
USING (
  public.has_studio_role(studio_id, auth.uid(), 'admin')
);

-- RLS Policies for studio_posts
CREATE POLICY "Members can view posts in their studio"
ON public.studio_posts FOR SELECT
USING (
  public.is_studio_member(studio_id, auth.uid())
);

CREATE POLICY "Members can create posts in their studio"
ON public.studio_posts FOR INSERT
WITH CHECK (
  public.is_studio_member(studio_id, auth.uid()) AND auth.uid() = author_id
);

CREATE POLICY "Authors and moderators can update posts"
ON public.studio_posts FOR UPDATE
USING (
  author_id = auth.uid() OR 
  public.has_studio_role(studio_id, auth.uid(), 'moderator') OR
  public.has_studio_role(studio_id, auth.uid(), 'admin')
);

CREATE POLICY "Authors, moderators and admins can delete posts"
ON public.studio_posts FOR DELETE
USING (
  author_id = auth.uid() OR 
  public.has_studio_role(studio_id, auth.uid(), 'moderator') OR
  public.has_studio_role(studio_id, auth.uid(), 'admin')
);

-- RLS Policies for post_comments
CREATE POLICY "Members can view comments in their studio"
ON public.post_comments FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.studio_posts sp
    WHERE sp.id = post_comments.post_id 
    AND public.is_studio_member(sp.studio_id, auth.uid())
  )
);

CREATE POLICY "Members can create comments"
ON public.post_comments FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.studio_posts sp
    WHERE sp.id = post_comments.post_id 
    AND public.is_studio_member(sp.studio_id, auth.uid())
    AND NOT sp.is_locked
  ) AND auth.uid() = author_id
);

-- RLS Policies for post_likes
CREATE POLICY "Members can view likes in their studio"
ON public.post_likes FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.studio_posts sp
    WHERE sp.id = post_likes.post_id 
    AND public.is_studio_member(sp.studio_id, auth.uid())
  )
);

CREATE POLICY "Members can like posts"
ON public.post_likes FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.studio_posts sp
    WHERE sp.id = post_likes.post_id 
    AND public.is_studio_member(sp.studio_id, auth.uid())
  ) AND auth.uid() = user_id
);

CREATE POLICY "Users can unlike their own likes"
ON public.post_likes FOR DELETE
USING (auth.uid() = user_id);

-- RLS Policies for communication_formats
CREATE POLICY "Members can view communication formats"
ON public.communication_formats FOR SELECT
USING (
  public.is_studio_member(studio_id, auth.uid())
);

CREATE POLICY "Admins can manage communication formats"
ON public.communication_formats FOR ALL
USING (
  public.has_studio_role(studio_id, auth.uid(), 'admin')
);

-- Update triggers for timestamps
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_studios_updated_at
  BEFORE UPDATE ON public.studios
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_studio_posts_updated_at
  BEFORE UPDATE ON public.studio_posts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_communication_formats_updated_at
  BEFORE UPDATE ON public.communication_formats
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Insert sample studio
INSERT INTO public.studios (id, name, description, invitation_code)
VALUES (
  '550e8400-e29b-41d4-a716-446655440001',
  'Studio Bignami',
  'Studio professionale per periti assicurativi specializzati in fenomeni elettrici',
  'BIGNAMI1'
);