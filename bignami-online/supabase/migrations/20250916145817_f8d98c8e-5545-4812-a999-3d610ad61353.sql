-- Fix search_path security issue in functions
CREATE OR REPLACE FUNCTION public.has_studio_role(_studio_id UUID, _user_id UUID, _role studio_role)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
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
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.studio_members
    WHERE studio_id = _studio_id 
    AND user_id = _user_id
  )
$$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;