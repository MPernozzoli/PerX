-- Create tables for multiple conditions per guarantee

-- Table for multiple maximums per guarantee
CREATE TABLE public.guarantee_maximums (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  coverage_item_id uuid NOT NULL REFERENCES public.coverage_items(id) ON DELETE CASCADE,
  on_frontespizio boolean DEFAULT false,
  exact_value text,
  percentage_of_party text,
  minimum_value text,
  maximum_value text,
  notes text,
  page_reference text,
  article_number text,
  applies_to text[], -- Array of section IDs
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  order_index integer DEFAULT 0
);

-- Table for multiple deductibles per guarantee
CREATE TABLE public.guarantee_deductibles (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  coverage_item_id uuid NOT NULL REFERENCES public.coverage_items(id) ON DELETE CASCADE,
  exact_value text,
  on_frontespizio boolean DEFAULT false,
  percentage text,
  minimum_value text,
  maximum_value text,
  notes text,
  page_reference text,
  article_number text,
  applies_to text[], -- Array of section IDs
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  order_index integer DEFAULT 0
);

-- Table for multiple exclusion groups per guarantee
CREATE TABLE public.guarantee_exclusion_groups (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  coverage_item_id uuid NOT NULL REFERENCES public.coverage_items(id) ON DELETE CASCADE,
  exclusions text[] NOT NULL, -- Array of exclusion texts
  page_reference text,
  article_number text,
  applies_to text[], -- Array of section IDs
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  order_index integer DEFAULT 0
);

-- Enable RLS on all new tables
ALTER TABLE public.guarantee_maximums ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guarantee_deductibles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guarantee_exclusion_groups ENABLE ROW LEVEL SECURITY;

-- Create policies for guarantee_maximums
CREATE POLICY "Anyone can view guarantee maximums" 
ON public.guarantee_maximums 
FOR SELECT 
USING (true);

CREATE POLICY "Authenticated users can manage guarantee maximums" 
ON public.guarantee_maximums 
FOR ALL 
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- Create policies for guarantee_deductibles
CREATE POLICY "Anyone can view guarantee deductibles" 
ON public.guarantee_deductibles 
FOR SELECT 
USING (true);

CREATE POLICY "Authenticated users can manage guarantee deductibles" 
ON public.guarantee_deductibles 
FOR ALL 
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- Create policies for guarantee_exclusion_groups
CREATE POLICY "Anyone can view guarantee exclusion groups" 
ON public.guarantee_exclusion_groups 
FOR SELECT 
USING (true);

CREATE POLICY "Authenticated users can manage guarantee exclusion groups" 
ON public.guarantee_exclusion_groups 
FOR ALL 
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- Add indexes for better performance
CREATE INDEX idx_guarantee_maximums_coverage_item_id ON public.guarantee_maximums(coverage_item_id);
CREATE INDEX idx_guarantee_deductibles_coverage_item_id ON public.guarantee_deductibles(coverage_item_id);
CREATE INDEX idx_guarantee_exclusion_groups_coverage_item_id ON public.guarantee_exclusion_groups(coverage_item_id);