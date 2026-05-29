-- Add new fields to coverage_items table for guarantee details
ALTER TABLE public.coverage_items 
ADD COLUMN description text,
ADD COLUMN value_type text DEFAULT 'valore_intero',
ADD COLUMN primo_rischio_value text,
ADD COLUMN common_exclusions text[];