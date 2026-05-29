-- Add new fields to coverage_items table for the enhanced guarantee system

-- Add fields for maximum type and association
ALTER TABLE public.coverage_items 
ADD COLUMN maximum_type text DEFAULT 'exact',
ADD COLUMN maximum_applies_to text[] DEFAULT '{}';

-- Add fields for deductible type and association  
ALTER TABLE public.coverage_items
ADD COLUMN deductible_type text DEFAULT 'exact',
ADD COLUMN deductible_percentage text,
ADD COLUMN deductible_minimum text,
ADD COLUMN deductible_maximum text,
ADD COLUMN deductible_applies_to text[] DEFAULT '{}';

-- Add field for exclusions association
ALTER TABLE public.coverage_items
ADD COLUMN exclusions_apply_to text[] DEFAULT '{}';