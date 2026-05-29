-- Drop the section_guarantee_conditions table since we're changing approach
DROP TABLE IF EXISTS public.section_guarantee_conditions;

-- Add guarantee-specific fields to coverage_items
ALTER TABLE public.coverage_items 
ADD COLUMN IF NOT EXISTS maximum_value TEXT,
ADD COLUMN IF NOT EXISTS maximum_page_reference TEXT,
ADD COLUMN IF NOT EXISTS maximum_article_number TEXT,
ADD COLUMN IF NOT EXISTS deductible_value TEXT,
ADD COLUMN IF NOT EXISTS deductible_page_reference TEXT,
ADD COLUMN IF NOT EXISTS deductible_article_number TEXT,
ADD COLUMN IF NOT EXISTS guarantee_exclusions TEXT[],
ADD COLUMN IF NOT EXISTS exclusions_page_reference TEXT,
ADD COLUMN IF NOT EXISTS exclusions_article_number TEXT;

-- Create junction table for section-guarantee assignments with specific values
CREATE TABLE IF NOT EXISTS public.section_guarantee_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  section_id UUID NOT NULL REFERENCES public.sections(id) ON DELETE CASCADE,
  coverage_item_id UUID NOT NULL REFERENCES public.coverage_items(id) ON DELETE CASCADE,
  -- Override values (if null, use the default from coverage_item)
  override_maximum_value TEXT,
  override_maximum_page_reference TEXT,
  override_maximum_article_number TEXT,
  override_deductible_value TEXT,
  override_deductible_page_reference TEXT,
  override_deductible_article_number TEXT,
  override_guarantee_exclusions TEXT[],
  override_exclusions_page_reference TEXT,
  override_exclusions_article_number TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(section_id, coverage_item_id)
);

-- Enable RLS on the new table
ALTER TABLE public.section_guarantee_assignments ENABLE ROW LEVEL SECURITY;

-- Create policies for section_guarantee_assignments
CREATE POLICY "Anyone can view section guarantee assignments" 
ON public.section_guarantee_assignments 
FOR SELECT 
USING (true);

CREATE POLICY "Authenticated users can manage section guarantee assignments" 
ON public.section_guarantee_assignments 
FOR ALL 
USING (true);