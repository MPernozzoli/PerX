-- Add page reference and article number fields to coverages table
ALTER TABLE public.coverages 
ADD COLUMN page_reference text,
ADD COLUMN article_number text;

-- Add page reference and article number fields to sections table
ALTER TABLE public.sections 
ADD COLUMN page_reference text,
ADD COLUMN article_number text;

-- Add page reference and article number fields to common_limits table
ALTER TABLE public.common_limits 
ADD COLUMN page_reference text,
ADD COLUMN article_number text;