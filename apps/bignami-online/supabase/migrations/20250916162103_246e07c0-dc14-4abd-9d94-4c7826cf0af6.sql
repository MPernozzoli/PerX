-- Create profiles table for additional user data
CREATE TABLE public.profiles (
  id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  auth_provider TEXT DEFAULT 'email',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create companies table
CREATE TABLE public.companies (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  aliases TEXT[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create policies table
CREATE TABLE public.policies (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('domestica', 'azienda', 'agricola')),
  description TEXT NOT NULL,
  tags TEXT[] DEFAULT '{}',
  default_guarantee TEXT NOT NULL DEFAULT 'Fenomeno Elettrico',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create policy editions table
CREATE TABLE public.policy_editions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  policy_id UUID NOT NULL REFERENCES public.policies(id) ON DELETE CASCADE,
  year INTEGER NOT NULL,
  edition_label TEXT,
  pdf_url TEXT,
  pdf_sha256 TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
  canonical_group_id UUID,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create coverages table
CREATE TABLE public.coverages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  policy_edition_id UUID NOT NULL REFERENCES public.policy_editions(id) ON DELETE CASCADE,
  guarantee TEXT NOT NULL DEFAULT 'Fenomeno Elettrico',
  overview_text TEXT NOT NULL,
  definitions TEXT[] DEFAULT '{}',
  common_exclusions TEXT[] DEFAULT '{}',
  common_interpretations TEXT[] DEFAULT '{}',
  common_notes TEXT[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create sections table
CREATE TABLE public.sections (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  coverage_id UUID NOT NULL REFERENCES public.coverages(id) ON DELETE CASCADE,
  party TEXT NOT NULL CHECK (party IN ('fabbricato', 'contenuto', 'impianti', 'macchinari', 'elettronica', 'altro')),
  definition TEXT NOT NULL,
  exclusions TEXT[] DEFAULT '{}',
  sum_insured_type TEXT NOT NULL CHECK (sum_insured_type IN ('exact', 'frontespizio', 'comune_a_piu_partite')),
  sum_insured_value TEXT,
  deductible_type TEXT NOT NULL CHECK (deductible_type IN ('exact', 'frontespizio', 'comune_a_piu_partite')),
  deductible_value TEXT,
  loss_assessment TEXT NOT NULL,
  special_conditions TEXT[] DEFAULT '{}',
  notes TEXT[] DEFAULT '{}',
  links_to_common_limits TEXT[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create common limits table
CREATE TABLE public.common_limits (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  coverage_id UUID NOT NULL REFERENCES public.coverages(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  scope TEXT NOT NULL,
  value TEXT NOT NULL,
  on_frontespizio BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create edit history table
CREATE TABLE public.edit_history (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  target_type TEXT NOT NULL CHECK (target_type IN ('policy', 'policy_edition', 'coverage', 'section', 'common_limit', 'norm_ref', 'studio_template')),
  target_id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  change_summary TEXT NOT NULL,
  diff JSONB,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  visibility TEXT NOT NULL DEFAULT 'global' CHECK (visibility IN ('global', 'studio')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create comments table
CREATE TABLE public.comments (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  target_type TEXT NOT NULL CHECK (target_type IN ('policy', 'policy_edition', 'coverage', 'section', 'norm_ref')),
  target_id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  visibility TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'studio')),
  body TEXT NOT NULL,
  parent_comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  resolved BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create norm refs table
CREATE TABLE public.norm_refs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  code TEXT NOT NULL,
  article TEXT NOT NULL,
  comma TEXT,
  text TEXT NOT NULL,
  summary TEXT NOT NULL,
  tags TEXT[] DEFAULT '{}',
  links TEXT[] DEFAULT '{}',
  last_update TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create studio templates table
CREATE TABLE public.studio_templates (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  studio_id UUID NOT NULL REFERENCES public.studios(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('email', 'whatsapp', 'relazione', 'altro')),
  title TEXT NOT NULL,
  body_template TEXT NOT NULL,
  tags TEXT[] DEFAULT '{}',
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create user policy interactions table
CREATE TABLE public.user_policy_interactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  policy_id UUID NOT NULL REFERENCES public.policies(id) ON DELETE CASCADE,
  policy_edition_id UUID NOT NULL REFERENCES public.policy_editions(id) ON DELETE CASCADE,
  last_viewed TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  view_count INTEGER DEFAULT 1,
  bookmarked BOOLEAN DEFAULT FALSE,
  UNIQUE(user_id, policy_id, policy_edition_id)
);

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.policy_editions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coverages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.common_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.edit_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.norm_refs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.studio_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_policy_interactions ENABLE ROW LEVEL SECURITY;

-- Create profiles automatically when user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, name, email, auth_provider)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.raw_user_meta_data ->> 'name', NEW.email),
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'provider', 'email')
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- RLS Policies for profiles
CREATE POLICY "Users can view all profiles"
ON public.profiles FOR SELECT
USING (TRUE);

CREATE POLICY "Users can update own profile"
ON public.profiles FOR UPDATE
USING (auth.uid() = id);

-- RLS Policies for companies (public read, authenticated write)
CREATE POLICY "Anyone can view companies"
ON public.companies FOR SELECT
USING (TRUE);

CREATE POLICY "Authenticated users can manage companies"
ON public.companies FOR ALL
TO authenticated
USING (TRUE);

-- RLS Policies for policies (public read, authenticated write)
CREATE POLICY "Anyone can view policies"
ON public.policies FOR SELECT
USING (TRUE);

CREATE POLICY "Authenticated users can manage policies"
ON public.policies FOR ALL
TO authenticated
USING (TRUE);

-- RLS Policies for policy editions (public read, authenticated write)
CREATE POLICY "Anyone can view policy editions"
ON public.policy_editions FOR SELECT
USING (TRUE);

CREATE POLICY "Authenticated users can manage policy editions"
ON public.policy_editions FOR ALL
TO authenticated
USING (TRUE);

-- RLS Policies for coverages (public read, authenticated write)
CREATE POLICY "Anyone can view coverages"
ON public.coverages FOR SELECT
USING (TRUE);

CREATE POLICY "Authenticated users can manage coverages"
ON public.coverages FOR ALL
TO authenticated
USING (TRUE);

-- RLS Policies for sections (public read, authenticated write)
CREATE POLICY "Anyone can view sections"
ON public.sections FOR SELECT
USING (TRUE);

CREATE POLICY "Authenticated users can manage sections"
ON public.sections FOR ALL
TO authenticated
USING (TRUE);

-- RLS Policies for common limits (public read, authenticated write)
CREATE POLICY "Anyone can view common limits"
ON public.common_limits FOR SELECT
USING (TRUE);

CREATE POLICY "Authenticated users can manage common limits"
ON public.common_limits FOR ALL
TO authenticated
USING (TRUE);

-- RLS Policies for edit history
CREATE POLICY "Users can view edit history"
ON public.edit_history FOR SELECT
USING (TRUE);

CREATE POLICY "Users can create edit history"
ON public.edit_history FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- RLS Policies for comments
CREATE POLICY "Users can view comments"
ON public.comments FOR SELECT
USING (TRUE);

CREATE POLICY "Users can create comments"
ON public.comments FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own comments"
ON public.comments FOR UPDATE
USING (auth.uid() = user_id);

-- RLS Policies for norm refs (public read, authenticated write)
CREATE POLICY "Anyone can view norm refs"
ON public.norm_refs FOR SELECT
USING (TRUE);

CREATE POLICY "Authenticated users can manage norm refs"
ON public.norm_refs FOR ALL
TO authenticated
USING (TRUE);

-- RLS Policies for studio templates
CREATE POLICY "Studio members can view templates"
ON public.studio_templates FOR SELECT
USING (public.is_studio_member(studio_id, auth.uid()));

CREATE POLICY "Studio admins can manage templates"
ON public.studio_templates FOR ALL
USING (public.has_studio_role(studio_id, auth.uid(), 'admin'));

-- RLS Policies for user policy interactions
CREATE POLICY "Users can view own interactions"
ON public.user_policy_interactions FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own interactions"
ON public.user_policy_interactions FOR ALL
USING (auth.uid() = user_id);

-- Add update triggers for timestamps
CREATE TRIGGER update_studio_templates_updated_at
  BEFORE UPDATE ON public.studio_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Insert sample data
INSERT INTO public.companies (name, aliases) VALUES
('Generali Italia', ARRAY['Generali', 'Assicurazioni Generali']),
('Allianz', ARRAY['Allianz Spa']),
('AXA', ARRAY['AXA Assicurazioni']),
('Unipol', ARRAY['UnipolSai']);

INSERT INTO public.policies (company_id, name, type, description, tags) VALUES
(
  (SELECT id FROM public.companies WHERE name = 'Generali Italia' LIMIT 1),
  'Globale Fabbricati',
  'domestica',
  'Polizza globale per fabbricati civili',
  ARRAY['fenomeno elettrico', 'incendio', 'furto']
);

-- Insert sample norm refs
INSERT INTO public.norm_refs (code, article, text, summary, tags) VALUES
('CC', '1218', 'Il debitore che nell''adempimento dell''obbligazione si vale dell''opera di terzi, risponde anche dei fatti dolosi o colposi di costoro.', 'Responsabilità per fatto degli ausiliari', ARRAY['responsabilità civile', 'ausiliario']),
('CC', '2049', 'I padroni e i committenti sono responsabili per i danni arrecati dal fatto illecito dei loro domestici e commessi nell''esercizio delle incombenze cui sono adibiti.', 'Responsabilità dei padroni e dei committenti', ARRAY['responsabilità civile', 'dipendenti']);