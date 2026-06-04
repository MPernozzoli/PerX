-- Add new fields for value types and risk assessment
ALTER TABLE public.coverages 
ADD COLUMN value_type text DEFAULT 'valore_intero',
ADD COLUMN primo_rischio_value text;

ALTER TABLE public.sections 
ADD COLUMN value_type text DEFAULT 'valore_intero',
ADD COLUMN primo_rischio_value text;

-- Add comments for clarity
COMMENT ON COLUMN public.coverages.value_type IS 'valore_intero, primo_rischio_assoluto, primo_rischio_assoluto_fino_a';
COMMENT ON COLUMN public.coverages.primo_rischio_value IS 'Value when value_type is primo_rischio_assoluto_fino_a';
COMMENT ON COLUMN public.sections.value_type IS 'valore_intero, primo_rischio_assoluto, primo_rischio_assoluto_fino_a';
COMMENT ON COLUMN public.sections.primo_rischio_value IS 'Value when value_type is primo_rischio_assoluto_fino_a';