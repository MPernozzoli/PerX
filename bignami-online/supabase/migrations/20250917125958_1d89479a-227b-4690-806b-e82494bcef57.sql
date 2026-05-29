-- Drop the complex assignment table since we don't need it
DROP TABLE IF EXISTS public.section_guarantee_assignments;

-- Keep the guarantee-specific fields in coverage_items (these are correct)
-- coverage_items already has: maximum_value, maximum_page_reference, maximum_article_number, 
-- deductible_value, deductible_page_reference, deductible_article_number,
-- guarantee_exclusions, exclusions_page_reference, exclusions_article_number

-- Add exclusions field back to sections (for common section exclusions)
ALTER TABLE public.sections 
ADD COLUMN IF NOT EXISTS exclusions TEXT[];