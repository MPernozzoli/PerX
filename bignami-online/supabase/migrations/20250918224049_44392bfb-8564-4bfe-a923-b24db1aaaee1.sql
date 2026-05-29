-- Create guarantee_damage_definitions table for "definizione dal danno"
CREATE TABLE public.guarantee_damage_definitions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  coverage_item_id UUID NOT NULL,
  definition_type TEXT NOT NULL CHECK (definition_type IN ('a_nuovo', 'vsu_si', 'massimo_doppio', 'massimo_triplo')),
  notes TEXT,
  page_reference TEXT,
  article_number TEXT,
  applies_to TEXT[] DEFAULT '{}',
  order_index INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.guarantee_damage_definitions ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Anyone can view guarantee damage definitions" 
ON public.guarantee_damage_definitions 
FOR SELECT 
USING (true);

CREATE POLICY "Authenticated users can manage guarantee damage definitions" 
ON public.guarantee_damage_definitions 
FOR ALL 
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- Add indexes for performance
CREATE INDEX idx_guarantee_damage_definitions_coverage_item_id ON public.guarantee_damage_definitions(coverage_item_id);
CREATE INDEX idx_guarantee_damage_definitions_order ON public.guarantee_damage_definitions(coverage_item_id, order_index);