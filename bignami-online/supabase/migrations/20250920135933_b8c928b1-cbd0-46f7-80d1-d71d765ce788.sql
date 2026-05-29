-- Create guarantee_groups table
CREATE TABLE public.guarantee_groups (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  is_active boolean NOT NULL DEFAULT true
);

-- Enable RLS
ALTER TABLE public.guarantee_groups ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Anyone can view guarantee groups" 
ON public.guarantee_groups 
FOR SELECT 
USING (true);

CREATE POLICY "Authenticated users can manage guarantee groups" 
ON public.guarantee_groups 
FOR ALL 
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- Insert standard guarantee groups
INSERT INTO public.guarantee_groups (code, name) VALUES
('FE', 'Fenomeno Elettrico'),
('AC', 'Acqua Condotta'),
('FA', 'Fenomeni Atmosferici'),
('FUR', 'Furto'),
('INC', 'Incendio'),
('RC', 'Responsabilità Civile'),
('CR', 'Cristalli');