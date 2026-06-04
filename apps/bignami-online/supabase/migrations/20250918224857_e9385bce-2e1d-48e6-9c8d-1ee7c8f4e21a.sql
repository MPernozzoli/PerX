-- Add "valore_stato_uso" option to damage definitions
ALTER TABLE public.guarantee_damage_definitions 
DROP CONSTRAINT guarantee_damage_definitions_definition_type_check;

ALTER TABLE public.guarantee_damage_definitions 
ADD CONSTRAINT guarantee_damage_definitions_definition_type_check 
CHECK (definition_type IN ('a_nuovo', 'vsu_si', 'massimo_doppio', 'massimo_triplo', 'valore_stato_uso'));