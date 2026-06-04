-- Add determinazione field to sections table
ALTER TABLE public.sections 
ADD COLUMN determinazione TEXT[] DEFAULT '{}';

-- Add comment explaining the field
COMMENT ON COLUMN public.sections.determinazione IS 'Types of determination for the section: Valore a Nuovo, Valore Reale, or empty';