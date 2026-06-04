-- Add exact_name field to sections table
ALTER TABLE public.sections ADD COLUMN exact_name TEXT;

-- Add exact_name field to coverage_items table  
ALTER TABLE public.coverage_items ADD COLUMN exact_name TEXT;