-- Add emoji field to sections table for custom icons
ALTER TABLE public.sections 
ADD COLUMN emoji text DEFAULT '📋';

-- Create a table for multiple coverages per policy edition
CREATE TABLE public.coverage_items (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  coverage_id uuid NOT NULL REFERENCES public.coverages(id) ON DELETE CASCADE,
  guarantee_name text NOT NULL,
  guarantee_group text NOT NULL DEFAULT 'FE',
  order_index integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS on coverage_items
ALTER TABLE public.coverage_items ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for coverage_items
CREATE POLICY "Anyone can view coverage items" 
ON public.coverage_items 
FOR SELECT 
USING (true);

CREATE POLICY "Authenticated users can manage coverage items" 
ON public.coverage_items 
FOR ALL 
USING (true);