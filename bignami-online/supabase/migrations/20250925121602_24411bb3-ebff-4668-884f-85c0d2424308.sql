-- Create user roles enum
CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');

-- Create user_roles table
CREATE TABLE public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    role app_role NOT NULL DEFAULT 'user',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    UNIQUE (user_id, role)
);

-- Enable RLS
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Create security definer function to check roles
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

-- Create RLS policies
CREATE POLICY "Users can view their own roles"
ON public.user_roles
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all roles"
ON public.user_roles
FOR SELECT
USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can manage all roles"
ON public.user_roles
FOR ALL
USING (public.has_role(auth.uid(), 'admin'));

-- Update edit_history table to support approval workflow
ALTER TABLE public.edit_history 
ADD COLUMN IF NOT EXISTS approved_by UUID,
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Create bulk_imports table for Excel uploads
CREATE TABLE public.bulk_imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    filename TEXT NOT NULL,
    file_url TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    ai_analysis JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    processed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    imported_policies_count INTEGER DEFAULT 0
);

-- Enable RLS on bulk_imports
ALTER TABLE public.bulk_imports ENABLE ROW LEVEL SECURITY;

-- Create policies for bulk_imports
CREATE POLICY "Users can view their own imports"
ON public.bulk_imports
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can create imports"
ON public.bulk_imports
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all imports"
ON public.bulk_imports
FOR SELECT
USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can update all imports"
ON public.bulk_imports
FOR UPDATE
USING (public.has_role(auth.uid(), 'admin'));

-- Insert admin role for massimo.pernozzoli
-- First we need to get the user_id from profiles table
DO $$
DECLARE
    admin_user_id UUID;
BEGIN
    -- Get the user ID for massimo.pernozzoli
    SELECT id INTO admin_user_id
    FROM public.profiles
    WHERE email = 'massimo.pernozzoli@gmail.com';
    
    -- If user exists, assign admin role
    IF admin_user_id IS NOT NULL THEN
        INSERT INTO public.user_roles (user_id, role)
        VALUES (admin_user_id, 'admin')
        ON CONFLICT (user_id, role) DO NOTHING;
    END IF;
END $$;